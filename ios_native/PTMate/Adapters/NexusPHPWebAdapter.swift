import Foundation
import SwiftSoup

final class NexusPHPWebAdapter: SiteAdapter, NexusPHPHelper {
    private var _siteConfig: SiteConfig!
    private var client: HttpClient!
    private var _discountMapping: [String: String]?
    private var _tagMapping: [String: String]?
    private var _customTemplate: SiteConfigTemplate?
    private var _finderConfigCache: [String: [String: Any]] = [:]
    private var _requestConfigCache: [String: NexusPHPWebRequestConfigCacheEntry] = [:]

    var tagMapping: [String: String]? {
        _tagMapping
    }

    var discountMapping: [String: String]? {
        _discountMapping
    }

    var siteConfig: SiteConfig {
        _siteConfig
    }

    private static let maxHtmlDumpLength = 200 * 1024

    private func logRuleAndSoup(_ tag: String, _ rule: [String: Any]?, _ soup: Node?) {
        let ruleJson = rule.map { jsonEncodeString($0) } ?? "{}"
        var html = ""
        if let soup {
            html = (try? soup.outerHtml()) ?? ""
        }
        if html.utf16.count > Self.maxHtmlDumpLength {
            html = String(decoding: Array(html.utf16.prefix(Self.maxHtmlDumpLength)), as: UTF16.self)
                + "\n... (truncated)"
        }
        NexusPHPWebLog.write("[\(tag)] rule=\(ruleJson)")
        NexusPHPWebLog.write("HTML=\(html)")
    }

    func initialize(_ config: SiteConfig) async throws {
        _siteConfig = config
        await loadDiscountMapping()
        await loadTagMapping()
        client = HttpClient(baseURL: config.baseUrl)
        client.cookieProvider = { [weak self] in
            self?.siteConfig.cookie
        }
    }

    func setCustomTemplate(_ template: SiteConfigTemplate) {
        _customTemplate = template
        _finderConfigCache.removeAll()
        _requestConfigCache.removeAll()
    }

    private func loadDiscountMapping() async {
        if let customTemplate = _customTemplate {
            _discountMapping = customTemplate.discountMapping
            return
        }
        let template = await SiteConfigService.shared.getTemplateById(
            _siteConfig.templateId,
            siteType: _siteConfig.siteType
        )
        if let mapping = template?.discountMapping {
            _discountMapping = mapping
        }
    }

    private func loadTagMapping() async {
        if let customTemplate = _customTemplate {
            _tagMapping = customTemplate.tagMapping
            return
        }
        let template = await SiteConfigService.shared.getTemplateById(
            _siteConfig.templateId,
            siteType: _siteConfig.siteType
        )
        if let mapping = template?.tagMapping {
            _tagMapping = mapping
        }
    }

