import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case head = "HEAD"
}

enum HTTPBody {
    case form([String: String])
    case json(Any)
    case raw(Data, contentType: String)
}

struct HTTPRequest {
    var urlString: String
    var method: HTTPMethod = .get
    var headers: [String: String] = [:]
    var query: [String: String] = [:]
    var body: HTTPBody?

    init(_ urlString: String, method: HTTPMethod = .get, headers: [String: String] = [:], query: [String: String] = [:], body: HTTPBody? = nil) {
        self.urlString = urlString
        self.method = method
        self.headers = headers
        self.query = query
        self.body = body
    }
}

struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let data: Data
    let url: URL
    let redirectLocations: [URL]

    var text: String {
        HTTPCharset.decode(data, contentType: headers["content-type"])
    }

    func bodyJSON() throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }
}

enum HTTPCharset {
    static func decode(_ data: Data, contentType: String?) -> String {
        if let charsetName = charsetName(from: contentType),
           let encoding = cfEncoding(for: charsetName) {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func charsetName(from contentType: String?) -> String? {
        guard let contentType else { return nil }
        for part in contentType.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            if piece.lowercased().hasPrefix("charset=") {
                var value = piece.dropFirst("charset=".count)
                if value.hasPrefix("\"") || value.hasPrefix("'") {
                    value = value.dropFirst()
                    if value.hasSuffix("\"") || value.hasSuffix("'") {
                        value = value.dropLast()
                    }
                }
                return String(value).lowercased()
            }
        }
        return nil
    }

    static func cfEncoding(for name: String) -> String.Encoding? {
        switch name {
        case "utf-8", "utf8":
            return .utf8
        case "gb18030", "gbk", "gb2312", "gb_2312-80", "csgb2312", "x-gbk":
            return String.Encoding(rawValue: 0x80000632)
        case "big5", "big5-hkscs", "cn-big5", "csbig5":
            return String.Encoding(rawValue: 0x80000A03)
        case "shift_jis", "shift-jis", "sjis", "csshiftjis":
            return String.Encoding(rawValue: 0x80000A01)
        case "euc-jp", "x-euc-jp":
            return String.Encoding(rawValue: 0x80000A02)
        case "euc-kr", "euckr":
            return String.Encoding(rawValue: 0x80000A04)
        case "iso-8859-1", "iso8859-1", "latin1", "l1":
            return .isoLatin1
        case "iso-8859-15":
            return String.Encoding(rawValue: 0x80000A0D)
        case "windows-1252", "cp1252":
            return .windowsCP1252
        case "us-ascii", "ascii":
            return .ascii
        default:
            return nil
        }
    }
}

final class SessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let proxyUsername: String
    let proxyPassword: String
    let proxyHost: String
    let proxyPort: Int

    private let lock = NSLock()
    private var redirects: [Int: [URL]] = [:]

    init(proxyUsername: String = "", proxyPassword: String = "", proxyHost: String = "", proxyPort: Int = 0) {
        self.proxyUsername = proxyUsername
        self.proxyPassword = proxyPassword
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
    }

    func recordRedirect(taskIdentifier: Int, location: URL?) {
        guard let location else { return }
        lock.lock()
        redirects[taskIdentifier, default: []].append(location)
        lock.unlock()
    }

    func takeRedirects(taskIdentifier: Int) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return redirects.removeValue(forKey: taskIdentifier) ?? []
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        recordRedirect(taskIdentifier: task.taskIdentifier, location: request.url)
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        let isProxyChallenge = !proxyHost.isEmpty
            && space.host == proxyHost
            && (proxyPort == 0 || space.port == proxyPort)

