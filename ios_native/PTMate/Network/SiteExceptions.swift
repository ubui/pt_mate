import Foundation

class SiteException: Error {
    let message: String
    let detail: String?

    init(_ message: String, _ detail: String? = nil) {
        self.message = message
        self.detail = detail
    }

    var descriptionText: String {
        if let detail, !detail.isEmpty {
            return "\(message)\n\(detail)"
        }
        return message
    }
}

final class CloudflareChallengeException: SiteException {
    init(_ detail: String? = nil) {
        super.init("检测到 Cloudflare 验证，请在浏览器中完成验证后重试", detail)
    }
}

final class SiteAuthenticationException: SiteException {
    let statusCode: Int?

    init(statusCode: Int? = nil, message: String = "登录已失效，请重新配置站点认证信息", detail: String? = nil) {
        self.statusCode = statusCode
        super.init(message, detail)
    }

    override var descriptionText: String {
        let codeInfo = statusCode != nil ? " (HTTP \(statusCode!))" : ""
        if let detail, !detail.isEmpty {
            return "\(message)\(codeInfo)\n\(detail)"
        }
        return "\(message)\(codeInfo)"
    }
}

final class SiteNetworkException: SiteException {
    let timeoutType: String

    init(timeoutType: String, detail: String? = nil) {
        self.timeoutType = timeoutType
        super.init("网络请求超时: \(timeoutType)", detail)
    }

    var isTimeout: Bool {
        ["连接超时", "发送超时", "接收超时"].contains(timeoutType)
    }
}

final class SiteServiceException: SiteException {
    let statusCode: Int?

    init(statusCode: Int? = nil, message: String = "服务端响应异常", detail: String? = nil) {
        self.statusCode = statusCode
        super.init(message, detail)
    }

    override var descriptionText: String {
        let codeInfo = statusCode != nil ? " (HTTP \(statusCode!))" : ""
        if let detail, !detail.isEmpty {
            return "\(message)\(codeInfo)\n\(detail)"
        }
        return "\(message)\(codeInfo)"
    }
}

final class SiteApiException: SiteException {
    let responseData: Any?

    init(message: String, responseData: Any? = nil) {
        self.responseData = responseData
        super.init(message, responseData.map { String(describing: $0) })
    }

    override var descriptionText: String {
        if let responseData {
            return "\(message)\n\(String(describing: responseData))"
        }
        return message
    }
}

enum ApiExceptionAdapter {
    private static let maxDetailLength = 200

    private static let cfKeywords = [
        "cloudflare",
        "cf-ray",
        "challenge-form",
        "cf_chl_opt",
        "ray id:",
        "checking your browser",
    ]

    static func wrapError(_ error: Error, action actionName: String) -> SiteException {
        if let siteError = error as? SiteException {
            return siteError
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return SiteNetworkException(timeoutType: "连接超时")
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
                 NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet:
                return SiteNetworkException(timeoutType: "连接失败", detail: nsError.localizedDescription)
            default:
                break
            }
        }

        return SiteServiceException(
            message: "\(actionName)失败",
            detail: truncateDetail(nsError.localizedDescription)
        )
    }

    static func classifyResponse(statusCode: Int, body: String?, action actionName: String) -> SiteException {
        if isCloudflareChallenge(body) {
            return CloudflareChallengeException()
        }
        if statusCode == 401 || statusCode == 403 || statusCode == 302 {
            return SiteAuthenticationException(statusCode: statusCode, detail: truncateDetail(body))
        }
        if statusCode >= 500 {
            return SiteServiceException(
                statusCode: statusCode,
                message: "\(actionName)时服务端异常",
                detail: truncateDetail(body)
            )
        }
        return SiteServiceException(
            statusCode: statusCode,
            message: "\(actionName)失败",
            detail: truncateDetail(body)
        )
    }

    static func isCloudflareChallenge(_ body: String?) -> Bool {
        guard let body, !body.isEmpty else { return false }
        let lowerBody = body.lowercased()
        return cfKeywords.contains { lowerBody.contains($0) }
    }

    static func truncateDetail(_ content: String?) -> String? {
        guard let content, !content.isEmpty else { return nil }
        if content.count <= maxDetailLength { return content }
        let index = content.index(content.startIndex, offsetBy: maxDetailLength)
        return String(content[..<index]) + "..."
    }
}