    func fetchMemberProfile(apiKey: String?) async throws -> MemberProfile {
        do {
            let config = try await getUserInfoConfig()
            let path = try JSONCast.optionalString(config["path"]) ?? "usercp.php"

            let response = try await client.perform(HTTPRequest("/\(path)"))
            let soup = try NexusPHPWebParser.parseSoup(response.text)

            let userInfo = try await extractUserInfoByConfig(soup, config)

            let passKey = try await extractPassKeyByConfig()
            let bonusPerHour = try await extractBonusPerHourByConfig()

            let ratioText = (userInfoValue(userInfo, "ratio") ?? "0")
                .replacingOccurrences(of: ",", with: "")
            let bonusText = (userInfoValue(userInfo, "bonus") ?? "0")
                .replacingOccurrences(of: ",", with: "")
            let shareRate = dartDoubleFromString(ratioText) ?? 0.0
            let bonusPoints = dartDoubleFromString(bonusText) ?? 0.0

            let uploadedBytes = 0
            let downloadedBytes = 0

            let uidStr = userInfoValue(userInfo, "userId") ?? ""
            if let passKey, !passKey.isEmpty, (_siteConfig.passKey ?? "").isEmpty {
                _siteConfig = _siteConfig.copyWith(passKey: passKey)
            }
            if !uidStr.isEmpty, (_siteConfig.userId ?? "").isEmpty {
                _siteConfig = _siteConfig.copyWith(userId: uidStr)
            }

            return MemberProfile(
                username: userInfoValue(userInfo, "userName") ?? "",
                bonus: bonusPoints,
                shareRate: shareRate,
                uploadedBytes: uploadedBytes,
                downloadedBytes: downloadedBytes,
                uploadedBytesString: userInfoValue(userInfo, "upload") ?? "0 B",
                downloadedBytesString: userInfoValue(userInfo, "download") ?? "0 B",
                userId: userInfoValue(userInfo, "userId"),
                passKey: passKey,
                lastAccess: nil,
                bonusPerHour: bonusPerHour
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取用户资料")
        }
    }

    private func userInfoValue(_ info: [String: String?], _ key: String) -> String? {
        guard let value = info[key] else { return nil }
        return value
    }

    private func getFinderConfig(_ configType: String) async throws -> [String: Any] {
        if let cached = _finderConfigCache[configType] {
            return cached
        }

        if let infoFinder = _customTemplate?.infoFinder,
           let value = infoFinder[configType],
           !(value is NSNull)
        {
            let config = try JSONCast.map(value)
            _finderConfigCache[configType] = config
            return config
        }

        if _siteConfig.templateId != "-1" {
            do {
                let template = await SiteConfigService.shared.getTemplateById(
                    _siteConfig.templateId,
                    siteType: _siteConfig.siteType
                )
                if let infoFinder = template?.infoFinder,
                   let value = infoFinder[configType],
                   !(value is NSNull)
                {
                    let config = try JSONCast.map(value)
                    _finderConfigCache[configType] = config
                    return config
                }
            } catch {
            }
        }

        let template = await SiteConfigService.shared.getTemplateById("", siteType: .nexusphpweb)
        if let infoFinder = template?.infoFinder,
           let value = infoFinder[configType],
           !(value is NSNull)
        {
            let config = try JSONCast.map(value)
            _finderConfigCache[configType] = config
            return config
        }

        let emptyConfig: [String: Any] = [:]
        _finderConfigCache[configType] = emptyConfig
        return emptyConfig
    }

    private func getRequestConfig(_ action: String) async throws -> [String: Any]? {
        if let cached = _requestConfigCache[action] {
            switch cached {
            case .value(let config):
                return config
            case .missing:
                return nil
            }
        }

        var templatesToTry: [SiteConfigTemplate?] = []

        if let customTemplate = _customTemplate {
            templatesToTry.append(customTemplate)
        }

        if _siteConfig.templateId != "-1" && !_siteConfig.templateId.isEmpty {
            let template = await SiteConfigService.shared.getTemplateById(
                _siteConfig.templateId,
                siteType: _siteConfig.siteType
            )
            if let template {
                templatesToTry.append(template)
            }
        }

        let defaultTemplate = await SiteConfigService.shared.getTemplateById(
            "",
            siteType: .nexusphpweb
        )
        if let defaultTemplate {
            templatesToTry.append(defaultTemplate)
        }

        let parts = action.components(separatedBy: ".")
        for template in templatesToTry {
            guard let template, let request = template.request else { continue }

            var current: Any = request
            var found = true
            for part in parts {
                if let map = current as? [String: Any],
                   let next = map[part],
                   !(next is NSNull)
                {
                    current = next
                } else {
                    found = false
                    break
                }
            }

            if found, let config = current as? [String: Any] {
                _requestConfigCache[action] = .value(config)
                return config
            }
        }

        _requestConfigCache[action] = .missing
        return nil
    }

    private func getUserInfoConfig() async throws -> [String: Any] {
        try await getFinderConfig("userInfo")
    }

    private func extractUserInfoByConfig(
        _ soup: Node,
        _ config: [String: Any]
    ) async throws -> [String: String?] {
        let extractor = HtmlExtractor()

        let rowsConfig = try JSONCast.optionalMap(config["rows"])
        let fieldsConfig = try JSONCast.optionalMap(config["fields"])

        if rowsConfig == nil || fieldsConfig == nil {
            throw SiteServiceException(message: "配置格式错误：缺少 rows 或 fields 配置")
        }

        guard let rowSelector = try JSONCast.optionalString(rowsConfig?["selector"]),
              !rowSelector.isEmpty
        else {
            throw SiteServiceException(message: "配置错误：缺少行选择器")
        }

        guard let targetElement = extractor.findFirst(soup, rowSelector) else {
            logRuleAndSoup("userInfo.rows.notFound", rowsConfig, soup)
            throw SiteServiceException(message: "未找到目标元素：\(rowSelector)")
        }

        var result: [String: String?] = [:]
        let parsedFields = HtmlExtractor.parseFieldConfigs(fieldsConfig)

        for (key, fieldConfig) in parsedFields {
            result[key] = extractor.extractFieldSync(targetElement, fieldConfig).string
        }

        return result
    }

    private func extractBonusPerHourByConfig() async throws -> Double? {
        do {
            let bonusConfig = try await getFinderConfig("bonusPerHour")
            let path = try JSONCast.optionalString(bonusConfig["path"]) ?? "mybonus.php"

            let response = try await client.perform(HTTPRequest("/\(path)"))
            let soup = try NexusPHPWebParser.parseSoup(response.text)

            let extractor = HtmlExtractor()
            let rowsConfig = try JSONCast.optionalMap(bonusConfig["rows"])
            let fieldsConfig = try JSONCast.optionalMap(bonusConfig["fields"])

            if rowsConfig == nil || fieldsConfig == nil {
                throw SiteServiceException(message: "配置格式错误：缺少 rows 或 fields 配置")
            }

            guard let rowSelector = try JSONCast.optionalString(rowsConfig?["selector"]),
                  !rowSelector.isEmpty
            else {
                throw SiteServiceException(message: "配置错误：缺少行选择器")
            }

            guard let targetElement = extractor.findFirst(soup, rowSelector) else {
                logRuleAndSoup("bonus.rows.notFound", rowsConfig, soup)
                throw SiteServiceException(message: "未找到目标元素：\(rowSelector)")
            }

            let parsedFields = HtmlExtractor.parseFieldConfigs(fieldsConfig)
            guard let field = parsedFields["bonusPerHour"] else {
                logRuleAndSoup("bonus.field.missing", fieldsConfig, soup)
                throw SiteServiceException(message: "配置错误：缺少 bonusPerHour 字段")
            }

            let value = extractor.extractFieldSync(targetElement, field)

            if !value.hasValue { return nil }

            return value.doubleValue
        } catch {
            logRuleAndSoup("bonus.extract.failed", nil, nil)
            return nil
        }
    }

    private func extractPassKeyByConfig() async throws -> String? {
        do {
            let passKeyConfig = try await getFinderConfig("passKey")

            guard let path = try JSONCast.optionalString(passKeyConfig["path"]),
                  !path.isEmpty
            else {
                throw SiteServiceException(message: "PassKey配置中缺少path字段")
            }
            let response = try await client.perform(HTTPRequest("/\(path)"))
            let soup = try NexusPHPWebParser.parseSoup(response.text)

            let extractor = HtmlExtractor()

            let rowsConfig = try JSONCast.optionalMap(passKeyConfig["rows"])

            if rowsConfig == nil {
                logRuleAndSoup("passKey.rows.missing", passKeyConfig, soup)
                throw SiteServiceException(message: "配置格式错误：缺少 rows 配置")
            }

            guard let rowSelector = try JSONCast.optionalString(rowsConfig?["selector"]),
                  !rowSelector.isEmpty
            else {
                throw SiteServiceException(message: "配置错误：缺少行选择器")
            }

            guard let targetElement = extractor.findFirst(soup, rowSelector) else {
                logRuleAndSoup("passKey.rows.notFound", rowsConfig, soup)
                throw SiteServiceException(message: "未找到目标元素：\(rowSelector)")
            }

            let parsedFields = HtmlExtractor.parseFieldConfigs(
                try JSONCast.optionalMap(passKeyConfig["fields"])
            )
            let passKeyField = parsedFields["passKey"]

            if let passKeyField {
                let value = extractor.extractFieldSync(targetElement, passKeyField)

                if value.hasValue {
                    return value.string?.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                logRuleAndSoup("passKey.field.extractFailed", passKeyField.toJson(), targetElement)
                logRuleAndSoup("passKey.rows.info", rowsConfig, soup)
                throw SiteServiceException(
                    message: "提取PassKey失败：未匹配到目标元素\(rowSelector)"
                )
            }

            logRuleAndSoup("passKey.field.undefined", passKeyConfig, soup)
            throw SiteServiceException(message: "无法从配置中提取PassKey")
        } catch {
            logRuleAndSoup("passKey.extract.failed", nil, nil)
            throw SiteServiceException(
                message: "提取PassKey失败: \(NexusPHPWebErrorText.text(error))"
            )
        }
    }

    func searchTorrents(
        keyword: String?,
        pageNumber: Int,
        pageSize: Int,
        onlyFav: Int?,
        additionalParams: [String: Any]?
    ) async throws -> TorrentSearchResult {
        do {
            var searchAction = "search.normal"

            var categoryParam: String?
            if let additionalParams, additionalParams.keys.contains("category") {
                categoryParam = try JSONCast.optionalString(additionalParams["category"])
                if let categoryParam, categoryParam.hasPrefix("special") {
                    searchAction = "search.special"
                }
            }

            guard let requestConfig = try await getRequestConfig(searchAction) else {
                throw SiteServiceException(message: "未找到搜索配置: \(searchAction)")
            }

            let method = try JSONCast.optionalString(requestConfig["method"]) ?? "GET"
            let configParams = try JSONCast.optionalMap(requestConfig["params"]) ?? [:]

            var categoryId = ""
            if let categoryParam {
                let parts = categoryParam.components(separatedBy: "#")
                if parts.count == 2 && !parts[1].isEmpty {
                    categoryId = parts[1]
                }
            }

            let variables: [String: Any] = [
                "keyword": keyword ?? "",
                "page": pageNumber - 1,
                "pageSize": pageSize,
                "categoryId": categoryId,
                "onlyFav": onlyFav == 1 ? "1" : "",
            ]
            let path = NexusPHPWebCore.replacePlaceholders(
                try JSONCast.optionalString(requestConfig["path"]) ?? "/torrents.php",
                variables
            )

            var queryParams: [String: Any] = [:]
            for (key, value) in configParams {
                if let value = value as? String,
                   (value.contains("{categoryId}") && categoryId.isEmpty)
                    || (value.contains("{onlyFav}") && onlyFav != 1)
                {
                    continue
                }
                queryParams[key] = NexusPHPWebCore.replacePlaceholdersDeep(value, variables)
            }

            if let additionalParams {
                for (key, value) in additionalParams where key != "category" {
                    queryParams[key] = value
                }
            }

            let upperMethod = method.uppercased()
            let request: HTTPRequest
            if upperMethod == "GET" {
                request = HTTPRequest(
                    path,
                    method: .get,
                    query: stringParams(queryParams)
                )
            } else if upperMethod == "POST" {
                request = HTTPRequest(path, method: .post, body: .json(queryParams))
            } else {
                request = HTTPRequest(
                    path,
                    method: HTTPMethod(rawValue: upperMethod) ?? .get
                )
            }

            let response = try await client.perform(request)

            let searchConfig = try await getFinderConfig("search")
            let totalPagesConfig = try await getFinderConfig("totalPages")

            if searchConfig.isEmpty {
                return TorrentSearchResult(
                    pageNumber: pageNumber,
                    pageSize: pageSize,
                    total: 0,
                    totalPages: 0,
                    items: []
                )
            }

            let parseParams = NexusPHPWebParseSearchParams(
                html: response.text,
                searchConfig: searchConfig,
                totalPagesConfig: totalPagesConfig,
                discountMapping: _discountMapping ?? [:],
                tagMapping: _tagMapping ?? [:],
                baseUrl: _siteConfig.baseUrl,
                passKey: _siteConfig.passKey ?? "",
                userId: _siteConfig.userId ?? "",
                pageNumber: pageNumber,
                pageSize: pageSize
            )

            let result = try NexusPHPWebParser.parseSearchResponse(parseParams)

            return TorrentSearchResult(
                pageNumber: pageNumber,
                pageSize: pageSize,
                total: result.items.count * result.totalPages,
                totalPages: result.totalPages,
                items: result.items
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "搜索种子")
        }
    }

    func downloadTorrent(_ url: String) async throws -> Data {
        do {
            var downloadUrl = url
            if downloadUrl.hasPrefix("##") {
                downloadUrl = String(downloadUrl.dropFirst(2))
            }

            NexusPHPWebLog.write("NexusPHPWebAdapter: Downloading torrent from \(downloadUrl)")

            let response = try await client.perform(HTTPRequest(downloadUrl))

            NexusPHPWebLog.write(
                "NexusPHPWebAdapter: Download finished. Status: \(response.statusCode)"
            )
            NexusPHPWebLog.write(
                "NexusPHPWebAdapter: Final URI: \(response.url.absoluteString)"
            )

            let finalUri = response.url.absoluteString
            if finalUri.contains("login") || finalUri.contains("verify") {
                throw SiteServiceException(
                    message: "Download redirected to login/verify page. Check cookies."
                )
            }

            let contentType = NexusPHPWebSafeContentTypeTransformer.transform(
                response.headers["content-type"] ?? ""
            )
            if !contentType.isEmpty,
               !contentType.contains("bittorrent"),
               !contentType.contains("octet-stream")
            {
                NexusPHPWebLog.write(
                    "NexusPHPWebAdapter: Warning - Content-Type is \(contentType), might not be a torrent file."
                )
            }

            return response.data
        } catch {
            NexusPHPWebLog.write("下载种子文件失败: \(NexusPHPWebErrorText.text(error))")
            throw error
        }
    }

    func parseTotalPages(_ soup: Node) async throws -> Int {
        let config = try await getFinderConfig("totalPages")
        if config.isEmpty {
            return 1
        }
        var logs: [String]? = nil
        return NexusPHPWebParser.parseTotalPages(soup, config, logs: &logs)
    }

    func parseTorrentList(_ soup: Node) async throws -> [TorrentItem] {
        let searchConfig = try await getFinderConfig("search")
        if searchConfig.isEmpty { return [] }

        var logs: [String]? = nil
        return NexusPHPWebParser.parseTorrentList(
            soup,
            searchConfig,
            _discountMapping ?? [:],
            _tagMapping ?? [:],
            _siteConfig.baseUrl,
            _siteConfig.passKey ?? "",
            _siteConfig.userId ?? "",
            logs: &logs
        )
    }

    func fetchTorrentDetail(
        _ id: String,
        description: String?,
        detailUrl: String?
    ) async throws -> TorrentDetail {
        let baseUrl = _siteConfig.baseUrl.hasSuffix("/")
            ? String(_siteConfig.baseUrl.dropLast())
            : _siteConfig.baseUrl
        let defaultDetailUrl = "\(baseUrl)/details.php?id=\(id)&hit=1"
        let resolvedDetailUrl =
            NexusPHPWebCore.resolveHttpUrl(detailUrl, _siteConfig.baseUrl) ?? defaultDetailUrl

        if _siteConfig.features.nativeDetail {
            if let description, !description.isEmpty {
                return TorrentDetail(
                    descr: "",
                    descrHtml: description,
                    webviewUrl: resolvedDetailUrl
                )
            }
            do {
                let response = try await client.perform(HTTPRequest(resolvedDetailUrl))
                let soup = try NexusPHPWebParser.parseSoup(response.text)

                var extractedContent = ""
                var isBbcode = false
                do {
                    let detailConfig = try await getFinderConfig("detail")
                    if !detailConfig.isEmpty {
                        isBbcode = try JSONCast.optionalBool(detailConfig["isBbcode"]) ?? false
                        let rowsConfig = try JSONCast.optionalMap(detailConfig["rows"])
                        let selector = try JSONCast.optionalString(rowsConfig?["selector"])
                        if let selector, !selector.isEmpty {
                            if let element = SelectorEngine.findFirstElementBySelector(soup, selector) {
                                extractedContent = isBbcode
                                    ? (SelectorEngine.dartText(element) ?? "")
                                    : innerHtml(element)
                            }
                        }
                    }
                } catch {
                }

                if extractedContent.isEmpty {
                    if let kdescr = findKdescrElement(soup) {
                        extractedContent = isBbcode
                            ? (SelectorEngine.dartText(kdescr) ?? "")
                            : innerHtml(kdescr)
                    }
                }

                if !extractedContent.isEmpty {
                    if isBbcode {
                        return TorrentDetail(
                            descr: extractedContent,
                            webviewUrl: resolvedDetailUrl
                        )
                    }
                    extractedContent = NexusPHPWebCore.replaceAssetUrls(
                        extractedContent,
                        baseUrl
                    )
                    return TorrentDetail(
                        descr: "",
                        descrHtml: extractedContent,
                        webviewUrl: resolvedDetailUrl
                    )
                }

                NexusPHPWebLog.write("NativeDetail: 未能提取到描述内容，回退到 WebView 模式")
            } catch {
                NexusPHPWebLog.write(
                    "NativeDetail: 提取失败，回退到 WebView: \(NexusPHPWebErrorText.text(error))"
                )
            }
        }

        WebAdapterCore.syncCookiesToWebView(_siteConfig)

        return TorrentDetail(descr: "", webviewUrl: resolvedDetailUrl)
    }

    private func findKdescrElement(_ soup: Element) -> Element? {
        if let element = try? soup.select("div#kdescr").first() {
            return element
        }
        if let element = try? soup.select("td#kdescr").first() {
            return element
        }
        if let element = try? soup.select("#kdescr").first() {
            return element
        }
        return nil
    }

    private func innerHtml(_ node: Node) -> String {
        guard let element = node as? Element else { return "" }
        return (try? element.html()) ?? ""
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

    func genDlToken(id: String, url: String?) async throws -> String {
        guard let passKey = _siteConfig.passKey, !passKey.isEmpty else {
            throw SiteServiceException(message: "站点配置缺少passKey，无法生成下载链接")
        }
        guard let userId = _siteConfig.userId, !userId.isEmpty else {
            throw SiteServiceException(message: "站点配置缺少userId，无法生成下载链接")
        }

        let jwt = getDownLoadHash(passKey, id, userId)
        if let url, !url.isEmpty {
            return url
                .replacingOccurrences(of: "{jwt}", with: jwt)
                .replacingOccurrences(of: "{userId}", with: userId)
        }
        let baseUrl = _siteConfig.baseUrl.hasSuffix("/")
            ? String(_siteConfig.baseUrl.dropLast())
            : _siteConfig.baseUrl
        return "\(baseUrl)/download.php?downhash=\(userId).\(jwt)"
    }

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        throw SiteServiceException(message: "queryHistory not implemented")
    }

    func toggleCollection(torrentId: String, make: Bool) async throws {
        do {
            var actionConfig: [String: Any]?
            if !make {
                actionConfig = try await getRequestConfig("unCollect")
            }
            if actionConfig == nil {
                actionConfig = try await getRequestConfig("collect")
            }

            if let actionConfig {
                let url = try JSONCast.optionalString(actionConfig["path"])
                    ?? (try JSONCast.optionalString(actionConfig["url"]))
                    ?? "/bookmark.php"
                let method = try JSONCast.optionalString(actionConfig["method"]) ?? "GET"
                let params = try JSONCast.optionalMap(actionConfig["params"]) ?? [:]
                let headers = try JSONCast.optionalMap(actionConfig["headers"]) ?? [:]

                var processedParams: [String: Any] = [:]
                for (key, value) in params {
                    if let value = value as? String, value.contains("{torrentId}") {
                        processedParams[key] = value.replacingOccurrences(
                            of: "{torrentId}",
                            with: torrentId
                        )
                    } else {
                        processedParams[key] = value
                    }
                }

                if method.uppercased() == "POST" {
                    _ = try await client.perform(
                        HTTPRequest(
                            url,
                            method: .post,
                            headers: stringParams(headers),
                            body: .form(stringParams(processedParams))
                        )
                    )
                } else {
                    _ = try await client.perform(
                        HTTPRequest(
                            url,
                            method: .get,
                            headers: stringParams(headers),
                            query: stringParams(processedParams)
                        )
                    )
                }
            } else {
                _ = try await client.perform(
                    HTTPRequest("/bookmark.php", query: ["torrentid": torrentId])
                )
            }
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "切换收藏状态")
        }
    }

    func testConnection() async throws -> Bool {
        throw SiteServiceException(message: "testConnection not implemented")
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
            let categoriesConfig = try await getFinderConfig("categories")
            guard let path = try JSONCast.optionalString(categoriesConfig["path"]),
                  !path.isEmpty
            else {
                throw SiteServiceException(message: "配置错误：缺少 categories.path")
            }

            let response = try await client.perform(HTTPRequest("/\(path)"))

            if response.statusCode == 200 {
                let soup = try NexusPHPWebParser.parseSoup(response.text)
                let parsedCategories = try await parseCategories(soup, categoriesConfig)
                categories.append(contentsOf: parsedCategories)
            }

            return categories
        } catch {
            return categories
        }
    }