        if isProxyChallenge,
           !proxyUsername.isEmpty,
           !proxyPassword.isEmpty,
           challenge.previousFailureCount == 0 {
            completionHandler(.useCredential, URLCredential(
                user: proxyUsername,
                password: proxyPassword,
                persistence: .forSession
            ))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

final class SessionFactory {
    static let shared = SessionFactory()

    enum Kind {
        case site
        case image
        case download
        case generic
    }

    private let lock = NSLock()
    private var sessions: [Kind: URLSession] = [:]
    private var generation = -1
    private var delegates: [Kind: SessionDelegate] = [:]

    private init() {}

    func session(for kind: Kind) -> URLSession {
        lock.lock()
        defer { lock.unlock() }

        let currentGeneration = ProxyService.shared.generation
        if generation != currentGeneration {
            sessions.removeAll()
            delegates.removeAll()
            generation = currentGeneration
        }

        if let existing = sessions[kind] {
            return existing
        }

        let proxy = ProxyService.shared
        let delegate = SessionDelegate(
            proxyUsername: proxy.isActive ? proxy.proxyUsername : "",
            proxyPassword: proxy.isActive ? proxy.proxyPassword : "",
            proxyHost: proxy.isActive ? proxy.proxyHost : "",
            proxyPort: proxy.isActive ? proxy.proxyPort : 0
        )
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        if let proxyDict = proxy.makeProxyDictionary() {
            configuration.connectionProxyDictionary = proxyDict
        }

        switch kind {
        case .site:
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 300
            configuration.httpAdditionalHeaders = ["User-Agent": HTTPDefaults.userAgent]
        case .image:
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 300
            configuration.httpAdditionalHeaders = [
                "User-Agent": HTTPDefaults.userAgent,
                "Accept": "image/webp,image/apng,image/*,*/*;q=0.8",
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                "Cache-Control": "no-cache",
                "Pragma": "no-cache",
            ]
        case .download:
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 3600
            configuration.httpAdditionalHeaders = ["User-Agent": HTTPDefaults.userAgent]
        case .generic:
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 300
        }

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        sessions[kind] = session
        delegates[kind] = delegate
        return session
    }

    func delegate(for kind: Kind) -> SessionDelegate? {
        lock.lock()
        defer { lock.unlock() }
        return delegates[kind]
    }
}

enum HTTPDefaults {
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/143.0.0.0 Safari/537.36"
}

final class HttpClient {
    static let authExpiredMessage = "Cookie已过期，请重新登录更新Cookie"

    let baseURL: String
    var userAgent: String
    var cookieProvider: () -> String? = { nil }
    let kind: SessionFactory.Kind

    init(baseURL: String, userAgent: String = HTTPDefaults.userAgent, kind: SessionFactory.Kind = .site) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.kind = kind
    }

    static func isLoginPath(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        let normalized = value.lowercased()
        return normalized.contains("/login")
            || normalized.contains("login.php")
            || normalized.contains("takelogin")
            || normalized.contains("/verify")
            || normalized.contains("verify.php")
    }

    func resolveURL(path: String, query: [String: String]) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        var resolved: URL?

        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            resolved = absolute
        } else if trimmed.hasPrefix("//"), let base = URL(string: baseURL), let scheme = base.scheme {
            resolved = URL(string: "\(scheme):\(trimmed)")
        } else {
            resolved = URL(string: trimmed, relativeTo: URL(string: baseURL))?.absoluteURL
        }

        guard var url = resolved else { return nil }
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
            var items = components.queryItems ?? []
            for (key, value) in query {
                items.append(URLQueryItem(name: key, value: value))
            }
            components.queryItems = items
            url = components.url ?? url
        }
        return url
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = resolveURL(path: request.urlString, query: request.query) else {
            throw SiteServiceException(message: "无效的请求地址", detail: request.urlString)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let cookie = cookieProvider(), !cookie.isEmpty {
            urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        if let body = request.body {
            switch body {
            case .form(let params):
                var components = URLComponents()
                components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
                let encoded = components.percentEncodedQuery ?? ""
                urlRequest.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = Data(encoded.utf8)
            case .json(let value):
                let data = try JSONSerialization.data(withJSONObject: value)
                urlRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = data
            case .raw(let data, let contentType):
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = data
            }
        }

        let session = SessionFactory.shared.session(for: kind)
        let (data, response, taskIdentifier) = try await data(for: urlRequest, session: session)
        let redirects = SessionFactory.shared.delegate(for: kind)?.takeRedirects(taskIdentifier: taskIdentifier) ?? []

        guard let http = response as? HTTPURLResponse else {
            throw SiteServiceException(message: "响应格式异常", detail: response.mimeType)
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key.lowercased()] = value
            }
        }

        if Self.isAuthenticationRedirect(finalURL: http.url, redirects: redirects, statusCode: http.statusCode) {
            throw SiteAuthenticationException(statusCode: http.statusCode, message: Self.authExpiredMessage)
        }

        if !(200..<300).contains(http.statusCode) {
            let body = HTTPCharset.decode(data, contentType: headers["content-type"])
            throw ApiExceptionAdapter.classifyResponse(statusCode: http.statusCode, body: body, action: "请求")
        }

        return HTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            data: data,
            url: http.url ?? url,
            redirectLocations: redirects
        )
    }

    static func isAuthenticationRedirect(finalURL: URL?, redirects: [URL], statusCode: Int?) -> Bool {
        if statusCode == 401 || statusCode == 403 {
            return true
        }
        if isLoginPath(finalURL?.absoluteString) {
            return true
        }
        return redirects.contains { isLoginPath($0.absoluteString) }
    }

    private func data(for urlRequest: URLRequest, session: URLSession) async throws -> (Data, URLResponse, Int) {
        final class TaskBox {
            var task: URLSessionDataTask?
        }
        final class IdentifierBox {
            var value: Int = -1
        }
        let box = TaskBox()
        let identifierBox = IdentifierBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let response else {
                        continuation.resume(throwing: SiteServiceException(message: "响应为空"))
                        return
                    }
                    continuation.resume(returning: (data ?? Data(), response, identifierBox.value))
                }
                identifierBox.value = task.taskIdentifier
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }
}

enum TimeoutRetry {
    static let defaultRetryCount = 1
    static let defaultRetryDelay: Duration = .milliseconds(300)

    static func isTimeoutError(_ error: Error) -> Bool {
        if let siteError = error as? SiteNetworkException {
            return siteError.isTimeout
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorTimedOut
        }
        return false
    }

    static func retryOnTimeout<T: Sendable>(
        retryCount: Int = defaultRetryCount,
        retryDelay: Duration = defaultRetryDelay,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var retries = 0
        while true {
            do {
                return try await operation()
            } catch {
                if !isTimeoutError(error) || retries >= retryCount {
                    throw error
                }
                retries += 1
                if retryDelay > .zero {
                    try await Task.sleep(for: retryDelay)
                }
            }
        }
    }
}
