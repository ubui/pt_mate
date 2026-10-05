import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class QBittorrentClient: DownloaderClient, TorrentFileDownloading {
    let config: QbittorrentConfig
    let password: String

    private let onConfigUpdated: ((QbittorrentConfig) -> Void)?
    private let httpClient: HttpClient
    private let baseUrl: String
    private var authCookieHeader: String?
    private var cachedVersion: String?

    private enum QBFormField {
        case text(name: String, value: String)
        case file(name: String, filename: String, data: Data)
    }

    init(
        config: QbittorrentConfig,
        password: String,
        onConfigUpdated: ((QbittorrentConfig) -> Void)? = nil
    ) {
        self.config = config
        self.password = password
        self.onConfigUpdated = onConfigUpdated
        let base = Self.buildBase(config)
        self.baseUrl = base
        self.httpClient = HttpClient(
            baseURL: base,
            userAgent: HTTPDefaults.userAgent,
            kind: .generic
        )
    }

    var debugAuthCookieHeader: String? {
        authCookieHeader
    }

    func debugExtractCookieHeader(_ setCookieHeaders: [String]?) -> String? {
        extractCookieHeader(setCookieHeaders)
    }

    private static func buildBase(_ config: QbittorrentConfig) -> String {
        var urlStr = config.host.trimmingCharacters(in: .whitespaces)
        if urlStr.range(of: "^https?://", options: .regularExpression) == nil {
            urlStr = "http://\(urlStr)"
        }
        guard var components = URLComponents(string: urlStr) else {
            return urlStr
        }
        var resolvedPort: Int?
        if config.port > 0 {
            resolvedPort = config.port
        } else if let port = components.port {
            resolvedPort = port
        } else {
            resolvedPort = nil
        }
        components.port = resolvedPort
        if let scheme = components.scheme?.lowercased(), let resolvedPort,
           Self.isDefaultPort(scheme, resolvedPort) {
            components.port = nil
        }
        var result = components.string ?? urlStr
        if result.hasSuffix("/") {
            result = String(result.dropLast())
        }
        return result
    }

    private static func isDefaultPort(_ scheme: String, _ port: Int) -> Bool {
        switch scheme {
        case "http":
            return port == 80
        case "https":
            return port == 443
        default:
            return false
        }
    }

    private var apiPrefix: String {
        if let version = config.version, !version.isEmpty {
            let versionParts = version.components(separatedBy: ".")
            if !versionParts.isEmpty {
                let majorVersion = dartParseInt(versionParts[0]) ?? 0
                let minorVersion = versionParts.count > 1 ? (dartParseInt(versionParts[1]) ?? 0) : 0
                if majorVersion > 4 || (majorVersion == 4 && minorVersion >= 1) {
                    return "/api/v2"
                }
            }
        }
        return "/api/v2"
    }

    private func request(
        _ method: String,
        _ endpoint: String,
        headers: [String: String]? = nil,
        query: [String: Any]? = nil,
        fields: [QBFormField]? = nil,
        requireAuth: Bool = true
    ) async throws -> HTTPResponse {
        let url = baseUrl + apiPrefix + endpoint

        if requireAuth && authCookieHeader == nil {
            try await login()
        }

        var requestHeaders = headers ?? [:]
        if let cookie = authCookieHeader {
            requestHeaders["Cookie"] = cookie
        }

        let upperMethod = method.uppercased()
        guard upperMethod == "GET" || upperMethod == "POST" else {
            throw SiteServiceException(message: "HTTP method \(method) not supported")
        }

        do {
            if upperMethod == "GET" {
                return try await httpClient.perform(
                    HTTPRequest(
                        url,
                        method: .get,
                        headers: requestHeaders,
                        query: qbStringMap(query)
                    )
                )
            }
            guard let fields else {
                return try await httpClient.perform(
                    HTTPRequest(url, method: .post, headers: requestHeaders)
                )
            }
            if endpoint.contains("/torrents/add") {
                return try await httpClient.perform(
                    HTTPRequest(
                        url,
                        method: .post,
                        headers: requestHeaders,
                        body: qbMultipartBody(fields)
                    )
                )
            }
            return try await httpClient.perform(
                HTTPRequest(
                    url,
                    method: .post,
                    headers: requestHeaders,
                    body: .form(qbFormMap(fields))
                )
            )
        } catch {
            if TimeoutRetry.isTimeoutError(error) {
                throw error
            }

            let statusCode = qbErrorStatusCode(error)
            if statusCode == 403 {
                if authCookieHeader != nil {
                    authCookieHeader = nil
                    return try await request(
                        method,
                        endpoint,
                        headers: headers,
                        query: query,
                        fields: fields,
                        requireAuth: requireAuth
                    )
                }
                throw SiteServiceException(message: "Authentication failed")
            }

            if let statusCode, statusCode >= 400 {
                throw SiteServiceException(
                    message: "HTTP \(statusCode): \(qbErrorBodyText(error))"
                )
            }

            throw SiteServiceException(
                message: "Request failed: \(qbErrorMessageText(error))"
            )
        }
    }

    private func login() async throws {
        let response: HTTPResponse
        do {
            response = try await performLoginRequest()
        } catch {
            if TimeoutRetry.isTimeoutError(error) {
                throw error
            }
            throw SiteServiceException(
                message: "Login failed: \(qbErrorMessageText(error))"
            )
        }

        if !(200..<300).contains(response.statusCode) {
            throw SiteServiceException(message: "Login failed: \(response.text)")
        }

        let cookieHeader = extractCookieHeader(qbSetCookieHeaders(response))
        guard let cookieHeader, !cookieHeader.isEmpty else {
            throw SiteServiceException(
                message: "Failed to extract authentication cookies from login response"
            )
        }

        authCookieHeader = cookieHeader
    }

    private func performLoginRequest() async throws -> HTTPResponse {
        let urlString = baseUrl + apiPrefix + "/auth/login"
        guard let url = URL(string: urlString) else {
            throw SiteServiceException(message: "无效的请求地址", detail: urlString)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue(HTTPDefaults.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.httpBody = Data(
            qbEncodedFormBody([
                "username": config.username,
                "password": password,
            ]).utf8
        )

        let session = SessionFactory.shared.session(for: .generic)
        let (data, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw SiteServiceException(message: "响应格式异常")
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key.lowercased()] = value
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ApiExceptionAdapter.classifyResponse(
                statusCode: http.statusCode,
                body: HTTPCharset.decode(data, contentType: headers["content-type"]),
                action: "请求"
            )
        }

        return HTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            data: data,
            url: http.url ?? url,
            redirectLocations: []
        )
    }

    private func extractCookieHeader(_ setCookieHeaders: [String]?) -> String? {
        guard let setCookieHeaders, !setCookieHeaders.isEmpty else {
            return nil
        }

        var cookieMap: [String: String] = [:]
        var cookieOrder: [String] = []

        for header in setCookieHeaders {
            let firstPart = header
                .split(separator: ";", omittingEmptySubsequences: false)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard let separatorIndex = firstPart.firstIndex(of: "=") else {
                continue
            }
            if firstPart.distance(from: firstPart.startIndex, to: separatorIndex) <= 0 {
                continue
            }

            let name = String(firstPart[firstPart.startIndex..<separatorIndex])
                .trimmingCharacters(in: .whitespaces)
            let value = String(firstPart[firstPart.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                continue
            }

            if cookieMap[name] == nil {
                cookieOrder.append(name)
            }
            cookieMap[name] = value
        }

        if cookieMap.isEmpty {
            return nil
        }

        return cookieOrder
            .map { "\($0)=\(cookieMap[$0] ?? "")" }
            .joined(separator: "; ")
    }

    private func qbSetCookieHeaders(_ response: HTTPResponse) -> [String]? {
        guard let value = response.headers["set-cookie"], !value.isEmpty else {
            return nil
        }
        return [value]
    }

    func testConnection() async throws {
        do {
            try await login()
            _ = try await getVersion()
        } catch {
            throw SiteServiceException(
                message: "Connection test failed: \(qbErrorMessageText(error))"
            )
        }
    }

    func getTransferInfo() async throws -> TransferInfo {
        let response = try await request("GET", "/transfer/info")
        let data = try JSONCast.map(try response.bodyJSON())
        return TransferInfo(
            upSpeed: qbIntOrZero(data["up_info_speed"]),
            dlSpeed: qbIntOrZero(data["dl_info_speed"]),
            upTotal: qbIntOrZero(data["up_info_data"]),
            dlTotal: qbIntOrZero(data["dl_info_data"])
        )
    }

    func getServerState() async throws -> ServerState {
        let response = try await request("GET", "/sync/maindata")
        let data = try JSONCast.map(try response.bodyJSON())

        let serverState = try JSONCast.optionalMap(data["server_state"]) ?? [:]
        var freeSpaceOnDisk = 0
        if let raw = serverState["free_space_on_disk"] {
            if let strictInt = strictIntValue(raw) {
                freeSpaceOnDisk = strictInt
            } else {
                freeSpaceOnDisk = dartParseInt(raw) ?? 0
            }
        }

        return ServerState(freeSpaceOnDisk: freeSpaceOnDisk)
    }

    func getTasks(params: GetTasksParams?) async throws -> [DownloadTask] {
        var queryParams: [String: Any] = [:]

        if let params {
            if let filter = params.filter { queryParams["filter"] = filter }
            if let category = params.category { queryParams["category"] = category }
            if let tag = params.tag { queryParams["tag"] = tag }
            if let sort = params.sort { queryParams["sort"] = sort }
            if let reverse = params.reverse { queryParams["reverse"] = reverse }
            if let limit = params.limit { queryParams["limit"] = limit }
            if let offset = params.offset { queryParams["offset"] = offset }
        }

        let response = try await request(
            "GET",
            "/torrents/info",
            query: queryParams
        )
        let data = try JSONCast.list(try response.bodyJSON())

        var tasks: [DownloadTask] = []
        tasks.reserveCapacity(data.count)
        for item in data {
            tasks.append(convertToDownloadTask(try JSONCast.map(item)))
        }
        return tasks
    }

    func addTask(_ params: AddTaskParams, siteConfig: SiteConfig?) async throws {
        var fields: [QBFormField] = []

        var url = params.url
        var forceRelay = false
        if url.hasPrefix("##") {
            url = String(url.dropFirst(2))
            forceRelay = true
        }

        let useRelay = config.useLocalRelay || forceRelay
        if !useRelay {
            fields.append(.text(name: "urls", value: url))
        } else {
            let torrentData = try await downloadTorrentFileCommon(
                url,
                siteConfig: siteConfig
            )
            fields.append(.file(
                name: "torrents",
                filename: "ptmate.torrent",
                data: torrentData
            ))
        }

        if let category = params.category {
            fields.append(.text(name: "category", value: category))
        }
        if let tags = params.tags, !tags.isEmpty {
            fields.append(.text(name: "tags", value: tags.joined(separator: ",")))
        }
        if let savePath = params.savePath {
            fields.append(.text(name: "savepath", value: savePath))
        }
        if let autoTMM = params.autoTMM {
            fields.append(.text(name: "autoTMM", value: autoTMM ? "true" : "false"))
        }
        if let startPaused = params.startPaused {
            fields.append(.text(
                name: "stopped",
                value: startPaused ? "true" : "false"
            ))
            fields.append(.text(name: "stopCondition", value: "None"))
        }

        _ = try await request("POST", "/torrents/add", fields: fields)
    }

    private func pauseApiPath(_ version: String?) -> String {
        guard let version else {
            return "/torrents/pause"
        }

        let cleanVersion = version.lowercased().hasPrefix("v")
            ? String(version.dropFirst())
            : version

        let versionParts = cleanVersion.components(separatedBy: ".")
        if !versionParts.isEmpty,
           let majorVersion = dartParseInt(versionParts[0]),
           majorVersion >= 5 {
            return "/torrents/stop"
        }
        return "/torrents/pause"
    }

    private func resumeApiPath(_ version: String?) -> String {
        guard let version else {
            return "/torrents/resume"
        }

        let cleanVersion = version.lowercased().hasPrefix("v")
            ? String(version.dropFirst())
            : version

        let versionParts = cleanVersion.components(separatedBy: ".")
        if !versionParts.isEmpty,
           let majorVersion = dartParseInt(versionParts[0]),
           majorVersion >= 5 {
            return "/torrents/start"
        }
        return "/torrents/resume"
    }

    func pauseTasks(_ hashes: [String]) async throws {
        var version = cachedVersion ?? config.version
        if version?.isEmpty ?? true {
            do {
                version = try await getVersion()
            } catch {
                version = nil
            }
        }

        _ = try await request(
            "POST",
            pauseApiPath(version),
            fields: [.text(name: "hashes", value: hashes.joined(separator: "|"))]
        )
    }

    func resumeTasks(_ hashes: [String]) async throws {
        var version = cachedVersion ?? config.version
        if version?.isEmpty ?? true {
            do {
                version = try await getVersion()
            } catch {
                version = nil
            }
        }

        _ = try await request(
            "POST",
            resumeApiPath(version),
            fields: [.text(name: "hashes", value: hashes.joined(separator: "|"))]
        )
    }

    func deleteTasks(_ hashes: [String], deleteFiles: Bool) async throws {
        _ = try await request(
            "POST",
            "/torrents/delete",
            fields: [
                .text(name: "hashes", value: hashes.joined(separator: "|")),
                .text(name: "deleteFiles", value: deleteFiles ? "true" : "false"),
            ]
        )
    }

    func getCategories() async throws -> [String] {
        let response = try await request("GET", "/torrents/categories")
        let data = try JSONCast.map(try response.bodyJSON())
        return Array(data.keys)
    }

    func getTags() async throws -> [String] {
        let response = try await request("GET", "/torrents/tags")
        let data = try JSONCast.list(try response.bodyJSON())
        var tags: [String] = []
        tags.reserveCapacity(data.count)
        for item in data {
            tags.append(try JSONCast.string(item))
        }
        return tags
    }

    func getVersion() async throws -> String {
        if let cachedVersion {
            return cachedVersion
        }

        let response = try await request("GET", "/app/version")
        let version = response.text.replacingOccurrences(of: "\"", with: "")

        cachedVersion = version

        if config.version?.isEmpty ?? true {
            if let onConfigUpdated {
                onConfigUpdated(config.copyWith(version: version))
            }
        }

        return version
    }

    func getPaths() async throws -> [String] {
        let response = try await request("GET", "/torrents/info")
        let data = try JSONCast.list(try response.bodyJSON())

        var seen: Set<String> = []
        var allPaths: [String] = []

        for item in data {
            let torrent = try JSONCast.map(item)
            if let savePath = try JSONCast.optionalString(torrent["save_path"]),
               !savePath.isEmpty {
                if seen.insert(savePath).inserted {
                    allPaths.append(savePath)
                }
            }
        }

        allPaths.sort()
        return allPaths
    }

    func getUpdatedConfig() async throws -> QbittorrentConfig {
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

    func ensureVersionInfo(
        onVersionUpdated: ((QbittorrentConfig) -> Void)? = nil
    ) async throws -> QbittorrentConfig {
        if let version = config.version, !version.isEmpty {
            return config
        }

        do {
            let version = try await getVersion()
            let updatedConfig = config.copyWith(version: version)
            onVersionUpdated?(updatedConfig)
            return updatedConfig
        } catch {
            return config
        }
    }

    func pauseTaskWithVersionUpdate(
        _ hash: String,
        onConfigUpdated: ((QbittorrentConfig) -> Void)? = nil
    ) async throws {
        try await pauseTask(hash)

        if onConfigUpdated != nil {
            let updatedConfig = try await ensureVersionInfo()
            if updatedConfig != config {
                onConfigUpdated?(updatedConfig)
            }
        }
    }

    func resumeTaskWithVersionUpdate(
        _ hash: String,
        onConfigUpdated: ((QbittorrentConfig) -> Void)? = nil
    ) async throws {
        try await resumeTask(hash)

        if onConfigUpdated != nil {
            let updatedConfig = try await ensureVersionInfo()
            if updatedConfig != config {
                onConfigUpdated?(updatedConfig)
            }
        }
    }

    func dispose() {}

    private func convertToDownloadTask(_ torrent: [String: Any]) -> DownloadTask {
        return DownloadTask(
            hash: torrent["hash"] as? String ?? "",
            name: torrent["name"] as? String ?? "",
            state: torrent["state"] as? String ?? "",
            size: qbIntOrZero(torrent["size"]),
            progress: dartLenientDouble(torrent["progress"]),
            dlspeed: qbIntOrZero(torrent["dlspeed"]),
            upspeed: qbIntOrZero(torrent["upspeed"]),
            eta: qbIntOrZero(torrent["eta"]),
            category: torrent["category"] as? String ?? "",
            tags: qbTags(torrent["tags"]),
            completionOn: qbIntOrZero(torrent["completion_on"]),
            contentPath: torrent["content_path"] as? String ?? "",
            addedOn: qbIntOrZero(torrent["added_on"]),
            amountLeft: qbIntOrZero(torrent["amount_left"]),
            ratio: dartLenientDouble(torrent["ratio"]),
            timeActive: qbIntOrZero(torrent["time_active"]),
            uploaded: qbIntOrZero(torrent["uploaded"])
        )
    }

    private func qbIntOrZero(_ value: Any?) -> Int {
        if let int = strictIntValue(value) {
            return int
        }
        return dartParseInt(value) ?? 0
    }

    private func qbTags(_ value: Any?) -> [String] {
        guard let value, !(value is NSNull) else {
            return []
        }
        return dartToString(value)
            .components(separatedBy: ",")
            .filter { !$0.isEmpty }
    }

    private func qbStringMap(_ params: [String: Any]?) -> [String: String] {
        guard let params else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in params {
            result[key] = dartToString(value)
        }
        return result
    }

    private func qbFormMap(_ fields: [QBFormField]) -> [String: String] {
        var result: [String: String] = [:]
        for field in fields {
            if case .text(let name, let value) = field {
                result[name] = value
            }
        }
        return result
    }

    private func qbEncodedFormBody(_ params: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }

    private func qbMultipartBody(_ fields: [QBFormField]) -> HTTPBody {
        let boundary = "--dio-boundary-\(UInt32.random(in: 0..<UInt32.max))"
        var data = Data()
        for field in fields {
            data.append(Data("--\(boundary)\r\n".utf8))
            switch field {
            case .text(let name, let value):
                data.append(Data(
                    "content-disposition: form-data; name=\"\(qbEncodeMultipartName(name))\"\r\n\r\n".utf8
                ))
                data.append(Data(value.utf8))
                data.append(Data("\r\n".utf8))
            case .file(let name, let filename, let fileData):
                data.append(Data(
                    "content-disposition: form-data; name=\"\(qbEncodeMultipartName(name))\"; filename=\"\(qbEncodeMultipartName(filename))\"\r\n\r\n".utf8
                ))
                data.append(fileData)
                data.append(Data("\r\n".utf8))
            }
        }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return .raw(data, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    private func qbEncodeMultipartName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "%0D%0A")
            .replacingOccurrences(of: "\r", with: "%0D%0A")
            .replacingOccurrences(of: "\n", with: "%0D%0A")
            .replacingOccurrences(of: "\"", with: "%22")
    }

    private func qbErrorStatusCode(_ error: Error) -> Int? {
        if let authError = error as? SiteAuthenticationException {
            return authError.statusCode
        }
        if let serviceError = error as? SiteServiceException {
            return serviceError.statusCode
        }
        return nil
    }

    private func qbErrorBodyText(_ error: Error) -> String {
        if let siteError = error as? SiteException {
            return siteError.detail ?? siteError.message
        }
        return ApiExceptionAdapter.wrapError(error, action: "请求").descriptionText
    }

    private func qbErrorMessageText(_ error: Error) -> String {
        if let siteError = error as? SiteException {
            return siteError.message
        }
        return ApiExceptionAdapter.wrapError(error, action: "请求").message
    }
}
