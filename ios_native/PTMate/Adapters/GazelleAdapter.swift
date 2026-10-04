import Foundation

final class GazelleAdapter: SiteAdapter {
    private(set) var siteConfig: SiteConfig = SiteConfig(id: "", name: "", baseUrl: "")
    private var client: HttpClient!

    private static let decimalEntityRegex = try! NSRegularExpression(
        pattern: "&#([0-9]+);"
    )

    private static let hexEntityRegex = try! NSRegularExpression(
        pattern: "&#[xX]([0-9a-fA-F]+);"
    )

    func initialize(_ config: SiteConfig) async throws {
        siteConfig = config
        client = HttpClient(baseURL: config.baseUrl)
        client.cookieProvider = { [weak self] in
            self?.siteConfig.cookie
        }
    }

    func fetchMemberProfile(apiKey: String?) async throws -> MemberProfile {
        do {
            let resp = try await checkedRequest("/ajax.php?action=index")
            let json = try decodeJSON(resp)

            if !stringEquals(json["status"], "success") {
                throw SiteApiException(
                    message: "获取用户资料失败: \(stringOrDefault(json["error"], "未知错误"))",
                    responseData: json
                )
            }

            let response = try strictMap(json["response"]) ?? [:]
            return try parseMemberProfile(response)
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取用户资料")
        }
    }

    private func parseMemberProfile(_ json: [String: Any]) throws -> MemberProfile {
        let userstats = try strictMap(json["userstats"]) ?? [:]

        let uploadedBytes = dartParseInt(userstats["uploaded"]) ?? 0
        let downloadedBytes = dartParseInt(userstats["downloaded"]) ?? 0

        return MemberProfile(
            username: stringOrDefault(json["username"], ""),
            bonus: dartLenientDouble(userstats["bonusPoints"]),
            shareRate: dartLenientDouble(userstats["ratio"]),
            uploadedBytes: uploadedBytes,
            downloadedBytes: downloadedBytes,
            uploadedBytesString: dataFromBytes(uploadedBytes),
            downloadedBytesString: dataFromBytes(downloadedBytes),
            userId: optionalToString(json["id"]),
            passKey: optionalToString(json["passkey"]),
            authKey: optionalToString(json["authkey"]),
            lastAccess: try parseDateTimeCustom(
                optionalToString(userstats["lastAccess"]),
                fieldName: "lastAccess"
            ),
            bonusPerHour: dartLenientDouble(userstats["seedingBonusPointsPerHour"]),
            seedingSizeBytes: dartParseInt(userstats["seedingSize"])
        )
    }

