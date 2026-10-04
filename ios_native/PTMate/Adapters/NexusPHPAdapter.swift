import Foundation

final class NexusPHPAdapter: SiteAdapter, NexusPHPHelper {
    private var _siteConfig: SiteConfig!
    private var client: HttpClient!
    private var _discountMapping: [String: String]?
    private var _tagMapping: [String: String]?

    private static let whitespaceRegex = try! NSRegularExpression(
        pattern: "[\\s\\u200B-\\u200D\\uFEFF]"
    )

    var discountMapping: [String: String]? {
        _discountMapping
    }

    var tagMapping: [String: String]? {
        _tagMapping
    }

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
        let template = await SiteConfigService.shared.getTemplateById("", siteType: .nexusphp)
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
        let template = await SiteConfigService.shared.getTemplateById("", siteType: .nexusphp)
        if let template {
            _tagMapping = template.tagMapping
        }
    }

    private func buildHeaders(_ token: String?) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
        if let token, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    private func getRequest(_ path: String, query: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(
            path,
            method: .get,
            headers: buildHeaders(_siteConfig.apiKey),
            query: query
        )
    }

    private func multipartRequest(_ path: String, _ fields: [(String, String)]) -> HTTPRequest {
        HTTPRequest(
            path,
            method: .post,
            headers: buildHeaders(_siteConfig.apiKey),
            body: multipartBody(fields)
        )
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

    private func isRetSuccess(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        guard let number = value as? NSNumber, strictBool(value) == nil else { return false }
        return number.doubleValue == 0
    }

    private func messageOr(_ value: Any?, _ fallback: String) -> String {
        guard let value, !(value is NSNull) else { return fallback }
        return dartToString(value)
    }

    private func jsonString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return dartToString(value)
    }

    private func metaInt(_ meta: [String: Any]?, _ key: String, _ fallback: Int) throws -> Int {
        if let meta, let value = meta[key], !(value is NSNull) {
            return try JSONCast.int(value)
        }
        return fallback
    }

    private func stripWhitespace(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return Self.whitespaceRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: ""
        )
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
            let resp = try await client.perform(
                getRequest(
                    "/api/v1/profile",
                    query: ["include_fields[user]": "seeding_leeching_data"]
                )
            )
            let data = try JSONCast.map(resp.bodyJSON())
            if isRetSuccess(data["ret"]), let profileValue = data["data"], !(profileValue is NSNull) {
                let profileNode = try JSONCast.map(profileValue)
                return try parseMemberProfile(try JSONCast.map(profileNode["data"]))
            }
            throw SiteApiException(
                message: "获取用户资料失败: \(messageOr(data["msg"], "未知错误"))",
                responseData: data
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取用户资料")
        }
    }

    private func parseMemberProfile(_ data: [String: Any]) throws -> MemberProfile {
        let uploadedBytes = try dartLenientInt(data["uploaded"])
        let downloadedBytes = try dartLenientInt(data["downloaded"])
        let shareRateText = jsonString(data["share_ratio"]) ?? "0"

        let username: String
        if let raw = data["username"], !(raw is NSNull) {
            username = try JSONCast.string(raw)
        } else {
            username = ""
        }

        var bonusPerHour: Double?
        if let raw = data["seed_bonus_per_hour"], !(raw is NSNull) {
            bonusPerHour = try JSONCast.num(raw)
        }

        var seedingSizeBytes: Int?
        if let seedingData = try JSONCast.optionalMap(data["seeding_leeching_data"]),
            let raw = seedingData["seeding_size"], !(raw is NSNull)
        {
            seedingSizeBytes = try dartLenientInt(raw)
        }

        return MemberProfile(
            username: username,
            bonus: dartLenientDouble(data["bonus"]),
            shareRate: Double(shareRateText) ?? 0.0,
            uploadedBytes: uploadedBytes,
            downloadedBytes: downloadedBytes,
            uploadedBytesString: dataFromBytes(uploadedBytes),
            downloadedBytesString: dataFromBytes(downloadedBytes),
            userId: jsonString(data["id"]),
            passKey: nil,
            lastAccess: try parseDateTimeCustom(
                jsonString(data["last_access"]),
                fieldName: "lastAccess"
            ),
            bonusPerHour: bonusPerHour,
            seedingSizeBytes: seedingSizeBytes
        )
    }

    func searchTorrents(
        keyword: String?,
        pageNumber: Int,
        pageSize: Int,
        onlyFav: Int?,
        additionalParams: [String: Any]?
    ) async throws -> TorrentSearchResult {
        var params: [String: String] = [
            "page": String(pageNumber),
            "per_page": String(pageSize),
            "include_fields[torrent]": "download_url,has_bookmarked,active_status",
        ]

        if let keyword, !keyword.isEmpty {
            params["filter[title]"] = keyword
        }
        if let onlyFav, onlyFav > 0 {
            params["filter[bookmark]"] = String(onlyFav)
        }

        var url = "/api/v1/torrents"
        if let additionalParams, !additionalParams.isEmpty {
            for (key, value) in additionalParams {
                if key == "category" {
                    let category = dartToString(value).components(separatedBy: "#")
                    if category.count == 1, !category[0].isEmpty {
                        url += "/\(category[0])"
                    } else if category.count == 2, !category[0].isEmpty {
                        url += "/\(category[0])"
                        params["filter[category]"] = category[1]
                    }
                } else {
                    params[key] = dartToString(value)
                }
            }
        }

        do {
            let resp = try await client.perform(getRequest(url, query: params))
            let data = try JSONCast.map(resp.bodyJSON())
            if isRetSuccess(data["ret"]) {
                return try parseTorrentSearchResult(try JSONCast.map(data["data"]))
            }
            throw SiteApiException(
                message: "搜索失败: \(messageOr(data["msg"], "未知错误"))",
                responseData: data
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "搜索种子")
        }
    }

    private func parseTorrentSearchResult(_ data: [String: Any]) throws -> TorrentSearchResult {
        let meta = try JSONCast.map(data["meta"])
        let itemsRaw = try JSONCast.list(data["data"])

        var items: [TorrentItem] = []
        for element in itemsRaw {
            items.append(try parseTorrentItem(try JSONCast.map(element)))
        }

        return TorrentSearchResult(
            pageNumber: try JSONCast.int(meta["current_page"]),
            pageSize: try JSONCast.int(meta["per_page"]),
            total: try JSONCast.int(meta["total"]),
            totalPages: try JSONCast.int(meta["last_page"]),
            items: items
        )
    }

    private func parseTorrentItem(_ item: [String: Any]) throws -> TorrentItem {
        var discountText = "Normal"
        if let promotionInfo = try JSONCast.optionalMap(item["promotion_info"]) {
            let originalText = try JSONCast.optionalString(promotionInfo["text"]) ?? "Normal"
            let lowered = originalText.lowercased()
            if lowered.contains("2x"), lowered.contains("free") {
                discountText = "Free*2"
            } else {
                discountText = originalText
            }
        }

        var status = DownloadStatus.none
        if let activeStatus = try JSONCast.optionalMap(item["active_status"]) {
            let state = (jsonString(activeStatus["active_status"]) ?? "").lowercased()
            if state == "leeching" {
                status = .downloading
            } else if state == "seeding" || state == "inactivity" {
                status = .completed
            }
        }

        let name = try JSONCast.string(item["name"])
        let smallDescr = try JSONCast.optionalString(item["small_descr"]) ?? ""

        var tags = TagType.matchTags(name + smallDescr)

        if let rawTags = item["tags"], !(rawTags is NSNull), let tagsList = rawTags as? [Any] {
            for element in tagsList {
                guard let tagMap = element as? [String: Any] else { continue }
                guard let rawName = tagMap["name"], !(rawName is NSNull) else { continue }
                let tagName = dartToString(rawName)
                guard !tagName.isEmpty else { continue }
                if let mappedTag = parseTagType(tagName), !tags.contains(mappedTag) {
                    tags.append(mappedTag)
                }
            }
        }

        var addedValue: String?
        if let added = item["added"], !(added is NSNull) {
            addedValue = try JSONCast.string(added) + ":00"
        }

        return TorrentItem(
            id: String(try JSONCast.int(item["id"])),
            name: name,
            smallDescr: smallDescr,
            discount: parseDiscountType(discountText),
            discountEndTime: nil,
            downloadUrl: try JSONCast.optionalString(item["download_url"]),
            seeders: try JSONCast.int(item["seeders"]),
            leechers: try JSONCast.int(item["leechers"]),
            sizeBytes: try JSONCast.int(item["size"]),
            createdDate: try parseDateTimeCustom(addedValue, fieldName: "createdDate"),
            imageList: [],
            cover: try JSONCast.optionalString(item["cover"]) ?? "",
            downloadStatus: status,
            collection: try JSONCast.optionalBool(item["has_bookmarked"]) ?? false,
            isTop: jsonString(item["pos_state"]) != "normal",
            tags: tags,
            comments: try JSONCast.optionalInt(item["comments"]) ?? 0
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
                getRequest("/api/v1/detail/\(id)", query: ["includes": "extra"])
            )
            if resp.data.isEmpty {
                throw SiteApiException(message: "响应数据格式错误", responseData: nil)
            }

            let data = try JSONCast.map(resp.bodyJSON())
            guard let outerValue = data["data"], !(outerValue is NSNull) else {
                throw SiteApiException(message: "响应数据格式错误", responseData: data)
            }
            let outerNode = try JSONCast.map(outerValue)
            guard let innerValue = outerNode["data"], !(innerValue is NSNull) else {
                throw SiteApiException(message: "响应数据格式错误", responseData: data)
            }

            let torrentData = try JSONCast.map(innerValue)
            let extra = try JSONCast.optionalMap(torrentData["extra"])
            let descr = (extra.flatMap { jsonString($0["descr"]) }) ?? ""

            return TorrentDetail(descr: descr)
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取种子详情")
        }
    }

    func fetchComments(
        _ id: String,
        pageNumber: Int,
        pageSize: Int
    ) async throws -> TorrentCommentList {
        do {
            let resp = try await client.perform(
                getRequest(
                    "/api/v1/comments",
                    query: [
                        "torrent_id": id,
                        "page": String(pageNumber),
                        "per_page": String(pageSize),
                    ]
                )
            )

            let data = try JSONCast.map(resp.bodyJSON())
            guard isRetSuccess(data["ret"]) else {
                throw SiteApiException(
                    message: messageOr(data["msg"], "获取评论失败"),
                    responseData: data
                )
            }

            let responseData = try JSONCast.map(data["data"])
            let meta = try JSONCast.optionalMap(responseData["meta"])
            let commentsRaw = try JSONCast.optionalList(responseData["data"]) ?? []

            var comments: [TorrentComment] = []
            for element in commentsRaw {
                let commentData = try JSONCast.map(element)
                let createUser = try JSONCast.optionalMap(commentData["create_user"])
                comments.append(
                    TorrentComment(
                        id: jsonString(commentData["id"]) ?? "",
                        createdDate: try parseDateTimeCustom(
                            jsonString(commentData["created_at"]),
                            fieldName: "createdDate"
                        ),
                        lastModifiedDate: try parseDateTimeCustom(
                            jsonString(commentData["created_at"]),
                            fieldName: "lastModifiedDate"
                        ),
                        torrentId: id,
                        author: (createUser.flatMap { jsonString($0["username"]) }) ?? "",
                        text: jsonString(commentData["text"]) ?? "",
                        editedBy: "",
                        subject: ""
                    )
                )
            }

            return TorrentCommentList(
                pageNumber: try metaInt(meta, "current_page", pageNumber),
                pageSize: try metaInt(meta, "per_page", pageSize),
                total: try metaInt(meta, "total", comments.count),
                totalPages: try metaInt(meta, "last_page", 1),
                comments: comments
            )
        } catch {
            return TorrentCommentList(
                pageNumber: pageNumber,
                pageSize: pageSize,
                total: 0,
                totalPages: 0,
                comments: []
            )
        }
    }

    func genDlToken(id: String, url: String?) async throws -> String {
        guard let passKey = _siteConfig.passKey, !passKey.isEmpty else {
            throw SiteServiceException(message: "站点配置缺少passKey，无法生成下载链接")
        }
        guard let userId = _siteConfig.userId, !userId.isEmpty else {
            throw SiteServiceException(message: "站点配置缺少userId，无法生成下载链接")
        }

        let jwt = getDownLoadHash(passKey, id, userId)
        return "\(_siteConfig.baseUrl)download.php?downhash=\(userId).\(jwt)"
    }

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        ["data": [String: Any]()]
    }

    func toggleCollection(torrentId: String, make: Bool) async throws {
        do {
            let endpoint = make ? "/api/v1/bookmarks" : "/api/v1/bookmarks/delete"
            let resp = try await client.perform(
                multipartRequest(endpoint, [("torrent_id", torrentId)])
            )

            if resp.data.isEmpty {
                return
            }

            let data = try JSONCast.map(resp.bodyJSON())
            if let ret = data["ret"], !(ret is NSNull), !isRetSuccess(ret) {
                throw SiteApiException(
                    message: "收藏操作失败: \(messageOr(data["msg"], "未知错误"))",
                    responseData: data
                )
            }
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "收藏操作")
        }
    }

    func testConnection() async throws -> Bool {
        true
    }

    func getSearchCategories() async throws -> [SearchCategoryConfig] {
        let defaultCategories = await SiteConfigService.shared.getDefaultSearchCategories(
            _siteConfig.baseUrl
        )
        if !defaultCategories.isEmpty {
            return defaultCategories
        }

        var categories: [SearchCategoryConfig] = [
            SearchCategoryConfig(id: "all", displayName: "综合", parameters: "{}")
        ]

        do {
            let resp = try await client.perform(getRequest("/api/v1/sections"))
            if resp.statusCode == 200 {
                let data = try JSONCast.map(resp.bodyJSON())
                if isRetSuccess(data["ret"]), let dataValue = data["data"], !(dataValue is NSNull) {
                    let dataNode = try JSONCast.map(dataValue)

                    let sectionsData: [Any]
                    if let rawSections = dataNode["data"],
                        !(rawSections is NSNull),
                        let sectionList = rawSections as? [Any]
                    {
                        sectionsData = sectionList
                    } else {
                        sectionsData = try JSONCast.list(dataNode["sections"])
                    }

                    let onlyOne = sectionsData.count == 1
                    for section in sectionsData {
                        let sectionMap = try JSONCast.map(section)
                        let sectionName = try JSONCast.string(sectionMap["name"])
                        let sectionDisplayName = stripWhitespace(
                            try JSONCast.string(sectionMap["display_name"])
                        )
                        let categoriesData = try JSONCast.list(sectionMap["categories"])

                        for category in categoriesData {
                            let categoryMap = try JSONCast.map(category)
                            let categoryId = categoryMap["id"]
                            let categoryName = stripWhitespace(
                                try JSONCast.string(categoryMap["name"])
                            )
                            categories.append(
                                SearchCategoryConfig(
                                    id: "\(sectionName)_\(dartToString(categoryId))",
                                    displayName: onlyOne
                                        ? categoryName
                                        : "\(sectionDisplayName).\(categoryName)",
                                    parameters:
                                        "{\"category\":\"\(sectionName)#\(dartToString(categoryId))\"}"
                                )
                            )
                        }
                    }
                    return categories
                }
            }
            return categories
        } catch {
            return categories
        }
    }
}
