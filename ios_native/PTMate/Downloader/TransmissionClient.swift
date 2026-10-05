import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TransmissionClient: DownloaderClient, TorrentFileDownloading {
    let config: TransmissionConfig
    let password: String

    private let onConfigUpdated: ((TransmissionConfig) -> Void)?
    private var sessionId: String?
    private var cachedVersion: String?

    init(
        config: TransmissionConfig,
        password: String,
        onConfigUpdated: ((TransmissionConfig) -> Void)? = nil
    ) {
        self.config = config
        self.password = password
        self.onConfigUpdated = onConfigUpdated
    }

    private var baseUrl: String {
        transmissionBuildBase(config)
    }

    private var rpcPath: String {
        "/transmission/rpc"
    }

    func testConnection() async throws {
        do {
            _ = try await rpcRequest("session-stats")
        } catch {
            throw SiteServiceException(
                message: "Connection test failed: \(transmissionErrorText(error))"
            )
        }
    }

    func getTransferInfo() async throws -> TransferInfo {
        let response = try await rpcRequest("session-stats")
        let cumulative = try JSONCast.optionalMap(response["cumulative-stats"]) ?? [:]
        return TransferInfo(
            upSpeed: transmissionInt(response["uploadSpeed"]),
            dlSpeed: transmissionInt(response["downloadSpeed"]),
            upTotal: transmissionInt(cumulative["uploadedBytes"]),
            dlTotal: transmissionInt(cumulative["downloadedBytes"])
        )
    }

    func getServerState() async throws -> ServerState {
        let response = try await rpcRequest("session-get")
        return ServerState(
            freeSpaceOnDisk: transmissionInt(response["download-dir-free-space"])
        )
    }

    func getTasks(params: GetTasksParams?) async throws -> [DownloadTask] {
        let arguments: [String: Any] = [
            "fields": [
                "id",
                "name",
                "status",
                "totalSize",
                "percentDone",
                "rateDownload",
                "rateUpload",
                "eta",
                "labels",
                "downloadDir",
                "addedDate",
                "leftUntilDone",
                "uploadRatio",
                "activityDate",
                "hashString",
                "uploadedEver",
            ]
        ]

        let response = try await rpcRequest("torrent-get", arguments: arguments)
        let torrents = try JSONCast.optionalList(response["torrents"]) ?? []

        var tasks: [DownloadTask] = []
        for torrent in torrents {
            tasks.append(convertToDownloadTask(try JSONCast.map(torrent)))
        }
        return tasks
    }

    func addTask(_ params: AddTaskParams, siteConfig: SiteConfig?) async throws {
        var arguments: [String: Any] = [:]

        var url = params.url
        if url.hasPrefix("##") {
            url = String(url.dropFirst(2))
        }

        if url.hasPrefix("magnet:") {
            arguments["filename"] = url
        } else {
            let torrentData = try await downloadTorrentFileCommon(url, siteConfig: siteConfig)
            arguments["metainfo"] = torrentData.base64EncodedString()
        }

        if let savePath = params.savePath {
            arguments["download-dir"] = savePath
        }

        var labels: [String] = []
        if let category = params.category, !category.isEmpty {
            labels.append(category)
        }
        if let tags = params.tags, !tags.isEmpty {
            labels.append(contentsOf: tags)
        }
        if !labels.isEmpty {
            arguments["labels"] = labels
        }

        arguments["paused"] = params.startPaused == true

        _ = try await rpcRequest("torrent-add", arguments: arguments)
    }

    func pauseTasks(_ hashes: [String]) async throws {
        let ids = try await hashesToIds(hashes)
        if !ids.isEmpty {
            _ = try await rpcRequest("torrent-stop", arguments: ["ids": ids])
        }
    }

    func resumeTasks(_ hashes: [String]) async throws {
        let ids = try await hashesToIds(hashes)
        if !ids.isEmpty {
            _ = try await rpcRequest("torrent-start", arguments: ["ids": ids])
        }
    }

    func deleteTasks(_ hashes: [String], deleteFiles: Bool) async throws {
        let ids = try await hashesToIds(hashes)
        if !ids.isEmpty {
            _ = try await rpcRequest(
                "torrent-remove",
                arguments: ["ids": ids, "delete-local-data": deleteFiles]
            )
        }
    }

    func getCategories() async throws -> [String] {
        []
    }

    func getTags() async throws -> [String] {
        let response = try await rpcRequest(
            "torrent-get",
            arguments: ["fields": ["labels"]]
        )

        let torrents = try JSONCast.optionalList(response["torrents"]) ?? []
        var allLabels: [String] = []

        for torrent in torrents {
            let map = try JSONCast.map(torrent)
            let labels = try JSONCast.optionalList(map["labels"]) ?? []
            for label in labels {
                let text = dartToString(label)
                if !allLabels.contains(text) {
                    allLabels.append(text)
                }
            }
        }

        return allLabels
    }

    func getVersion() async throws -> String {
        if let cachedVersion {
            return cachedVersion
        }

        let response = try await rpcRequest("session-get")
        let version = response["version"] as? String ?? "Unknown"

        cachedVersion = version

        if config.version == nil || config.version?.isEmpty == true {
            if let onConfigUpdated {
                onConfigUpdated(config.copyWith(version: version))
            }
        }

        return version
    }

    func getPaths() async throws -> [String] {
        let response = try await rpcRequest(
            "torrent-get",
            arguments: ["fields": ["downloadDir"]]
        )

        let torrents = try JSONCast.optionalList(response["torrents"]) ?? []
        var allPaths: [String] = []

        for torrent in torrents {
            let map = try JSONCast.map(torrent)
            if let downloadDir = map["downloadDir"] as? String, !downloadDir.isEmpty {
                if !allPaths.contains(downloadDir) {
                    allPaths.append(downloadDir)
                }
            }
        }

        return allPaths.sorted()
    }

    func getUpdatedConfig() async -> TransmissionConfig {
        if let version = config.version, !version.isEmpty {
            return config
        }

        do {
            let version = try await getVersion()
            return config.copyWith(version: version)
        } catch {
            return config
        }
    }

    func dispose() {}

    private func rpcRequest(
        _ method: String,
        arguments: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let url = baseUrl + rpcPath

        var requestBody: [String: Any] = ["method": method]
        if let arguments {
            requestBody["arguments"] = arguments
        }

        var requestHeaders: [String: String] = ["Content-Type": "application/json"]

        if !config.username.isEmpty {
            let credentials = Data("\(config.username):\(password)".utf8).base64EncodedString()
            requestHeaders["Authorization"] = "Basic \(credentials)"
        }

        if let sessionId {
            requestHeaders["X-Transmission-Session-Id"] = sessionId
        }

        let response: TransmissionRPCResponse
        do {
            response = try await performPost(url: url, headers: requestHeaders, body: requestBody)
        } catch {
            if TimeoutRetry.isTimeoutError(error) {
                throw error
            }
            throw SiteServiceException(
                message: "Request failed: \(transmissionErrorText(error))"
            )
        }

        if response.statusCode == 200 {
            let json = try JSONSerialization.jsonObject(with: response.body)
            let responseData = try JSONCast.map(json)
            let result = responseData["result"] as? String
            if result == "success" {
                return try JSONCast.optionalMap(responseData["arguments"]) ?? [:]
            }
            throw SiteServiceException(
                message: "RPC request failed: \(dartToString(responseData["result"]))"
            )
        }

        if (200..<300).contains(response.statusCode) {
            throw SiteServiceException(
                message: "HTTP \(response.statusCode): \(transmissionBodyText(response.body))"
            )
        }

        if response.statusCode == 409 {
            if let refreshed = response.headers["x-transmission-session-id"] {
                sessionId = refreshed
                return try await rpcRequest(method, arguments: arguments)
            }
        }

        if response.statusCode == 401 {
            throw SiteServiceException(message: "Authentication failed")
        }

        if response.statusCode >= 400 {
            throw SiteServiceException(
                message: "HTTP \(response.statusCode): \(transmissionBodyText(response.body))"
            )
        }

        throw SiteServiceException(message: "Request failed: \(response.statusCode)")
    }

    private func performPost(
        url: String,
        headers: [String: String],
        body: [String: Any]
    ) async throws -> TransmissionRPCResponse {
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        guard let requestURL = URL(string: url) else {
            throw SiteServiceException(message: "无效的请求地址", detail: url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue(HTTPDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = bodyData

        let session = SessionFactory.shared.session(for: .generic)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SiteServiceException(message: "响应格式异常", detail: response.mimeType)
        }

        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                responseHeaders[key.lowercased()] = value
            }
        }

        return TransmissionRPCResponse(
            statusCode: http.statusCode,
            headers: responseHeaders,
            body: data
        )
    }

    private func hashesToIds(_ hashes: [String]) async throws -> [Int] {
        if hashes.isEmpty {
            return []
        }

        let response = try await rpcRequest(
            "torrent-get",
            arguments: ["fields": ["id", "hashString"]]
        )

        let torrents = try JSONCast.optionalList(response["torrents"]) ?? []
        var ids: [Int] = []

        for torrent in torrents {
            let map = try JSONCast.map(torrent)
            let hash = map["hashString"] as? String
            let id = strictIntValue(map["id"])
            if let hash, let id, hashes.contains(hash) {
                ids.append(id)
            }
        }

        return ids
    }

    private func convertToDownloadTask(_ torrent: [String: Any]) -> DownloadTask {
        let status = strictIntValue(torrent["status"]) ?? 0
        var state = DownloadTaskState.unknown
        switch status {
        case 0:
            state = DownloadTaskState.pausedDL
        case 1:
            state = DownloadTaskState.queuedDL
        case 2:
            state = DownloadTaskState.checkingDL
        case 3:
            state = DownloadTaskState.queuedDL
        case 4:
            state = DownloadTaskState.downloading
        case 5:
            state = DownloadTaskState.queuedUP
        case 6:
            state = DownloadTaskState.uploading
        default:
            state = DownloadTaskState.unknown
        }

        let percentDone = transmissionDouble(torrent["percentDone"])
        let totalSize = transmissionInt(torrent["totalSize"])
        let leftUntilDone = transmissionInt(torrent["leftUntilDone"])
        let labels = (torrent["labels"] as? [Any])?.map { dartToString($0) } ?? []

        return DownloadTask(
            hash: transmissionString(torrent["hashString"]),
            name: transmissionString(torrent["name"]),
            state: state,
            size: totalSize,
            progress: percentDone,
            dlspeed: transmissionInt(torrent["rateDownload"]),
            upspeed: transmissionInt(torrent["rateUpload"]),
            eta: transmissionInt(torrent["eta"]),
            category: "",
            tags: labels,
            completionOn: 0,
            contentPath: transmissionString(torrent["downloadDir"]),
            addedOn: transmissionInt(torrent["addedDate"]),
            amountLeft: leftUntilDone,
            ratio: transmissionDouble(torrent["uploadRatio"]),
            timeActive: transmissionInt(torrent["activityDate"])
                - transmissionInt(torrent["addedDate"]),
            uploaded: transmissionInt(torrent["uploadedEver"])
        )
    }
}

