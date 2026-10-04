import Foundation

final class MTeamAdapter: SiteAdapter {
    private var _siteConfig: SiteConfig!
    private var client: HttpClient!
    private var _discountMapping: [String: String]?
    private var _tagMapping: [String: String]?

    var siteConfig: SiteConfig {
        _siteConfig
    }

    func initialize(_ config: SiteConfig) async throws {
        _siteConfig = config
        await loadDiscountMapping()
        await loadTagMapping()
        var base = config.baseUrl.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        client = HttpClient(baseURL: base)
    }

    private func loadDiscountMapping() async {
        let template = await SiteConfigService.shared.getTemplateById("", siteType: .mteam)
        if let template {
            _discountMapping = template.discountMapping
        }
        let specialMapping = await SiteConfigService.shared.getDiscountMapping(_siteConfig.baseUrl)
        if !specialMapping.isEmpty {
            for (key, value) in specialMapping {
                _discountMapping?[key] = value
            }
        }
    }

    private func loadTagMapping() async {
        let template = await SiteConfigService.shared.getTemplateById("", siteType: .mteam)
        if let template {
            _tagMapping = template.tagMapping
        }
    }

    private func parseTagType(_ str: String?) -> TagType? {
        guard let str, !str.isEmpty else { return nil }

        let mapping = _tagMapping ?? [:]
        guard let enumName = mapping[str] else { return nil }

        for type in TagType.allCases {
            if type.rawValue.lowercased() == enumName.lowercased() {
                return type
            }
            if type.content == enumName {
                return type
            }
        }
        return nil
    }

    private func parseDiscountType(_ str: String?) -> DiscountType {
        guard let str, !str.isEmpty else { return .normal }

        let mapping = _discountMapping ?? [:]
        guard let enumValue = mapping[str] else { return .normal }

        if let type = DiscountType(rawValue: enumValue) {
            return type
        }
        return .normal
    }

    private func makeHeaders() -> [String: String] {
        var headers: [String: String] = [
            "accept": "application/json, text/plain, */*"
        ]
        let siteKey = _siteConfig.apiKey ?? ""
        if !siteKey.isEmpty {
            headers["x-api-key"] = siteKey
        }
        return headers
    }

    private func postRequest(_ path: String) -> HTTPRequest {
        HTTPRequest(path, method: .post, headers: makeHeaders())
    }

    private func jsonRequest(_ path: String, _ body: [String: Any]) -> HTTPRequest {
        HTTPRequest(path, method: .post, headers: makeHeaders(), body: .json(body))
    }

    private func multipartRequest(_ path: String, _ fields: [(String, String)]) -> HTTPRequest {
        HTTPRequest(path, method: .post, headers: makeHeaders(), body: multipartBody(fields))
    }

    private func multipartBody(_ fields: [(String, String)]) -> HTTPBody {
        let boundary = "--dio-boundary-\(UInt32.random(in: 0..<UInt32.max))"
        var data = Data()
        for (name, value) in fields {
            data.append(Data("--\(boundary)\r\n".utf8))
            let encodedName = name
                .replacingOccurrences(of: "\r\n", with: "%0D%0A")
                .replacingOccurrences(of: "\r", with: "%0D%0A")
                .replacingOccurrences(of: "\n", with: "%0D%0A")
                .replacingOccurrences(of: "\"", with: "%22")
            data.append(Data("content-disposition: form-data; name=\"\(encodedName)\"\r\n\r\n".utf8))
            data.append(Data(value.utf8))
            data.append(Data("\r\n".utf8))
        }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return .raw(data, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    private func fallbackMessage(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "未知错误" }
        return dartToString(value)
    }

    private func jsonString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return dartToString(value)
    }

    private func jsonIntOrZero(_ value: Any?) -> Int {
        guard let value, !(value is NSNull) else { return 0 }
        return dartParseInt(value) ?? 0
    }

    private func parseLooseBool(_ value: Any?) -> Bool {
        if let bool = strictBool(value) {
            return bool
        }
        return dartToString(value).lowercased() == "true"
    }

    private func isApiSuccess(_ data: [String: Any]) -> Bool {
        dartToString(data["code"]) == "0"
    }