    func searchTorrents(
        keyword: String?,
        pageNumber: Int,
        pageSize: Int,
        onlyFav: Int?,
        additionalParams: [String: Any]?
    ) async throws -> TorrentSearchResult {
        do {
            var params: [String: String] = [
                "action": "browse",
                "page": dartToString(pageNumber),
            ]

            if let keyword {
                let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    params["searchstr"] = trimmed
                }
            }

            if onlyFav == 1 {
                params["action"] = "bookmarks"
                params["type"] = "torrents"
            }

            if let additionalParams {
                for (key, value) in additionalParams {
                    if let value = nullFiltered(value) {
                        params[key] = dartToString(value)
                    }
                }
            }

            let resp = try await checkedRequest("/ajax.php", query: params)
            let json = try decodeJSON(resp)

            if !stringEquals(json["status"], "success") {
                throw SiteApiException(
                    message: "搜索失败: \(stringOrDefault(json["error"], "未知错误"))",
                    responseData: json
                )
            }

            let response = try strictMap(json["response"]) ?? [:]
            if onlyFav == 1 {
                return try parseTorrentBookmarkResult(
                    response,
                    pageNumber: pageNumber,
                    pageSize: pageSize
                )
            }
            return try parseTorrentSearchResult(
                response,
                pageNumber: pageNumber,
                pageSize: pageSize
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "搜索种子")
        }
    }

    private func parseTorrentSearchResult(
        _ json: [String: Any],
        pageNumber: Int,
        pageSize: Int
    ) throws -> TorrentSearchResult {
        let results = try strictList(json["results"]) ?? []
        var items: [TorrentItem] = []

        for group in results {
            guard let groupMap = group as? [String: Any] else { continue }

            let torrents = try strictList(groupMap["torrents"]) ?? []
            let rawGroupName = unescapeHtml(
                stringOrDefault(firstNonNull(groupMap["groupName"], groupMap["name"]), "")
            )
            let artist = unescapeHtml(stringOrDefault(groupMap["artist"], ""))
            let cover = stringOrDefault(firstNonNull(groupMap["cover"], groupMap["wikiImage"]), "")

            for torrent in torrents {
                guard let torrentMap = torrent as? [String: Any] else { continue }

                let id = stringOrDefault(firstNonNull(torrentMap["torrentId"], torrentMap["id"]), "")
                if id.isEmpty { continue }

                let tagString = makeTagString(torrentMap)

                items.append(
                    TorrentItem(
                        id: id,
                        name: makeName(artist: artist, rawGroupName: rawGroupName, torrent: torrentMap),
                        smallDescr: "",
                        discount: parseDiscountType(isTrue(torrentMap["isFreeleech"])),
                        discountEndTime: nil,
                        downloadUrl: buildDownloadUrl(id),
                        seeders: dartParseInt(torrentMap["seeders"]) ?? 0,
                        leechers: dartParseInt(torrentMap["leechers"]) ?? 0,
                        sizeBytes: dartParseInt(torrentMap["size"]) ?? 0,
                        createdDate: try parseDateTimeCustom(
                            optionalToString(torrentMap["time"]),
                            fieldName: "createdDate"
                        ),
                        imageList: cover.isEmpty ? [] : [cover],
                        cover: cover,
                        collection: isTrue(groupMap["bookmarked"]),
                        doubanRating: optionalToString(groupMap["doubanRating"]) ?? "0",
                        imdbRating: optionalToString(groupMap["imdbRating"]) ?? "0",
                        tags: TagType.matchTags(tagString)
                    )
                )
            }
        }

        let total = dartParseInt(json["pages"]) ?? 1

        return TorrentSearchResult(
            pageNumber: pageNumber,
            pageSize: pageSize,
            total: items.count,
            totalPages: total,
            items: items
        )
    }

    private func parseTorrentBookmarkResult(
        _ json: [String: Any],
        pageNumber: Int,
        pageSize: Int
    ) throws -> TorrentSearchResult {
        let bookmarks = try strictList(json["bookmarks"]) ?? []
        var items: [TorrentItem] = []

        for group in bookmarks {
            guard let groupMap = group as? [String: Any] else { continue }

            let torrents = try strictList(groupMap["torrents"]) ?? []
            let rawGroupName = unescapeHtml(stringOrDefault(groupMap["name"], ""))
            let artist = unescapeHtml(stringOrDefault(groupMap["artist"], ""))
            let cover = stringOrDefault(groupMap["image"], "")

            for torrent in torrents {
                guard let torrentMap = torrent as? [String: Any] else { continue }

                let id = stringOrDefault(firstNonNull(torrentMap["id"], torrentMap["torrentId"]), "")
                if id.isEmpty { continue }

                let tagString = makeTagString(torrentMap)

                items.append(
                    TorrentItem(
                        id: id,
                        name: makeName(artist: artist, rawGroupName: rawGroupName, torrent: torrentMap),
                        smallDescr: "",
                        discount: parseDiscountType(
                            isTrue(torrentMap["freeTorrent"]) || isTrue(torrentMap["isFreeleech"])
                        ),
                        discountEndTime: nil,
                        downloadUrl: buildDownloadUrl(id),
                        seeders: dartParseInt(torrentMap["seeders"]) ?? 0,
                        leechers: dartParseInt(torrentMap["leechers"]) ?? 0,
                        sizeBytes: dartParseInt(torrentMap["size"]) ?? 0,
                        createdDate: try parseDateTimeCustom(
                            optionalToString(torrentMap["time"]),
                            fieldName: "createdDate"
                        ),
                        imageList: cover.isEmpty ? [] : [cover],
                        cover: cover,
                        collection: true,
                        doubanRating: optionalToString(groupMap["doubanRating"]) ?? "0",
                        imdbRating: optionalToString(groupMap["imdbRating"]) ?? "0",
                        tags: TagType.matchTags(tagString)
                    )
                )
            }
        }

        let total = dartParseInt(json["pages"]) ?? 1

        return TorrentSearchResult(
            pageNumber: pageNumber,
            pageSize: pageSize,
            total: items.count,
            totalPages: total,
            items: items
        )
    }

    private func makeTagString(_ torrent: [String: Any]) -> String {
        let components = [
            torrent["remasterTitle"],
            torrent["resolution"],
            torrent["source"],
            torrent["codec"],
            torrent["subtitles"],
        ]
        var parts: [String] = []
        for component in components {
            guard let component = nullFiltered(component) else { continue }
            let text = dartToString(component)
            if !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.joined(separator: " ").replacingOccurrences(of: ",", with: " ")
    }

    private func makeName(artist: String, rawGroupName: String, torrent: [String: Any]) -> String {
        let prefix = artist.isEmpty ? "" : "\(artist) - "
        let format = stringOrDefault(torrent["format"], "")
        let encoding = stringOrDefault(torrent["encoding"], "")
        return "\(prefix)\(rawGroupName) - \(format) / \(encoding)"
    }

    private func parseDiscountType(_ isFreeleech: Bool?) -> DiscountType {
        if isFreeleech == true {
            return .free
        }
        return .normal
    }

    private func buildDownloadUrl(_ id: String) -> String? {
        let authKey = siteConfig.authKey
        let passKey = siteConfig.passKey

        if let authKey, !authKey.isEmpty, let passKey, !passKey.isEmpty {
            let baseUrl = siteConfig.baseUrl.hasSuffix("/")
                ? String(siteConfig.baseUrl.dropLast())
                : siteConfig.baseUrl
            return "\(baseUrl)/torrents.php?action=download&id=\(id)&authkey=\(authKey)&torrent_pass=\(passKey)"
        }
        return nil
    }

    func fetchTorrentDetail(
        _ id: String,
        description: String?,
        detailUrl: String?
    ) async throws -> TorrentDetail {
        let baseUrl = siteConfig.baseUrl.hasSuffix("/")
            ? String(siteConfig.baseUrl.dropLast())
            : siteConfig.baseUrl

        if let description, !description.isEmpty {
            return TorrentDetail(
                descr: description,
                descrHtml: description,
                webviewUrl: "\(baseUrl)/torrents.php?torrentid=\(id)"
            )
        }

        return TorrentDetail(
            descr: "",
            webviewUrl: "\(baseUrl)/torrents.php?torrentid=\(id)"
        )
    }

    func genDlToken(id: String, url: String?) async throws -> String {
        let baseUrl = siteConfig.baseUrl.hasSuffix("/")
            ? String(siteConfig.baseUrl.dropLast())
            : siteConfig.baseUrl
        return "\(baseUrl)/torrents.php?action=download&id=\(id)"
    }

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        [:]
    }

    func toggleCollection(torrentId: String, make: Bool) async throws {
        do {
            let action = make ? "add" : "remove"
            _ = try await checkedRequest(
                "/bookmarks.php",
                query: [
                    "action": action,
                    "type": "torrent",
                    "id": torrentId,
                ]
            )
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

    func fetchComments(
        _ id: String,
        pageNumber: Int,
        pageSize: Int
    ) async throws -> TorrentCommentList {
        TorrentCommentList(
            pageNumber: pageNumber,
            pageSize: pageSize,
            total: 0,
            totalPages: 0,
            comments: []
        )
    }

    func getSearchCategories() async throws -> [SearchCategoryConfig] {
        await SiteConfigService.shared.getDefaultSearchCategories(siteConfig.baseUrl)
    }

    private func checkedRequest(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> HTTPResponse {
        let response = try await client.perform(HTTPRequest(path, query: query))
        let isLoginRedirect = response.url.absoluteString.contains("login")
            || response.redirectLocations.contains { $0.absoluteString.contains("login") }
        if isLoginRedirect {
            throw SiteAuthenticationException(message: HttpClient.authExpiredMessage)
        }
        return response
    }

    private func decodeJSON(_ response: HTTPResponse) throws -> [String: Any] {
        if let parsed = try? JSONSerialization.jsonObject(with: response.data),
            let map = parsed as? [String: Any]
        {
            return map
        }

        let text = response.text
        let outer = try JSONSerialization.jsonObject(
            with: Data(text.utf8),
            options: [.fragmentsAllowed]
        )
        if let map = outer as? [String: Any] {
            return map
        }
        if let string = outer as? String {
            let inner = try JSONSerialization.jsonObject(
                with: Data(string.utf8),
                options: [.fragmentsAllowed]
            )
            guard let map = inner as? [String: Any] else {
                throw typeMismatchError("Map<String, dynamic>", inner)
            }
            return map
        }
        throw typeMismatchError("Map<String, dynamic>", outer)
    }

    private func unescapeHtml(_ input: String) -> String {
        if input.isEmpty { return input }

        var result = input
        result = result.replacingOccurrences(of: "&#039;", with: "'")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")

        result = replacingMatches(result, Self.decimalEntityRegex) { text in
            guard let code = Int(text), code >= 0, code <= 0x10FFFF,
                let scalar = UnicodeScalar(UInt32(code))
            else { return nil }
            return String(Character(scalar))
        }

        result = replacingMatches(result, Self.hexEntityRegex) { text in
            guard let code = UInt32(text, radix: 16), let scalar = UnicodeScalar(code) else {
                return nil
            }
            return String(Character(scalar))
        }

        return result
    }

    private func replacingMatches(
        _ text: String,
        _ regex: NSRegularExpression,
        _ transform: (String) -> String?
    ) -> String {
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if matches.isEmpty { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text),
                let captureRange = Range(match.range(at: 1), in: text)
            else { continue }
            let replacement = transform(String(text[captureRange]))
            result += text[cursor..<range.lowerBound]
            if let replacement {
                result += replacement
            } else {
                result += text[range]
            }
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
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
