import Foundation

final class RousiAdapter: SiteAdapter {
    private(set) var siteConfig: SiteConfig = SiteConfig(id: "", name: "", baseUrl: "")
    private var client: HttpClient!

    func initialize(_ config: SiteConfig) async throws {
        siteConfig = config
        var base = config.baseUrl.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        client = HttpClient(baseURL: base)
    }

    func fetchMemberProfile(apiKey: String?) async throws -> MemberProfile {
        do {
            let response = try await request(
                "/api/v1/profile",
                query: ["include_fields[user]": "seeding_leeching_data"]
            )
            let data = try decodeObject(response)
            if intEquals(data["code"], 0), let payload = try strictMap(data["data"]) {
                return try parseMemberProfile(payload)
            }
            throw SiteApiException(
                message: "获取用户资料失败: \(stringOrDefault(data["message"], "未知错误"))",
                responseData: data
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取用户资料")
        }
    }

    private func parseMemberProfile(_ data: [String: Any]) throws -> MemberProfile {
        let uploadedBytes = try strictInt(data["uploaded"], 0)
        let downloadedBytes = try strictInt(data["downloaded"], 0)

        let seedingData = try strictMap(data["seeding_leeching_data"])
        let seedingSize = try seedingData.flatMap { try strictNumInt($0["seeding_size"]) }

        return MemberProfile(
            username: try strictString(data["username"], ""),
            bonus: try strictDouble(data["karma"], 0),
            shareRate: try strictDouble(data["ratio"], 0),
            uploadedBytes: uploadedBytes,
            downloadedBytes: downloadedBytes,
            uploadedBytesString: dataFromBytes(uploadedBytes),
            downloadedBytesString: dataFromBytes(downloadedBytes),
            userId: optionalToString(data["id"]),
            passKey: nil,
            lastAccess: try parseDateTimeCustom(
                optionalToString(data["last_active_at"]),
                fieldName: "lastAccess"
            ),
            bonusPerHour: try strictDouble(data["seeding_karma_per_hour"], 0),
            seedingSizeBytes: seedingSize
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
            "page": dartToString(pageNumber),
            "page_size": dartToString(pageSize),
        ]

        if let keyword, !keyword.isEmpty {
            params["keyword"] = keyword
        }

        if let additionalParams, let category = nullFiltered(additionalParams["category"]) {
            params["category"] = dartToString(category)
        }

        do {
            let response = try await request("/api/v1/torrents", query: params)
            let data = try decodeObject(response)
            if intEquals(data["code"], 0), let payload = try strictMap(data["data"]) {
                return try parseTorrentSearchResult(payload)
            }
            throw SiteApiException(
                message: "搜索失败: \(stringOrDefault(data["message"], "未知错误"))",
                responseData: data
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "搜索种子")
        }
    }

    private func parseTorrentSearchResult(_ data: [String: Any]) throws -> TorrentSearchResult {
        let torrents = try strictList(data["torrents"]) ?? []
        let items = try torrents.map { try parseTorrentItem($0) }

        return TorrentSearchResult(
            pageNumber: try strictInt(data["page"], 1),
            pageSize: try strictInt(data["page_size"], 20),
            total: try strictInt(data["total"], 0),
            totalPages: try strictInt(data["total_pages"], 1),
            items: items
        )
    }

    private func parseTorrentItem(_ item: Any) throws -> TorrentItem {
        guard let map = item as? [String: Any] else {
            throw typeMismatchError("Map<String, dynamic>", item)
        }

        var discount = DiscountType.normal
        var discountEndTime: String?
        let promotion = try strictMap(map["promotion"])
        if let promotion {
            if let type = try strictIntCast(promotion["type"]) {
                switch type {
                case 2:
                    discount = .free
                case 4:
                    discount = .twoXFree
                case 5:
                    discount = .percent50
                case 6:
                    discount = .twoX50Percent
                case 7:
                    discount = .percent30
                default:
                    discount = .normal
                }
            }
            if let until = nullFiltered(promotion["until"]) {
                discountEndTime = dartToString(until)
            }
        }

        let cover = try strictString(map["cover_image"], "")
        let name = try strictString(map["title"], "")
        let tags = TagType.matchTags(name)

        guard let rawId = firstNonNull(map["uuid"], map["id"]) else {
            throw typeMismatchError("String", nil)
        }

        return TorrentItem(
            id: dartToString(rawId),
            name: name,
            smallDescr: try strictString(map["subtitle"], ""),
            discount: discount,
            discountEndTime: try parseDateTimeCustom(
                discountEndTime,
                fieldName: "discountEndTime"
            ),
            downloadUrl: nil,
            seeders: try strictInt(map["seeders"], 0),
            leechers: try strictInt(map["leechers"], 0),
            sizeBytes: try strictInt(map["size"], 0),
            createdDate: try parseDateTimeCustom(
                optionalToString(map["created_at"]),
                fieldName: "createdDate"
            ),
            imageList: [],
            cover: cover,
            downloadStatus: .none,
            collection: false,
            tags: tags,
            comments: 0
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

            let response = try await request("/api/v1/torrents/\(id)")
            let data = try decodeObject(response)
            if intEquals(data["code"], 0), let info = try strictMap(data["data"]) {
                var imageBBCode = ""
                let images = try strictList(info["images"])
                if let images, !images.isEmpty {
                    for img in images {
                        guard let imgMap = img as? [String: Any] else {
                            throw typeMismatchError("Map<String, dynamic>", img)
                        }
                        if let url = nullFiltered(imgMap["url"]) {
                            imageBBCode += "[img]\(dartToString(url))[/img]\n"
                        }
                    }
                    if !imageBBCode.isEmpty {
                        imageBBCode += "\n"
                    }
                }

                let descr = try strictString(info["description"], "")
                return TorrentDetail(descr: imageBBCode + descr)
            }
            throw SiteApiException(
                message: "获取详情失败: \(stringOrDefault(data["message"], "未知错误"))",
                responseData: data
            )
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
            let response = try await request(
                "/api/v1/torrents/\(id)/comments",
                query: [
                    "page": dartToString(pageNumber),
                    "page_size": dartToString(pageSize),
                ]
            )

            if response.statusCode == 200 {
                let data = try decodeObject(response)
                if intEquals(data["code"], 0), let d = try strictMap(data["data"]) {
                    let list = try strictList(d["comments"]) ?? []
                    let comments = try list.map { try parseComment($0, torrentId: id) }

                    return TorrentCommentList(
                        pageNumber: try strictInt(d["page"], 1),
                        pageSize: try strictInt(d["page_size"], 20),
                        total: try strictInt(d["total"], 0),
                        totalPages: try strictInt(d["total_pages"], 1),
                        comments: comments
                    )
                }
            }
            return TorrentCommentList(
                pageNumber: pageNumber,
                pageSize: pageSize,
                total: 0,
                totalPages: 0,
                comments: []
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

    private func parseComment(_ comment: Any, torrentId: String) throws -> TorrentComment {
        guard let map = comment as? [String: Any] else {
            throw typeMismatchError("Map<String, dynamic>", comment)
        }
        guard let rawId = nullFiltered(map["id"]) else {
            throw typeMismatchError("String", nil)
        }

        return TorrentComment(
            id: dartToString(rawId),
            createdDate: try parseDateTimeCustom(
                optionalToString(map["created_at"]),
                fieldName: "createdDate"
            ),
            lastModifiedDate: try parseDateTimeCustom(
                optionalToString(map["created_at"]),
                fieldName: "lastModifiedDate"
            ),
            torrentId: torrentId,
            author: try strictString(map["username"], ""),
            text: try strictString(map["content"], ""),
            editedBy: "",
            subject: ""
        )
    }

    func genDlToken(id: String, url: String?) async throws -> String {
        if let url, !url.isEmpty {
            return url
        }

        do {
            let response = try await request("/api/v1/torrents/\(id)")
            let data = try decodeObject(response)
            if intEquals(data["code"], 0), let payload = try strictMap(data["data"]) {
                let rawDownloadUrl = nullFiltered(payload["download_url"])
                if let downloadUrl = rawDownloadUrl as? String, !downloadUrl.isEmpty {
                    return downloadUrl
                }

                let rawIsPurchased = nullFiltered(payload["is_purchased"])
                let rawPrice = nullFiltered(payload["price"])

                var isPurchased = true
                if let boolValue = strictBool(rawIsPurchased) {
                    isPurchased = boolValue
                } else if let text = rawIsPurchased as? String {
                    isPurchased = text.lowercased() == "true"
                }

                var price = 0.0
                if strictBool(rawPrice) == nil, let number = rawPrice as? NSNumber {
                    price = number.doubleValue
                } else if let text = rawPrice as? String {
                    price = dartDoubleFromString(text) ?? 0
                }

                let missingDownloadUrl: Bool
                if let rawDownloadUrl {
                    missingDownloadUrl = dartToString(rawDownloadUrl).isEmpty
                } else {
                    missingDownloadUrl = true
                }

                if missingDownloadUrl,
                    price > 0 || !isPurchased || (rawIsPurchased as? String) == "false"
                {
                    throw SiteApiException(message: "NEED_PURCHASE", responseData: data)
                }
            }
            throw SiteApiException(message: "无法获取下载链接", responseData: data)
        } catch let error as SiteApiException where error.message == "NEED_PURCHASE" {
            throw error
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "生成下载链接")
        }
    }

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        ["data": [String: Any]()]
    }

    func toggleCollection(torrentId: String, make: Bool) async throws {}

    func testConnection() async throws -> Bool {
        do {
            _ = try await fetchMemberProfile(apiKey: nil)
            return true
        } catch {
            return false
        }
    }

    func getSearchCategories() async throws -> [SearchCategoryConfig] {
        do {
            let response = try await request("/api/v1/categories")
            var list = [
                SearchCategoryConfig(id: "all", displayName: "全部", parameters: "{}")
            ]

            if response.statusCode == 200 {
                let data = try decodeObject(response)
                if intEquals(data["code"], 0), let cats = try strictList(data["data"]) {
                    for cat in cats {
                        guard let catMap = cat as? [String: Any] else {
                            throw typeMismatchError("Map<String, dynamic>", cat)
                        }
                        let name = try strictStringRequired(catMap["name"])
                        let label = try strictStringRequired(catMap["label"])
                        list.append(
                            SearchCategoryConfig(
                                id: "cat_\(name)",
                                displayName: label,
                                parameters: "{\"category\": \"\(name)\"}"
                            )
                        )
                    }
                }
            }
            return list
        } catch {
            return []
        }
    }

    private func request(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> HTTPResponse {
        var headers = ["Accept": "application/json"]
        if let apiKey = siteConfig.apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return try await client.perform(HTTPRequest(path, headers: headers, query: query))
    }

    private func decodeObject(_ response: HTTPResponse) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: response.data)
        guard let map = parsed as? [String: Any] else {
            throw typeMismatchError("Map<String, dynamic>", parsed)
        }
        return map
    }

    private func nullFiltered(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        return value
    }

    private func firstNonNull(_ values: Any?...) -> Any? {
        for value in values {
            if let value = nullFiltered(value) {
                return value
            }
        }
        return nil
    }

    private func strictString(_ value: Any?, _ fallback: String) throws -> String {
        guard let value = nullFiltered(value) else { return fallback }
        guard let string = value as? String else {
            throw typeMismatchError("String", value)
        }
        return string
    }

    private func strictStringRequired(_ value: Any?) throws -> String {
        guard let value = nullFiltered(value) else {
            throw typeMismatchError("String", nil)
        }
        guard let string = value as? String else {
            throw typeMismatchError("String", value)
        }
        return string
    }

    private func strictNumber(_ value: Any) throws -> Double {
        if strictBool(value) != nil {
            throw typeMismatchError("num", value)
        }
        guard let number = value as? NSNumber else {
            throw typeMismatchError("num", value)
        }
        return number.doubleValue
    }

    private func strictInt(_ value: Any?, _ fallback: Int) throws -> Int {
        guard let value = nullFiltered(value) else { return fallback }
        return try dartDoubleToInt(try strictNumber(value))
    }

    private func strictDouble(_ value: Any?, _ fallback: Double) throws -> Double {
        guard let value = nullFiltered(value) else { return fallback }
        return try strictNumber(value)
    }

    private func strictIntCast(_ value: Any?) throws -> Int? {
        guard let value = nullFiltered(value) else { return nil }
        guard let int = strictIntValue(value) else {
            throw typeMismatchError("int", value)
        }
        return int
    }

    private func strictNumInt(_ value: Any?) throws -> Int? {
        guard let value = nullFiltered(value) else { return nil }
        return try dartDoubleToInt(try strictNumber(value))
    }

    private func strictMap(_ value: Any?) throws -> [String: Any]? {
        guard let value = nullFiltered(value) else { return nil }
        guard let map = value as? [String: Any] else {
            throw typeMismatchError("Map<String, dynamic>", value)
        }
        return map
    }

    private func strictList(_ value: Any?) throws -> [Any]? {
        guard let value = nullFiltered(value) else { return nil }
        guard let list = value as? [Any] else {
            throw typeMismatchError("List<dynamic>", value)
        }
        return list
    }

    private func intEquals(_ value: Any?, _ target: Int) -> Bool {
        guard let value = nullFiltered(value),
            strictBool(value) == nil,
            let number = value as? NSNumber
        else {
            return false
        }
        return number.doubleValue == Double(target)
    }

    private func stringOrDefault(_ value: Any?, _ fallback: String) -> String {
        guard let value = nullFiltered(value) else { return fallback }
        return dartToString(value)
    }

    private func optionalToString(_ value: Any?) -> String? {
        guard let value = nullFiltered(value) else { return nil }
        return dartToString(value)
    }

    private func dataFromBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1024 {
            return String(format: "%.2f TB", gb / 1024.0)
        }
        return String(format: "%.2f GB", gb)
    }
}