    private func parseCategories(
        _ soup: Node,
        _ categoriesConfig: [String: Any]
    ) async throws -> [SearchCategoryConfig] {
        var categories: [SearchCategoryConfig] = []
        let extractor = HtmlExtractor()

        let rowsConfig = try JSONCast.optionalMap(categoriesConfig["rows"])
        let fieldsConfig = try JSONCast.optionalMap(categoriesConfig["fields"])

        if rowsConfig == nil || fieldsConfig == nil {
            logRuleAndSoup("categories.config.missing", categoriesConfig, soup)
            throw SiteServiceException(message: "配置格式错误：缺少 rows 或 fields 配置")
        }

        guard let rowSelector = try JSONCast.optionalString(rowsConfig?["selector"]),
              !rowSelector.isEmpty
        else {
            throw SiteServiceException(message: "配置错误：缺少行选择器")
        }

        let rowElements = extractor.findRows(soup, rowSelector)
        if rowElements.isEmpty {
            logRuleAndSoup("categories.rows.notFound", rowsConfig, soup)
            throw SiteServiceException(message: "未找到目标元素：\(rowSelector)")
        }

        let parsedFields = HtmlExtractor.parseFieldConfigs(fieldsConfig)
        guard let categoryIdField = parsedFields["categoryId"],
              let categoryNameField = parsedFields["categoryName"]
        else {
            throw SiteServiceException(message: "配置错误：缺少 categoryId 或 categoryName 字段配置")
        }

        var batchIndex = 1

        for rowElement in rowElements {
            let categoryIdValues = extractor.extractFieldValuesSync(
                rowElement,
                categoryIdField
            )
            let categoryNameValues = extractor.extractFieldValuesSync(
                rowElement,
                categoryNameField
            )

            if categoryIdValues.isEmpty && categoryNameValues.isEmpty {
                continue
            }

            let minLength = min(categoryIdValues.count, categoryNameValues.count)

            if minLength == 0 {
                continue
            }

            for index in 0..<minLength {
                let categoryId = categoryIdValues[index]
                let categoryName = categoryNameValues[index]

                if !categoryId.isEmpty && !categoryName.isEmpty {
                    let prefix: String
                    if batchIndex == 1 {
                        prefix = "normal#"
                    } else if batchIndex == 2 {
                        prefix = "special#"
                    } else {
                        prefix = "batch\(batchIndex)#"
                    }

                    categories.append(
                        SearchCategoryConfig(
                            id: categoryId,
                            displayName: batchIndex > 1 ? "s_\(categoryName)" : categoryName,
                            parameters: "{\"category\":\"\(prefix)\(categoryId)\"}"
                        )
                    )
                }
            }

            batchIndex += 1
        }

        return categories
    }

    private func stringParams(_ params: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in params {
            out[key] = dartToString(value)
        }
        return out
    }
}