    private func dataFromBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1024 {
            return formatGrouped2(gb / 1024.0) + " TB"
        }
        return formatGrouped2(gb) + " GB"
    }

    private func formatGrouped2(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    func fetchMemberProfile(apiKey: String?) async throws -> MemberProfile {
        do {
            let resp = try await client.perform(postRequest("/api/member/profile"))
            let data = try JSONCast.map(resp.bodyJSON())
            guard isApiSuccess(data) else {
                throw SiteApiException(
                    message: "获取用户资料失败: \(fallbackMessage(data["message"]))",
                    responseData: data
                )
            }

            let baseProfile = try parseMemberProfile(try JSONCast.map(data["data"]))

            var bonusPerHour: Double?
            var seedingSizeBytes: Int?

            do {
                let bonusResp = try await client.perform(postRequest("/api/tracker/mybonus"))
                let bonusData = try JSONCast.map(bonusResp.bodyJSON())
                if isApiSuccess(bonusData),
                    let bonusPayload = try JSONCast.optionalMap(bonusData["data"]),
                    let formulaParams = try JSONCast.optionalMap(bonusPayload["formulaParams"]),
                    let finalBs = formulaParams["finalBs"],
                    !(finalBs is NSNull)
                {
                    bonusPerHour = Double(dartToString(finalBs))
                }
            } catch {
            }

            do {
                let seedResp = try await client.perform(postRequest("/api/tracker/myPeerStatistics"))
                let seedData = try JSONCast.map(seedResp.bodyJSON())
                if isApiSuccess(seedData),
                    let seedPayload = try JSONCast.optionalMap(seedData["data"]),
                    let seederSize = seedPayload["seederSize"],
                    !(seederSize is NSNull)
                {
                    seedingSizeBytes = dartParseInt(seederSize)
                }
            } catch {
            }

            return MemberProfile(
                username: baseProfile.username,
                bonus: baseProfile.bonus,
                shareRate: baseProfile.shareRate,
                uploadedBytes: baseProfile.uploadedBytes,
                downloadedBytes: baseProfile.downloadedBytes,
                uploadedBytesString: baseProfile.uploadedBytesString,
                downloadedBytesString: baseProfile.downloadedBytesString,
                userId: baseProfile.userId,
                passKey: baseProfile.passKey,
                lastAccess: baseProfile.lastAccess,
                bonusPerHour: bonusPerHour,
                seedingSizeBytes: seedingSizeBytes
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取用户资料")
        }
    }

    private func parseMemberProfile(_ json: [String: Any]) throws -> MemberProfile {
        let mc = try JSONCast.optionalMap(json["memberCount"])
        let memberStatus = try JSONCast.optionalMap(json["memberStatus"])

        let uploadedBytes = jsonIntOrZero(mc?["uploaded"])
        let downloadedBytes = jsonIntOrZero(mc?["downloaded"])
        let lastBrowse = memberStatus.flatMap { jsonString($0["lastBrowse"]) }

        return MemberProfile(
            username: jsonString(json["username"]) ?? "",
            bonus: dartLenientDouble(mc?["bonus"]),
            shareRate: dartLenientDouble(mc?["shareRate"]),
            uploadedBytes: uploadedBytes,
            downloadedBytes: downloadedBytes,
            uploadedBytesString: dataFromBytes(uploadedBytes),
            downloadedBytesString: dataFromBytes(downloadedBytes),
            passKey: nil,
            lastAccess: try parseDateTimeCustom(lastBrowse, fieldName: "lastAccess")
        )
    }

    func searchTorrents(
        keyword: String?,
        pageNumber: Int,
        pageSize: Int,
        onlyFav: Int?,
        additionalParams: [String: Any]?
    ) async throws -> TorrentSearchResult {
        var requestData: [String: Any] = [
            "visible": 1,
            "pageNumber": pageNumber,
            "pageSize": pageSize
        ]

        if let keyword {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                requestData["keyword"] = trimmed
            }
        }
        if let onlyFav {
            requestData["onlyFav"] = onlyFav
        }

        if let additionalParams {
            for (key, value) in additionalParams {
                requestData[key] = value
            }
        }

        do {
            let resp = try await client.perform(jsonRequest("/api/torrent/search", requestData))
            let data = try JSONCast.map(resp.bodyJSON())
            guard isApiSuccess(data) else {
                throw SiteApiException(
                    message: "搜索失败: \(fallbackMessage(data["message"]))",
                    responseData: data
                )
            }

            let searchData = try JSONCast.map(data["data"])
            let rawList = try JSONCast.optionalList(searchData["data"]) ?? []

            var historyMap: [String: Any] = [:]
            var peerMap: [String: Any] = [:]

            if !rawList.isEmpty {
                do {
                    let tids: [String] = try rawList.map { element in
                        let map = try JSONCast.map(element)
                        return self.jsonString(map["id"]) ?? ""
                    }
                    let historyData = try await self.queryHistory(tids: tids)
                    historyMap = try JSONCast.optionalMap(historyData["historyMap"]) ?? [:]
                    peerMap = try JSONCast.optionalMap(historyData["peerMap"]) ?? [:]
                } catch {
                }
            }

            return try parseTorrentSearchResult(
                searchData,
                historyMap: historyMap,
                peerMap: peerMap
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "搜索种子")
        }
    }

    private func parseTorrentSearchResult(
        _ json: [String: Any],
        historyMap: [String: Any]?,
        peerMap: [String: Any]?
    ) throws -> TorrentSearchResult {
        let list = try JSONCast.optionalList(json["data"]) ?? []
        var items: [TorrentItem] = []
        for element in list {
            items.append(
                try parseTorrentItem(
                    try JSONCast.map(element),
                    historyMap: historyMap,
                    peerMap: peerMap
                )
            )
        }

        return TorrentSearchResult(
            pageNumber: jsonIntOrZero(json["pageNumber"]),
            pageSize: jsonIntOrZero(json["pageSize"]),
            total: jsonIntOrZero(json["total"]),
            totalPages: jsonIntOrZero(json["totalPages"]),
            items: items
        )
    }

    private func parseTorrentItem(
        _ json: [String: Any],
        historyMap: [String: Any]?,
        peerMap: [String: Any]?
    ) throws -> TorrentItem {
        let status = try JSONCast.optionalMap(json["status"]) ?? [:]
        let promotionRule = try JSONCast.optionalMap(status["promotionRule"]) ?? [:]

        var imageList: [String] = []
        if let rawImages = try JSONCast.optionalList(json["imageList"]) {
            imageList = rawImages.map { dartToString($0) }
        }

        var discount = jsonString(promotionRule["discount"]) ?? jsonString(status["discount"])
        var discountEndTime = jsonString(promotionRule["endTime"])
            ?? jsonString(status["discountEndTime"])
        let toppingLevel = dartParseInt(status["toppingLevel"])
        let toppingEndTime = jsonString(status["toppingEndTime"])
        if let toppingLevel, toppingLevel == 1 {
            discount = "FREE"
            discountEndTime = toppingEndTime
        }

        let name = jsonString(json["name"]) ?? ""
        let smallDescr = jsonString(json["smallDescr"]) ?? ""

        var nameTags = TagType.matchTags(name)

        if let labelsNew = try JSONCast.optionalList(json["labelsNew"]) {
            for label in labelsNew {
                let labelStr = dartToString(label)
                if let mapped = parseTagType(labelStr), !nameTags.contains(mapped) {
                    nameTags.append(mapped)
                }
            }
        }

        let id = jsonString(json["id"]) ?? ""
        var downloadStatus = DownloadStatus.none
        if let historyMap, let historyValue = historyMap[id] {
            let history = try JSONCast.map(historyValue)
            let timesCompleted = jsonIntOrZero(history["timesCompleted"])
            if timesCompleted > 0 {
                downloadStatus = .completed
            } else if let peerMap, peerMap[id] != nil {
                downloadStatus = .downloading
            }
        }

        var parsedDiscountEndTime: Date?
        if let discountEndTime {
            parsedDiscountEndTime = try parseDateTimeCustom(
                discountEndTime,
                fieldName: "discountEndTime"
            )
        }

        return TorrentItem(
            id: id,
            name: name,
            smallDescr: smallDescr,
            discount: parseDiscountType(discount),
            discountEndTime: parsedDiscountEndTime,
            downloadUrl: nil,
            seeders: jsonIntOrZero(status["seeders"]),
            leechers: jsonIntOrZero(status["leechers"]),
            sizeBytes: jsonIntOrZero(json["size"]),
            createdDate: try parseDateTimeCustom(
                jsonString(json["createdDate"]),
                fieldName: "createdDate"
            ),
            imageList: imageList,
            cover: imageList.first ?? "",
            downloadStatus: downloadStatus,
            collection: parseLooseBool(json["collection"]),
            doubanRating: jsonString(json["doubanRating"]) ?? "N/A",
            imdbRating: jsonString(json["imdbRating"]) ?? "N/A",
            isTop: (toppingLevel ?? 0) > 0,
            tags: nameTags,
            comments: jsonIntOrZero(status["comments"])
        )
    }

    func fetchTorrentDetail(
        _ id: String,
        description: String?,
        detailUrl: String?
    ) async throws -> TorrentDetail {
        do {
            if let description, !description.isEmpty {
                return TorrentDetail(descr: description, descrHtml: description)
            }

            let resp = try await client.perform(
                multipartRequest("/api/torrent/detail", [("id", id)])
            )
            let data = try JSONCast.map(resp.bodyJSON())
            guard isApiSuccess(data) else {
                throw SiteApiException(
                    message: "获取种子详情失败: \(fallbackMessage(data["message"]))",
                    responseData: data
                )
            }

            return parseTorrentDetail(try JSONCast.map(data["data"]))
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取种子详情")
        }
    }

    private func parseTorrentDetail(_ json: [String: Any]) -> TorrentDetail {
        TorrentDetail(descr: jsonString(json["descr"]) ?? "")
    }

    func fetchComments(
        _ id: String,
        pageNumber: Int,
        pageSize: Int
    ) async throws -> TorrentCommentList {
        do {
            let requestData: [String: Any] = [
                "type": "TORRENT",
                "relationId": id,
                "pageNumber": pageNumber,
                "pageSize": pageSize
            ]

            let resp = try await client.perform(jsonRequest("/api/comment/fetchList", requestData))
            let data = try JSONCast.map(resp.bodyJSON())
            guard isApiSuccess(data) else {
                throw SiteApiException(
                    message: "获取评论失败: \(fallbackMessage(data["message"]))",
                    responseData: data
                )
            }

            return try TorrentCommentList.fromJson(try JSONCast.map(data["data"]))
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取评论")
        }
    }

    func genDlToken(id: String, url: String?) async throws -> String {
        do {
            let resp = try await client.perform(
                multipartRequest("/api/torrent/genDlToken", [("id", id)])
            )
            let data = try JSONCast.map(resp.bodyJSON())
            guard isApiSuccess(data) else {
                throw SiteApiException(
                    message: "生成下载链接失败: \(fallbackMessage(data["message"]))",
                    responseData: data
                )
            }
            let dlUrl = jsonString(data["data"]) ?? ""
            if dlUrl.isEmpty {
                throw SiteApiException(message: "下载链接为空", responseData: data)
            }
            return dlUrl
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "生成下载链接")
        }
    }

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        do {
            let resp = try await client.perform(
                jsonRequest("/api/tracker/queryHistory", ["tids": tids])
            )
            let data = try JSONCast.map(resp.bodyJSON())
            guard isApiSuccess(data) else {
                throw SiteApiException(
                    message: "查询下载历史失败: \(fallbackMessage(data["message"]))",
                    responseData: data
                )
            }
            return try JSONCast.map(data["data"])
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "查询下载历史")
        }
    }

    func toggleCollection(torrentId: String, make: Bool) async throws {
        do {
            let resp = try await client.perform(
                multipartRequest(
                    "/api/torrent/collection",
                    [
                        ("id", torrentId),
                        ("make", make ? "true" : "false")
                    ]
                )
            )
            let data = try JSONCast.map(resp.bodyJSON())
            guard isApiSuccess(data) else {
                throw SiteApiException(
                    message: "收藏操作失败: \(fallbackMessage(data["message"]))",
                    responseData: data
                )
            }
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "收藏操作")
        }
    }

    func testConnection() async throws -> Bool {
        do {
            _ = try await fetchMemberProfile(apiKey: nil)
            return true
        } catch {
            return false
        }
    }

    func getSearchCategories() async throws -> [SearchCategoryConfig] {
        await SiteConfigService.shared.getDefaultSearchCategories(_siteConfig.baseUrl)
    }
}