private struct TransmissionRPCResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

private func transmissionBuildBase(_ config: TransmissionConfig) -> String {
    var urlStr = config.host.trimmingCharacters(in: .whitespaces)
    if !urlStr.hasPrefix("https://") && !urlStr.hasPrefix("http://") {
        urlStr = "http://" + urlStr
    }

    guard var components = URLComponents(string: urlStr) else {
        return urlStr
    }

    var port = config.port
    if port <= 0, let existing = components.port {
        port = existing
    }
    components.port = port > 0 ? port : nil

    guard var result = components.string else {
        return urlStr
    }
    if result.hasSuffix("/") {
        result.removeLast()
    }
    return result
}

private func transmissionInt(_ value: Any?) -> Int {
    if let int = strictIntValue(value) {
        return int
    }
    return dartParseInt(value) ?? 0
}

private func transmissionDouble(_ value: Any?) -> Double {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    return dartDoubleFromString(dartToString(value ?? 0)) ?? 0
}

private func transmissionString(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else {
        return ""
    }
    if let string = value as? String {
        return string
    }
    return dartToString(value)
}

private func transmissionBodyText(_ data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) {
        return dartToString(json)
    }
    return String(decoding: data, as: UTF8.self)
}

private func transmissionErrorText(_ error: Error) -> String {
    if let siteError = error as? SiteException {
        return siteError.descriptionText
    }
    if let urlError = error as? URLError {
        return urlError.localizedDescription
    }
    return (error as NSError).localizedDescription
}