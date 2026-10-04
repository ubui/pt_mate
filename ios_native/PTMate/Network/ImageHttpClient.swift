import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif

actor ImageHttpClient {
    static let instance = ImageHttpClient()

    private static let maxCacheSize = 500
    private static let maxCacheSizeBytes = 100 * 1024 * 1024

    private var imageCache: [String: Data] = [:]
    private var accessOrder: [String] = []
    private var pendingRequests: [String: Task<Data, Error>] = [:]

    private init() {}

    func fetchImage(
        _ url: String,
        siteBaseUrl: String? = nil,
        siteCookie: String? = nil
    ) async throws -> Data {
        let cacheKey = buildCacheKey(url, siteBaseUrl: siteBaseUrl, siteCookie: siteCookie)
        if let cached = imageCache[cacheKey] {
            updateAccessOrder(cacheKey)
            return cached
        }
        if let pending = pendingRequests[cacheKey] {
            return try await pending.value
        }
        let task = Task<Data, Error> {
            try await self.fetchImageFromNetwork(url, siteBaseUrl: siteBaseUrl, siteCookie: siteCookie)
        }
        pendingRequests[cacheKey] = task

        do {
            let data = try await task.value
            if data.count > 0 {
                addToCache(cacheKey, data)
            }
            pendingRequests.removeValue(forKey: cacheKey)
            return data
        } catch {
            pendingRequests.removeValue(forKey: cacheKey)
            throw error
        }
    }

    private func fetchImageFromNetwork(
        _ url: String,
        siteBaseUrl: String?,
        siteCookie: String?
    ) async throws -> Data {
        let shouldAttachCookie = shouldAttachSiteCookie(url, siteBaseUrl: siteBaseUrl)

        var referer: String?
        if let siteBaseUrl, !siteBaseUrl.trimmingCharacters(in: .whitespaces).isEmpty {
            referer = normalizeBaseUrl(siteBaseUrl)
        } else if url.contains("doubanio.com") {
            referer = "https://www.douban.com/"
        } else if url.contains("m-team.cc") {
            referer = "https://kp.m-team.cc/"
        } else if let urlComponents = URL(string: url), let host = urlComponents.host, let scheme = urlComponents.scheme {
            referer = "\(scheme)://\(host)/"
        }

        guard let requestURL = URL(string: url) else {
            throw SiteServiceException(message: "无效的图片地址", detail: url)
        }
        var request = URLRequest(url: requestURL)
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if shouldAttachCookie, let siteCookie, !siteCookie.trimmingCharacters(in: .whitespaces).isEmpty {
            request.setValue(siteCookie, forHTTPHeaderField: "Cookie")
        }

        let session = SessionFactory.shared.session(for: .image)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SiteServiceException(message: "图片响应格式异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ApiExceptionAdapter.classifyResponse(statusCode: http.statusCode, body: nil, action: "加载图片")
        }
        return data
    }

    private func buildCacheKey(_ url: String, siteBaseUrl: String?, siteCookie: String?) -> String {
        let shouldAttachCookie = shouldAttachSiteCookie(url, siteBaseUrl: siteBaseUrl)
        let normalizedBaseUrl = normalizeBaseUrl(siteBaseUrl)
        let cookieFingerprint = (shouldAttachCookie && !(siteCookie ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            ? (siteCookie ?? "").hashValue
            : 0
        return "\(url)|\(normalizedBaseUrl)|\(cookieFingerprint)"
    }

    private func normalizeBaseUrl(_ baseUrl: String?) -> String {
        let normalized = (baseUrl ?? "").trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty {
            return ""
        }
        return normalized.hasSuffix("/") ? normalized : "\(normalized)/"
    }

    private func shouldAttachSiteCookie(_ url: String, siteBaseUrl: String?) -> Bool {
        let normalizedBaseUrl = normalizeBaseUrl(siteBaseUrl)
        if normalizedBaseUrl.isEmpty {
            return false
        }

        guard
            let imageUri = URL(string: url),
            let siteUri = URL(string: normalizedBaseUrl),
            let imageHost = imageUri.host?.lowercased(),
            let siteHost = siteUri.host?.lowercased(),
            !imageHost.isEmpty,
            !siteHost.isEmpty
        else {
            return false
        }

        if imageHost == siteHost {
            return true
        }
        if imageHost.hasSuffix(".\(siteHost)") || siteHost.hasSuffix(".\(imageHost)") {
            return true
        }

        let imageRootDomain = rootDomain(imageHost)
        let siteRootDomain = rootDomain(siteHost)
        return !imageRootDomain.isEmpty && imageRootDomain == siteRootDomain
    }

    private func rootDomain(_ host: String) -> String {
        let segments = host.split(separator: ".")
        if segments.count < 2 {
            return host
        }
        return "\(segments[segments.count - 2]).\(segments.last ?? "")"
    }

    private func updateAccessOrder(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func addToCache(_ key: String, _ data: Data) {
        evictIfNeeded()
        imageCache[key] = data
        updateAccessOrder(key)
    }

    private func evictIfNeeded() {
        while imageCache.count >= Self.maxCacheSize {
            evictLeastRecentlyUsed()
        }
        while currentCacheSize() > Self.maxCacheSizeBytes {
            evictLeastRecentlyUsed()
        }
    }

    private func evictLeastRecentlyUsed() {
        guard !accessOrder.isEmpty else { return }
        let oldest = accessOrder.removeFirst()
        imageCache.removeValue(forKey: oldest)
    }

    private func currentCacheSize() -> Int {
        imageCache.values.reduce(0) { $0 + $1.count }
    }

    func clearCache() {
        imageCache.removeAll()
        accessOrder.removeAll()
    }

    func getCacheSize() -> Int {
        return imageCache.count
    }

    func getCacheSizeBytes() -> Int {
        return currentCacheSize()
    }

    func removeCacheForUrl(_ url: String) {
        let keys = imageCache.keys.filter { $0.hasPrefix("\(url)|") }
        for key in keys {
            imageCache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
}
