import Foundation
import SwiftSoup

final class WebAdapterConfigurationException: SiteException {
    let statusCode: Int?

    init(message: String) {
        self.statusCode = nil
        super.init(message, nil)
    }
}

enum WebAdapterCore {
    static let defaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/143.0.0.0 Safari/537.36"

    private static let placeholderRegex = try! NSRegularExpression(
        pattern: "\\{([A-Za-z0-9_]+)\\}"
    )

    static func createClient(_ config: SiteConfig) -> HttpClient {
        let client = HttpClient(
            baseURL: config.baseUrl,
            userAgent: defaultUserAgent,
            kind: .site
        )
        client.cookieProvider = { config.cookie }
        return client
    }

    static func replacePlaceholders(_ source: String, _ variables: [String: Any]) -> String {
        let matches = placeholderRegex.matches(
            in: source,
            options: [],
            range: NSRange(source.startIndex..., in: source)
        )
        if matches.isEmpty { return source }

        var output = ""
        var cursor = source.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: source),
                  let nameRange = Range(match.range(at: 1), in: source)
            else { continue }
            output += source[cursor..<fullRange.lowerBound]
            if let value = presentValue(variables[String(source[nameRange])]) {
                output += dartToString(value)
            }
            cursor = fullRange.upperBound
        }
        output += source[cursor...]
        return output
    }

    static func replacePlaceholdersDeep(_ value: Any?, _ variables: [String: Any]) -> Any? {
        if let string = value as? String {
            return replacePlaceholders(string, variables)
        }
        if let list = value as? [Any] {
            return list.map { replacePlaceholdersDeep($0, variables) ?? NSNull() }
        }
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, entry) in dictionary {
                result[key] = replacePlaceholdersDeep(entry, variables) ?? NSNull()
            }
            return result
        }
        return value
    }

    static func resolveHttpUrl(_ value: String?, _ baseUrl: String) -> String? {
        guard let value else { return nil }
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        guard let base = URL(string: baseUrl),
              let baseScheme = base.scheme,
              !baseScheme.isEmpty,
              let baseHost = base.host,
              !baseHost.isEmpty
        else { return nil }

        let resolved: URL?
        if raw.hasPrefix("//") {
            resolved = URL(string: "\(baseScheme):\(raw)")
        } else if let candidate = URL(string: raw), candidate.scheme != nil {
            resolved = candidate
        } else {
            resolved = URL(string: raw, relativeTo: base)?.absoluteURL
        }

        guard let resolved,
              let scheme = resolved.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = resolved.host,
              !host.isEmpty
        else { return nil }
        return resolved.absoluteString
    }

    static func syncCookiesToWebView(_ config: SiteConfig) {
        #if canImport(Darwin)
        guard let cookieHeader = config.cookie, !cookieHeader.isEmpty else { return }
        guard let baseUrl = URL(string: config.baseUrl),
              let host = baseUrl.host,
              !host.isEmpty
        else { return }

        let isSecure = baseUrl.scheme?.lowercased() == "https"
        for segment in cookieHeader.split(separator: ";", omittingEmptySubsequences: false) {
            guard let separator = segment.firstIndex(of: "="),
                  separator != segment.startIndex
            else { continue }
            let name = String(segment[segment.startIndex..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(segment[segment.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: host,
                .path: "/",
                .secure: isSecure,
            ]
            if let cookie = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        #endif
    }

    private static func presentValue(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        return value
    }
}

struct WebSearchParseResult {
    let items: [TorrentItem]
    let totalPages: Int
    let candidateItemRows: Int
}

enum WebAdapterDiagnosticStage {
    case request
    case searchParse
}

struct WebAdapterDiagnostic {
    let stage: WebAdapterDiagnosticStage
    let method: String?
    let path: String?
    let parameterKeys: [String]
    let statusCode: Int?
    let responseBytes: Int?
    let outcome: String?
    let parser: String?
    let candidateItemRows: Int?
    let parsedItems: Int?
    let totalPages: Int?

    init(
        stage: WebAdapterDiagnosticStage,
        method: String? = nil,
        path: String? = nil,
        parameterKeys: [String] = [],
        statusCode: Int? = nil,
        responseBytes: Int? = nil,
        outcome: String? = nil,
        parser: String? = nil,
        candidateItemRows: Int? = nil,
        parsedItems: Int? = nil,
        totalPages: Int? = nil
    ) {
        self.stage = stage
        self.method = method
        self.path = path
        self.parameterKeys = parameterKeys
        self.statusCode = statusCode
        self.responseBytes = responseBytes
        self.outcome = outcome
        self.parser = parser
        self.candidateItemRows = candidateItemRows
        self.parsedItems = parsedItems
        self.totalPages = totalPages
    }

    func toSafeLogLine() -> String {
        switch stage {
        case .request:
            return "WebAdapter request: "
                + "method=\(method ?? "-") "
                + "path=\(path ?? "-") "
                + "paramKeys=[\(parameterKeys.joined(separator: ","))] "
                + "status=\(statusCode.map { String($0) } ?? "-") "
                + "responseBytes=\(responseBytes ?? 0) "
                + "outcome=\(outcome ?? "-")"
        case .searchParse:
            return "WebAdapter search parse: "
                + "parser=\(parser ?? "flatTable") "
                + "candidateRows=\(candidateItemRows ?? 0) "
                + "parsedItems=\(parsedItems ?? 0) "
                + "totalPages=\(totalPages ?? 1)"
        }
    }
}

final class WebAdapter: SiteAdapter {
    private var _siteConfig: SiteConfig!
    private var client: HttpClient!
    private var _customTemplate: SiteConfigTemplate?
    private var _template: SiteConfigTemplate?
    private let providedClient: HttpClient?
    private let diagnosticSink: ((WebAdapterDiagnostic) -> Void)?

    init(
        client: HttpClient? = nil,
        diagnosticSink: ((WebAdapterDiagnostic) -> Void)? = nil
    ) {
        self.providedClient = client
        self.diagnosticSink = diagnosticSink
    }

    var siteConfig: SiteConfig {
        _siteConfig
    }

    func initialize(_ config: SiteConfig) async throws {
        if config.siteType != .web {
            throw WebAdapterConfigurationException(
                message: "WebAdapter 仅支持 SiteType.web，当前为 \(config.siteType.id)"
            )
        }
        _siteConfig = config
        if let providedClient {
            client = providedClient
        } else {
            client = WebAdapterCore.createClient(config)
        }
    }

    func setCustomTemplate(_ template: SiteConfigTemplate) throws {
        if template.siteType != .web {
            throw WebAdapterConfigurationException(message: "通用 Web 适配器只能使用 SiteType.web 模板")
        }
        _customTemplate = template
        _template = nil
    }

    private func getTemplate() async throws -> SiteConfigTemplate {
        if let custom = _customTemplate { return custom }
        if let cached = _template { return cached }

        let template = await SiteConfigService.shared.getTemplateById(
            _siteConfig.templateId,
            siteType: .web
        )
        guard let template, template.siteType == .web else {
            throw WebAdapterConfigurationException(
                message: "未找到 Web 模板: \(_siteConfig.templateId)。通用 Web 不会回退到 NexusPHPWeb 规则。"
            )
        }
        _template = template
        return template
    }

    private func getInfoFinder(_ key: String) async throws -> [String: Any] {
        let infoFinder = (try await getTemplate()).infoFinder
        guard let value = infoFinder?[key], let map = value as? [String: Any] else {
            throw WebAdapterConfigurationException(message: "Web 模板缺少 infoFinder.\(key) 配置")
        }
        return map
    }

    private func getRequest(_ key: String) async throws -> [String: Any] {
        let request = (try await getTemplate()).request
        guard let value = request?[key], let map = value as? [String: Any] else {
            throw WebAdapterConfigurationException(message: "Web 模板缺少 request.\(key) 配置")
        }
        return map
    }

    private func request(
        _ config: [String: Any],
        _ variables: [String: Any]
    ) async throws -> HTTPResponse {
        let pathTemplate = coalesce(config["path"], config["url"]) as? String
        guard let pathTemplate, !pathTemplate.isEmpty else {
            throw WebAdapterConfigurationException(message: "Web 请求配置缺少 path")
        }
        let method = (config["method"] as? String ?? "GET").uppercased()
        let path = WebAdapterCore.replacePlaceholders(pathTemplate, variables)
        let rawParams = coalesce(config["params"], config["queryParameters"])
        let params = replaceParams(rawParams, variables)
        let headers = stringMap(config["headers"])
        let httpMethod = method == "GET" ? HTTPMethod.get : HTTPMethod(rawValue: method)
        guard let httpMethod else {
            throw SiteServiceException(message: "Web 请求配置不支持的 HTTP 方法: \(method)")
        }
        do {
            let response: HTTPResponse
            if httpMethod == .get {
                response = try await client.perform(
                    HTTPRequest(
                        path,
                        method: httpMethod,
                        headers: headers,
                        query: stringQuery(params)
                    )
                )
            } else {
                response = try await client.perform(
                    HTTPRequest(
                        path,
                        method: httpMethod,
                        headers: headers,
                        body: .json(jsonBody(params))
                    )
                )
            }
            logRequestDiagnostics(
                method: method,
                path: path,
                params: params,
                statusCode: response.statusCode,
                responseBytes: responseByteLength(response.text),
                errorType: nil
            )
            return response
        } catch {
            logRequestDiagnostics(
                method: method,
                path: path,
                params: params,
                statusCode: errorStatusCode(error),
                responseBytes: 0,
                errorType: errorTypeName(error)
            )
            throw error
        }
    }

    private func logRequestDiagnostics(
        method: String,
        path: String,
        params: [String: Any],
        statusCode: Int?,
        responseBytes: Int,
        errorType: String?
    ) {
        let parameterKeys = params.keys.map { $0 }.sorted()
        emitDiagnostic(
            WebAdapterDiagnostic(
                stage: .request,
                method: method,
                path: safeDiagnosticPath(path),
                parameterKeys: parameterKeys,
                statusCode: statusCode,
                responseBytes: responseBytes,
                outcome: errorType == nil ? "ok" : "error:\(errorType!)"
            )
        )
    }

    private func logSearchParseDiagnostics(
        _ searchConfig: [String: Any],
        _ parsed: WebSearchParseResult
    ) {
        let parser = (searchConfig["parser"] as? String ?? "flatTable")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        emitDiagnostic(
            WebAdapterDiagnostic(
                stage: .searchParse,
                parser: parser,
                candidateItemRows: parsed.candidateItemRows,
                parsedItems: parsed.items.count,
                totalPages: parsed.totalPages
            )
        )
    }

    private func emitDiagnostic(_ diagnostic: WebAdapterDiagnostic) {
        diagnosticSink?(diagnostic)
    }

    private func safeDiagnosticPath(_ path: String) -> String {
        if let components = URLComponents(string: path) {
            let parsedPath = components.path
            if !parsedPath.isEmpty { return parsedPath }
        }
        let segments = path.components(separatedBy: CharacterSet(charactersIn: "?#"))
        let withoutQuery = segments.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return withoutQuery.isEmpty ? "/" : withoutQuery
    }

    private func responseByteLength(_ data: String) -> Int {
        if data.isEmpty { return 0 }
        return data.utf8.count
    }

    private func replaceParams(_ rawParams: Any?, _ variables: [String: Any]) -> [String: Any] {
        guard let dictionary = rawParams as? [String: Any] else { return [:] }
        var result: [String: Any] = [:]
        for (key, rawValue) in dictionary {
            if let rawString = rawValue as? String,
               rawString.contains("{categoryId}"),
               emptyCategoryId(variables["categoryId"])
            {
                continue
            }
            result[key] = WebAdapterCore.replacePlaceholdersDeep(rawValue, variables) ?? NSNull()
        }
        return result
    }

    private func emptyCategoryId(_ value: Any?) -> Bool {
        guard let value = presentValue(value) else { return true }
        return dartToString(value).isEmpty
    }

    private func stringQuery(_ params: [String: Any]) -> [String: String] {
        var query: [String: String] = [:]
        for (key, value) in params {
            guard let present = presentValue(value) else { continue }
            query[key] = dartToString(present)
        }
        return query
    }

    private func jsonBody(_ params: [String: Any]) -> [String: Any] {
        var body: [String: Any] = [:]
        for (key, value) in params {
            body[key] = presentValue(value) ?? NSNull()
        }
        return body
    }

    private func stringMap(_ value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, entry) in dictionary {
            result[key] = dartToString(entry)
        }
        return result
    }

    private func errorStatusCode(_ error: Error) -> Int? {
        if let authError = error as? SiteAuthenticationException {
            return authError.statusCode
        }
        if let configError = error as? WebAdapterConfigurationException {
            return configError.statusCode
        }
        if let serviceError = error as? SiteServiceException {
            return serviceError.statusCode
        }
        return nil
    }

    private func errorTypeName(_ error: Error) -> String {
        if let networkError = error as? SiteNetworkException {
            return networkError.isTimeout ? "connectionTimeout" : "connectionError"
        }
        if error is SiteAuthenticationException { return "badResponse" }
        if error is CloudflareChallengeException { return "badResponse" }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? "connectionTimeout" : "connectionError"
        }
        if let serviceError = error as? SiteServiceException, serviceError.statusCode != nil {
            return "badResponse"
        }
        return "unknown"
    }

    func fetchMemberProfile(apiKey: String?) async throws -> MemberProfile {
        do {
            let config = try await getInfoFinder("userInfo")
            var steps: [[String: Any]]
            if let rawSteps = presentValue(config["steps"]), let rawList = rawSteps as? [Any] {
                steps = rawList.compactMap { dynamicMap($0) }
            } else {
                steps = [dynamicMap(config)]
            }
            if steps.isEmpty {
                throw WebAdapterConfigurationException(message: "infoFinder.userInfo.steps 不能为空")
            }

            var values: [String: String] = ["baseUrl": _siteConfig.baseUrl]
            if let userId = _siteConfig.userId {
                values["userId"] = userId
            }
            if let passKey = _siteConfig.passKey {
                values["passKey"] = passKey
            }
            if let authKey = _siteConfig.authKey {
                values["authKey"] = authKey
            }
            for step in steps {
                let response = try await request(step, values)
                let extracted = try extractProfileValues(
                    soup: try SwiftSoup.parse(response.text),
                    config: step
                )
                for (key, value) in extracted where !value.isEmpty {
                    values[key] = value
                }
            }

            let passKey = values["passKey"]
            let authKey = values["authKey"]
            let userId = values["userId"]
            _siteConfig.userId = userId ?? _siteConfig.userId
            _siteConfig.passKey = passKey ?? _siteConfig.passKey
            _siteConfig.authKey = authKey ?? _siteConfig.authKey
            let upload = profileValue(values, ["upload", "uploaded"])
            let download = profileValue(values, ["download", "downloaded"])
            return MemberProfile(
                username: profileValue(values, ["userName", "username", "name"]),
                bonus: asDouble(profileValue(values, ["bonus", "bonusPoints"])),
                shareRate: asDouble(profileValue(values, ["ratio", "shareRate"])),
                uploadedBytes: TypedConverter.parseSizeToBytes(upload),
                downloadedBytes: TypedConverter.parseSizeToBytes(download),
                uploadedBytesString: upload.isEmpty ? "0 B" : upload,
                downloadedBytesString: download.isEmpty ? "0 B" : download,
                userId: userId,
                passKey: passKey,
                authKey: authKey,
                bonusPerHour: optionalDouble(values["bonusPerHour"]),
                seedingSizeBytes: TypedConverter.parseSizeToBytes(values["seedingSize"])
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "获取用户资料")
        }
    }

    private func extractProfileValues(
        soup: Node,
        config: [String: Any]
    ) throws -> [String: String] {
        let fields = dynamicMap(config["fields"])
        if fields.isEmpty {
            throw WebAdapterConfigurationException(message: "用户资料步骤缺少 fields 配置")
        }
        let rows = dynamicMap(config["rows"])
        let selector = rows["selector"] as? String
        let element: Node?
        if let selector, !selector.isEmpty {
            element = HtmlExtractor().findFirst(soup, selector)
        } else {
            element = soup
        }
        guard let element else {
            throw WebAdapterConfigurationException(
                message: "用户资料步骤未找到 rows.selector: \(selector ?? "null")"
            )
        }
        let values = WebSearchParser.extractValues(element, fields)
        let requiredFields = HtmlExtractor.parseFieldConfigs(fields)
            .filter { $0.value.required }
            .map { $0.key }
            .filter { key in values[key]?.isEmpty != false }
        if !requiredFields.isEmpty {
            throw SiteAuthenticationException(
                message: HttpClient.authExpiredMessage,
                detail: "用户资料页面缺少必填字段: \(requiredFields.joined(separator: ", "))"
            )
        }
        return values
    }

    func searchTorrents(
        keyword: String?,
        pageNumber: Int,
        pageSize: Int,
        onlyFav: Int?,
        additionalParams: [String: Any]?
    ) async throws -> TorrentSearchResult {
        do {
            let requestConfig = try await getRequest("search")
            let searchConfig = try await getInfoFinder("search")
            var additions: [String: Any] = [:]
            for (key, value) in additionalParams ?? [:] {
                additions[key] = value
            }
            let category = presentValue(additions["category"])
            var categoryId = ""
            if let category = category as? String {
                let split = category.components(separatedBy: "#")
                categoryId = split.count > 1 ? split[split.count - 1] : category
                if split.count > 1 {
                    additions.removeValue(forKey: "category")
                }
            }
            if categoryId.isEmpty {
                if let filterCat = presentValue(additions["filter_cat"]) {
                    categoryId = dartToString(filterCat)
                }
            }
            var variables: [String: Any] = [
                "baseUrl": _siteConfig.baseUrl,
                "keyword": keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                "page": pageNumber,
                "pageSize": pageSize,
                "categoryId": categoryId,
            ]
            if let onlyFav {
                variables["onlyFav"] = onlyFav
            } else {
                variables["onlyFav"] = ""
            }
            if let userId = _siteConfig.userId {
                variables["userId"] = userId
            }
            if let passKey = _siteConfig.passKey {
                variables["passKey"] = passKey
            }
            if let authKey = _siteConfig.authKey {
                variables["authKey"] = authKey
            }
            var requestWithAdditions = requestConfig
            let paramsKey = requestConfig.keys.contains("queryParameters")
                ? "queryParameters"
                : "params"
            var requestParams = dynamicMap(requestConfig[paramsKey])
            for (key, value) in additions {
                requestParams[key] = value
            }
            requestWithAdditions[paramsKey] = requestParams
            let response = try await request(requestWithAdditions, variables)
            let template = try await getTemplate()
            let parsed = try WebSearchParser.parse(
                html: response.text,
                searchConfig: searchConfig,
                baseUrl: _siteConfig.baseUrl,
                discountMapping: template.discountMapping,
                tagMapping: template.tagMapping
            )
            logSearchParseDiagnostics(searchConfig, parsed)
            return TorrentSearchResult(
                pageNumber: pageNumber,
                pageSize: pageSize,
                total: parsed.items.count * parsed.totalPages,
                totalPages: parsed.totalPages,
                items: parsed.items
            )
        } catch {
            throw ApiExceptionAdapter.wrapError(error, action: "搜索种子")
        }
    }

    func fetchTorrentDetail(
        _ id: String,
        description: String?,
        detailUrl: String?
    ) async throws -> TorrentDetail {
        var url = WebAdapterCore.resolveHttpUrl(detailUrl, _siteConfig.baseUrl)
        if url == nil {
            let template = try await getTemplate()
            let requestConfig = dynamicMap(template.request?["detail"])
            let path = coalesce(requestConfig["path"], requestConfig["url"])
            if let path = path as? String, !path.isEmpty {
                let relative = WebAdapterCore.replacePlaceholders(
                    path,
                    [
                        "torrentId": id,
                        "id": id,
                        "baseUrl": _siteConfig.baseUrl,
                    ]
                )
                url = WebAdapterCore.resolveHttpUrl(relative, _siteConfig.baseUrl)
            }
        }
        guard let url else {
            throw WebAdapterConfigurationException(
                message: "Web 种子详情缺少 detailUrl，且模板未提供 request.detail.path"
            )
        }
        WebAdapterCore.syncCookiesToWebView(_siteConfig)
        return TorrentDetail(descr: "", descrHtml: description, webviewUrl: url)
    }

    func genDlToken(id: String, url: String?) async throws -> String {
        if let direct = WebAdapterCore.resolveHttpUrl(url, _siteConfig.baseUrl) {
            return direct
        }

        let template = try await getTemplate()
        let requestConfig = dynamicMap(template.request?["download"])
        let path = coalesce(requestConfig["path"], requestConfig["url"])
        if let path = path as? String, !path.isEmpty {
            let relative = WebAdapterCore.replacePlaceholders(
                path,
                [
                    "torrentId": id,
                    "id": id,
                    "baseUrl": _siteConfig.baseUrl,
                ]
            )
            if let generated = WebAdapterCore.resolveHttpUrl(relative, _siteConfig.baseUrl) {
                return generated
            }
        }
        throw WebAdapterConfigurationException(
            message: "Web 种子下载缺少列表 downloadUrl，且模板未提供 request.download.path"
        )
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

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        [:]
    }

    func toggleCollection(torrentId: String, make: Bool) async throws {
        throw SiteServiceException(message: "通用 Web 站点暂不支持收藏操作")
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
        if !_siteConfig.searchCategories.isEmpty {
            return _siteConfig.searchCategories
        }
        return try await getTemplate().searchCategories
    }

    private func dynamicMap(_ value: Any?) -> [String: Any] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        var result: [String: Any] = [:]
        for (key, entry) in dictionary {
            result[key] = entry
        }
        return result
    }

    private func profileValue(_ values: [String: String], _ keys: [String]) -> String {
        for key in keys {
            if let value = values[key], !value.isEmpty { return value }
        }
        return ""
    }

    private func asDouble(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func optionalDouble(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        return asDouble(value)
    }

    private func presentValue(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        return value
    }

    private func coalesce(_ first: Any?, _ second: Any?) -> Any? {
        presentValue(first) ?? presentValue(second)
    }
}