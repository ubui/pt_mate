import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol TorrentFileDownloading {
    func downloadTorrentFileCommon(_ url: String, siteConfig: SiteConfig?) async throws -> Data
}

extension TorrentFileDownloading {
    func downloadTorrentFileCommon(_ url: String, siteConfig: SiteConfig?) async throws -> Data {
        let requestUrl = url.hasPrefix("##") ? String(url.dropFirst(2)) : url

        var mutableHeaders: [String: String] = [:]
        if shouldAttachTorrentSiteCookie(requestUrl, siteConfig: siteConfig),
           let cookie = siteConfig?.cookie {
            mutableHeaders["Cookie"] = cookie
        }
        let requestHeaders = mutableHeaders

        let response: TorrentFileResponse
        do {
            response = try await TimeoutRetry.retryOnTimeout {
                try await fetchTorrentFileResponse(requestUrl, headers: requestHeaders)
            }
        } catch {
            throw SiteServiceException(
                message: "Failed to download torrent file: \(torrentFileErrorText(error))"
            )
        }

        if response.statusCode >= 400 {
            if response.statusCode == 401 {
                throw SiteServiceException(
                    message: "Authentication failed when downloading torrent file"
                )
            }
            throw SiteServiceException(
                message: "HTTP \(response.statusCode) when downloading torrent file"
            )
        }

        let finalUrl = response.url.absoluteString
        if finalUrl.contains("login") || finalUrl.contains("verify") {
            throw SiteServiceException(
                message: "Failed to download torrent file: Exception: 下载请求被重定向到登录页，请检查 Cookie"
            )
        }

        if response.data.isEmpty {
            throw SiteServiceException(
                message: "Failed to download torrent file: Exception: Failed to download torrent file: empty response"
            )
        }

        return response.data
    }

    func shouldAttachTorrentSiteCookie(_ url: String, siteConfig: SiteConfig?) -> Bool {
        guard let siteConfig,
              siteConfig.siteType.usesCookieAuthentication,
              let cookie = siteConfig.cookie,
              !cookie.isEmpty
        else {
            return false
        }

        guard let requestUri = URL(string: url),
              let siteUri = URL(string: siteConfig.baseUrl)
        else {
            return false
        }

        let requestHost = requestUri.host ?? ""
        let siteHost = siteUri.host ?? ""
        return requestHost.isEmpty || requestHost == siteHost
    }
}

private struct TorrentFileResponse {
    let statusCode: Int
    let url: URL
    let data: Data
}

private func fetchTorrentFileResponse(
    _ url: String,
    headers: [String: String]
) async throws -> TorrentFileResponse {
    guard let requestURL = URL(string: url) else {
        throw SiteServiceException(message: "无效的请求地址", detail: url)
    }

    var request = URLRequest(url: requestURL)
    request.httpMethod = HTTPMethod.get.rawValue
    request.setValue(HTTPDefaults.userAgent, forHTTPHeaderField: "User-Agent")
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }

    let session = SessionFactory.shared.session(for: .download)
    let (data, response) = try await session.data(for: request)

    guard let http = response as? HTTPURLResponse else {
        throw SiteServiceException(message: "响应格式异常", detail: response.mimeType)
    }

    return TorrentFileResponse(
        statusCode: http.statusCode,
        url: http.url ?? requestURL,
        data: data
    )
}

private func torrentFileErrorText(_ error: Error) -> String {
    if let siteError = error as? SiteException {
        return siteError.descriptionText
    }
    if let urlError = error as? URLError {
        return urlError.localizedDescription
    }
    return (error as NSError).localizedDescription
}