import Foundation

final class Unit3dAdapter: SiteAdapter {
    private(set) var siteConfig: SiteConfig = SiteConfig(id: "", name: "", baseUrl: "")
    private var client: HttpClient!
    private var bearerToken: String?

    func initialize(_ config: SiteConfig) async throws {
        siteConfig = config
        client = HttpClient(baseURL: config.baseUrl)
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            bearerToken = "Bearer \(apiKey)"
        }
    }

    func fetchMemberProfile(apiKey: String?) async throws -> MemberProfile {
        do {
            if let apiKey, !apiKey.isEmpty {
                bearerToken = "Bearer \(apiKey)"
            }

            let response = try await request("/api/users")

            if response.statusCode == 200, !response.data.isEmpty {
                let body = try decodeObject(response)
                var userData = try extractUserData(body)

                if let list = nullFiltered(body["data"]) as? [Any] {
                    for user in list {
                        guard let userMap = user as? [String: Any] else {
                            throw typeMismatchError("Map<String, dynamic>", user)
                        }
                        let attrs = firstNonNull(userMap["attributes"]) ?? userMap
                        guard let attrsMap = attrs as? [String: Any] else {
                            throw typeMismatchError("Map<String, dynamic>", attrs)
                        }
                        if isTrue(userMap["is_me"]) || isTrue(attrsMap["is_me"]) {
                            userData = user
                            break
                        }
                    }
                }

                guard let userData else {
                    throw SiteServiceException(message: "未找到当前用户数据")
                }

                guard let userRecord = userData as? [String: Any] else {
                    throw typeMismatchError("Map<String, dynamic>", userData)
                }
                let attrs = firstNonNull(userRecord["attributes"]) ?? userRecord
                guard let userAttrs = attrs as? [String: Any] else {
                    throw typeMismatchError("Map<String, dynamic>", attrs)
                }

                let uploaded = try strictNumInt(userAttrs["uploaded"]) ?? 0
                let downloaded = try strictNumInt(userAttrs["downloaded"]) ?? 0

                return MemberProfile(
                    username: try strictString(userAttrs["username"], "Unknown"),
                    bonus: 0,
                    shareRate: try strictNumDouble(userAttrs["ratio"]) ?? 0,
                    uploadedBytes: uploaded,
                    downloadedBytes: downloaded,
                    uploadedBytesString: String(uploaded),
                    downloadedBytesString: String(downloaded),
                    userId: stringOrDefault(
                        firstNonNull(userRecord["id"], userAttrs["id"]),
                        ""
                    )
                )
            } else {
                throw SiteServiceException(
                    message: "获取用户资料失败: HTTP \(response.statusCode)"
                )
            }
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取用户资料")
        }
    }

    private func extractUserData(_ body: [String: Any]) throws -> Any? {
        let raw = nullFiltered(body["data"])
        if let list = raw as? [Any] {
            return list.first
        }
        if let text = raw as? String {
            if text.isEmpty {
                throw typeMismatchError("String", text)
            }
            return String(text.prefix(1))
        }
        if let raw {
            if raw is [String: Any] {
                return nil
            }
            throw typeMismatchError("List<dynamic>", raw)
        }
        return nil
    }

    func searchTorrents(
        keyword: String?,
        pageNumber: Int,
        pageSize: Int,
        onlyFav: Int?,
        additionalParams: [String: Any]?
    ) async throws -> TorrentSearchResult {
        do {
            var queryParams: [String: String] = [
                "page": dartToString(pageNumber),
                "perPage": dartToString(pageSize),
            ]

            if let keyword, !keyword.isEmpty {
                queryParams["name"] = keyword
            }

            if let additionalParams {
                for (key, value) in additionalParams {
                    if let value = nullFiltered(value) {
                        queryParams[key] = dartToString(value)
                    }
                }
            }

            let response = try await request("/api/torrents/filter", query: queryParams)

            if response.statusCode == 200, !response.data.isEmpty {
                let data = try decodeObject(response)
                var torrents: [TorrentItem] = []

                if let items = nullFiltered(data["data"]) as? [Any] {
                    for item in items {
                        torrents.append(try parseTorrentItem(item))
                    }
                }

                let meta = try strictMap(data["meta"]) ?? [:]
                let totalCount = try strictIntCast(meta["total"]) ?? 0
                let lastPage = try strictIntCast(meta["last_page"]) ?? 1

                return TorrentSearchResult(
                    pageNumber: pageNumber,
                    pageSize: pageSize,
                    total: totalCount,
                    totalPages: lastPage,
                    items: torrents
                )
            } else {
                throw SiteServiceException(
                    message: "搜索种子失败: HTTP \(response.statusCode)"
                )
            }
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "搜索种子")
        }
    }

    private func parseTorrentItem(_ item: Any) throws -> TorrentItem {
        guard let map = item as? [String: Any] else {
            throw typeMismatchError("Map<String, dynamic>", item)
        }

        let attributes = try strictMap(map["attributes"]) ?? map
        let meta = try strictMap(attributes["meta"]) ?? [:]

        let title = try strictString(attributes["name"], "")
        let subhead = try strictString(attributes["subhead"], "")

        var publishDate = Date()
        if let createdAt = nullFiltered(attributes["created_at"]) as? String,
            let parsed = try? dartParseDateTime(createdAt)
        {
            publishDate = parsed
        }

        var discount = DiscountType.normal
        if isTrue(attributes["freeleech"]) || stringEquals(attributes["freeleech_type"], "Free")
        {
            discount = .free
        } else if isTrue(attributes["doubleup"])
            || stringEquals(attributes["freeleech_type"], "Double Up")
        {
            discount = .twoXFree
        }

        let tags: [TagType] = []

        return TorrentItem(
            id: stringOrDefault(firstNonNull(map["id"], attributes["id"]), ""),
            name: title,
            smallDescr: subhead,
            discount: discount,
            discountEndTime: nil,
            downloadUrl: try strictString(attributes["download_link"], ""),
            description: try strictString(attributes["description"], ""),
            seeders: try strictNumInt(attributes["seeders"]) ?? 0,
            leechers: try strictNumInt(attributes["leechers"]) ?? 0,
            sizeBytes: try strictNumInt(attributes["size"]) ?? 0,
            createdDate: publishDate,
            imageList: [],
            cover: try strictString(
                firstNonNull(meta["poster"], attributes["poster"]),
                ""
            ),
            downloadStatus: .none,
            collection: false,
            isTop: false,
            tags: tags,
            comments: try strictNumInt(attributes["comments"]) ?? 0
        )
    }

    func fetchTorrentDetail(
        _ id: String,
        description: String?,
        detailUrl: String?
    ) async throws -> TorrentDetail {
        if let description, !description.isEmpty {
            return TorrentDetail(descr: description)
        }

        return TorrentDetail(descr: "")
    }

    func fetchComments(
        _ id: String,
        pageNumber: Int,
        pageSize: Int
    ) async throws -> TorrentCommentList {
        TorrentCommentList(
            pageNumber: pageNumber,
            pageSize: pageSize,
            total: 0,
            totalPages: 1,
            comments: []
        )
    }

    func genDlToken(id: String, url: String?) async throws -> String {
        if let url, !url.isEmpty {
            return url
        }
        throw SiteServiceException(message: "获取下载链接失败")
    }

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        [:]
    }

    func toggleCollection(torrentId: String, make: Bool) async throws {
        throw SiteServiceException(message: "当前站点不支持通过 API 收藏")
    }

    func testConnection() async throws -> Bool {
        if !siteConfig.features.supportMemberProfile {
            do {
                let response = try await request(
                    "/api/torrents",
                    query: ["perPage": "1"]
                )
                return response.statusCode == 200
            } catch {
                throw ApiExceptionAdapter.wrapError(error, action: "测试连接")
            }
        }

        do {
            _ = try await fetchMemberProfile(apiKey: nil)
            return true
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "测试连接")
        }
    }

    func getSearchCategories() async throws -> [SearchCategoryConfig] {
        []
    }

    private func request(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> HTTPResponse {
        var headers = ["Accept": "application/json"]
        if let bearerToken {
            headers["Authorization"] = bearerToken
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

    private func strictNumber(_ value: Any) throws -> Double {
        if strictBool(value) != nil {
            throw typeMismatchError("num", value)
        }
        guard let number = value as? NSNumber else {
            throw typeMismatchError("num", value)
        }
        return number.doubleValue
    }

    private func strictNumInt(_ value: Any?) throws -> Int? {
        guard let value = nullFiltered(value) else { return nil }
        return try dartDoubleToInt(try strictNumber(value))
    }

    private func strictNumDouble(_ value: Any?) throws -> Double? {
        guard let value = nullFiltered(value) else { return nil }
        return try strictNumber(value)
    }

    private func strictIntCast(_ value: Any?) throws -> Int? {
        guard let value = nullFiltered(value) else { return nil }
        guard let int = strictIntValue(value) else {
            throw typeMismatchError("int", value)
        }
        return int
    }

    private func strictMap(_ value: Any?) throws -> [String: Any]? {
        guard let value = nullFiltered(value) else { return nil }
        guard let map = value as? [String: Any] else {
            throw typeMismatchError("Map<String, dynamic>", value)
        }
        return map
    }

    private func stringEquals(_ value: Any?, _ target: String) -> Bool {
        guard let value = nullFiltered(value), let string = value as? String else {
            return false
        }
        return string == target
    }

    private func isTrue(_ value: Any?) -> Bool {
        guard let value = nullFiltered(value) else { return false }
        return strictBool(value) == true
    }

    private func stringOrDefault(_ value: Any?, _ fallback: String) -> String {
        guard let value = nullFiltered(value) else { return fallback }
        return dartToString(value)
    }
}
