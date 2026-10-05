import Foundation
import CoreFoundation

struct CookieCloudRemoteData {
    let cookiesByHost: [String: String]

    init(cookiesByHost: [String: String]) {
        self.cookiesByHost = cookiesByHost
    }
}

enum CookieCloudCandidateType {
    case updateExisting
    case addPreset
    case unknown
}

struct CookieCloudCandidate {
    var type: CookieCloudCandidateType
    var host: String
    var cookie: String
    var site: SiteConfig?
    var template: SiteConfigTemplate?

    init(
        type: CookieCloudCandidateType,
        host: String,
        cookie: String,
        site: SiteConfig? = nil,
        template: SiteConfigTemplate? = nil
    ) {
        self.type = type
        self.host = host
        self.cookie = cookie
        self.site = site
        self.template = template
    }

    var title: String {
        site?.name ?? template?.name ?? host
    }
}

struct CookieCloudSyncPlan {
    var updates: [CookieCloudCandidate]
    var additions: [CookieCloudCandidate]
    var unknown: [CookieCloudCandidate]

    init(
        updates: [CookieCloudCandidate],
        additions: [CookieCloudCandidate],
        unknown: [CookieCloudCandidate]
    ) {
        self.updates = updates
        self.additions = additions
        self.unknown = unknown
    }

    var hasChanges: Bool {
        !updates.isEmpty || !additions.isEmpty
    }

    var totalCandidates: Int {
        updates.count + additions.count + unknown.count
    }
}

struct CookieCloudApplyResult {
    var updatedCount: Int
    var addedCount: Int

    init(updatedCount: Int, addedCount: Int) {
        self.updatedCount = updatedCount
        self.addedCount = addedCount
    }
}

private struct CookieDomainSource {
    let domain: String
    let cookie: String
    let priority: Int
}

final class CookieCloudService {
    static let requestTimeout: TimeInterval = 15

    private let storage: StorageService

    init(storage: StorageService = .shared) {
        self.storage = storage
    }

    func fetchSyncPlan(config: CookieCloudConfig? = nil) async throws -> CookieCloudSyncPlan {
        let effectiveConfig: CookieCloudConfig
        if let config {
            effectiveConfig = config
        } else {
            effectiveConfig = try await storage.loadCookieCloudConfig()
        }
        let remote = try await fetchRemoteData(effectiveConfig)
        return try await buildSyncPlan(remote.cookiesByHost)
    }

    func fetchRemoteData(_ config: CookieCloudConfig) async throws -> CookieCloudRemoteData {
        guard config.isConfigured else {
            throw ModelsError.argumentException("Cookie Cloud 配置不完整")
        }

        let baseUrl = Self.stripTrailingSlashes(
            config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let client = HttpClient(baseURL: baseUrl, kind: .generic)
        let encodedUuid = Self.uriEncodeComponent(
            config.uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let request = HTTPRequest(
            "\(baseUrl)/get/\(encodedUuid)",
            method: .post,
            body: .json(["password": config.password])
        )
        let response = try await client.perform(request)
        let decoded = try response.bodyJSON()
        guard let body = decoded as? [String: Any] else {
            throw ModelsError.formatException("Cookie Cloud 响应格式无效")
        }

        guard let encryptedText = Self.extractEncryptedText(body), !encryptedText.isEmpty else {
            return CookieCloudRemoteData(
                cookiesByHost: Self.extractCookiesByHost(body)
            )
        }

        let plainText = try Self.decryptPayload(
            encryptedText,
            uuid: config.uuid,
            password: config.password
        )
        guard let plainData = plainText.data(using: .utf8),
            let plainObject = try? JSONSerialization.jsonObject(with: plainData),
            let plainMap = plainObject as? [String: Any]
        else {
            throw ModelsError.formatException("Cookie Cloud 明文格式无效")
        }
        return CookieCloudRemoteData(cookiesByHost: Self.extractCookiesByHost(plainMap))
    }

    static func decryptPayload(
        _ encryptedText: String,
        uuid: String,
        password: String
    ) throws -> String {
        let keySeedDigest = CookieCloudDigest.md5(Array("\(uuid)-\(password)".utf8))
        let keySeed = CookieCloudDigest.hex(Array(keySeedDigest.prefix(16)))
        guard let encryptedData = Data(base64Encoded: encryptedText) else {
            throw CookieCloudCryptoError.invalidBase64Payload
        }
        let encryptedBytes = [UInt8](encryptedData)
        let saltPrefix = Array("Salted__".utf8)

        if encryptedBytes.count > 16,
            Array(encryptedBytes[0..<8]) == saltPrefix {
            let salt = Array(encryptedBytes[8..<16])
            let cipherText = Array(encryptedBytes[16...])
            let keyIv = deriveOpenSslKeyIv(
                Array(keySeed.utf8),
                salt,
                keyLength: 32,
                ivLength: 16
            )
            if let plainText = try? decryptText(
                key: Array(keyIv[0..<32]),
                iv: Array(keyIv[32..<48]),
                data: cipherText
            ) {
                return plainText
            }
        }

        let fixedKey = CookieCloudDigest.md5(Array(keySeed.utf8))
        return try decryptText(
            key: fixedKey,
            iv: [UInt8](repeating: 0, count: 16),
            data: encryptedBytes
        )
    }

    static func deriveOpenSslKeyIv(
        _ password: [UInt8],
        _ salt: [UInt8],
        keyLength: Int,
        ivLength: Int
    ) -> [UInt8] {
        let targetLength = keyLength + ivLength
        var bytes: [UInt8] = []
        bytes.reserveCapacity(targetLength)
        var previous: [UInt8] = []
        while bytes.count < targetLength {
            var input = previous
            input.append(contentsOf: password)
            input.append(contentsOf: salt)
            let digest = CookieCloudDigest.md5(input)
            bytes.append(contentsOf: digest)
            previous = digest
        }
        return Array(bytes.prefix(targetLength))
    }

    private static func decryptText(key: [UInt8], iv: [UInt8], data: [UInt8]) throws -> String {
        let plainBytes = try CookieCloudAESCBC.decrypt(key: key, iv: iv, data: data)
        guard let text = String(data: Data(plainBytes), encoding: .utf8) else {
            throw CookieCloudCryptoError.invalidPlainTextEncoding
        }
        return text
    }

    private static func stripTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result = String(result.dropLast())
        }
        return result
    }

    private static let unreservedURICharacters: Set<UInt8> = {
        var set = Set<UInt8>()
        for byte in UInt8(0)...UInt8(127) {
            let isAlphaNumeric =
                (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) ||
                (byte >= 97 && byte <= 122)
            if isAlphaNumeric {
                set.insert(byte)
            } else if "-_.!~*'()".utf8.contains(byte) {
                set.insert(byte)
            }
        }
        return set
    }()

    static func uriEncodeComponent(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for byte in Array(value.utf8) {
            if unreservedURICharacters.contains(byte) {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    private static func extractEncryptedText(_ body: [String: Any]) -> String? {
        let keys = ["encrypted", "encrypted_data", "cookie_data", "data", "payload"]
        for key in keys {
            if let value = body[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        if let nested = body["data"] as? [String: Any] {
            return extractEncryptedText(nested)
        }
        return nil
    }

    static func extractCookiesByHost(_ json: [String: Any]) -> [String: String] {
        let candidates: [Any?] = [json["cookie_data"], json["cookies"], json["data"], json]
        var result: [String: String] = [:]
        for candidate in candidates {
            collectCookies(candidate, &result)
            if !result.isEmpty {
                break
            }
        }
        return result
    }

    private static func collectCookies(_ source: Any?, _ output: inout [String: String]) {
        if let map = source as? [String: Any] {
            for (key, value) in map {
                let host = normalizeCookieDomain(key)
                let cookie = cookieValueToString(value)
                if let host, let cookie, !cookie.isEmpty {
                    output[host] = cookie
                } else {
                    collectCookies(value, &output)
                }
            }
        } else if let list = source as? [Any] {
            for item in list {
                collectCookies(item, &output)
            }
        }
    }

    private static func cookieValueToString(_ value: Any?) -> String? {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let list = value as? [Any] {
            var parts: [String] = []
            for item in list {
                if let text = item as? String {
                    if text.contains("=") {
                        let head = text.split(
                            separator: ";",
                            maxSplits: 1,
                            omittingEmptySubsequences: false
                        ).first ?? ""
                        parts.append(
                            head.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                } else if let map = item as? [String: Any] {
                    let name = unwrapJSONNull(map["name"]).map(dartValueToString)
                    let cookieValue = unwrapJSONNull(map["value"]).map(dartValueToString)
                    if let name, let cookieValue {
                        parts.append("\(name)=\(cookieValue)")
                    }
                }
            }
            return parts.joined(separator: "; ")
        }
        if let map = value as? [String: Any] {
            let cookieString =
                unwrapJSONNull(map["cookieString"]) ?? unwrapJSONNull(map["cookie"])
            if let text = cookieString as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func unwrapJSONNull(_ value: Any?) -> Any? {
        if let value, CFGetTypeID(value as CFTypeRef) == CFNullGetTypeID() {
            return nil
        }
        return value
    }

    private static func dartValueToString(_ value: Any) -> String {
        if let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        return String(describing: value)
    }

    func buildSyncPlan(_ cookiesByHost: [String: String]) async throws -> CookieCloudSyncPlan {
        let localSites: [SiteConfig] = try await storage.loadSiteConfigs(
            includeApiKeys: false
        )
        let templates = await SiteConfigService.shared.loadPresetSiteTemplates()
        var updates: [CookieCloudCandidate] = []
        var additions: [CookieCloudCandidate] = []
        var unknown: [CookieCloudCandidate] = []
        var matchedTemplateIds = Set<String>()

        for site in localSites {
            if !Self.shouldSyncCookie(site.siteType) {
                continue
            }
            guard let targetHost = Self.normalizeUrlHost(site.baseUrl) else {
                continue
            }
            guard
                let cookie = Self.buildCookieHeaderForTarget(
                    targetHost,
                    cookiesByHost: cookiesByHost
                )
            else {
                continue
            }
            if !site.templateId.isEmpty {
                matchedTemplateIds.insert(site.templateId)
            }
            if (site.cookie ?? "") == cookie {
                continue
            }
            updates.append(
                CookieCloudCandidate(
                    type: .updateExisting,
                    host: targetHost,
                    cookie: cookie,
                    site: site
                )
            )
        }

        for template in templates {
            if !Self.shouldSyncCookie(template.siteType) ||
                matchedTemplateIds.contains(template.id) ||
                Self.hasLocalSiteForTemplate(template, localSites: localSites)
            {
                continue
            }
            guard
                let selectedUrl = Self.bestTemplateUrlForCookies(
                    template,
                    cookiesByHost: cookiesByHost
                )
            else {
                continue
            }
            guard let targetHost = Self.normalizeUrlHost(selectedUrl) else {
                continue
            }
            guard
                let cookie = Self.buildCookieHeaderForTarget(
                    targetHost,
                    cookiesByHost: cookiesByHost
                )
            else {
                continue
            }
            matchedTemplateIds.insert(template.id)
            additions.append(
                CookieCloudCandidate(
                    type: .addPreset,
                    host: targetHost,
                    cookie: cookie,
                    template: template
                )
            )
        }

        var unknownDomains = Set<String>()
        for entry in cookiesByHost {
            guard let domain = Self.normalizeCookieDomain(entry.key) else {
                continue
            }
            if entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            if Self.isKnownCookieDomain(
                domain,
                localSites: localSites,
                templates: templates
            ) {
                continue
            }
            let canonicalDomain = Self.cookieDomainForComparison(domain)
            if unknownDomains.insert(canonicalDomain).inserted {
                unknown.append(
                    CookieCloudCandidate(
                        type: .unknown,
                        host: domain,
                        cookie: entry.value
                    )
                )
            }
        }

        return CookieCloudSyncPlan(
            updates: updates,
            additions: additions,
            unknown: unknown
        )
    }

    func checkSiteCookieUpdate(_ site: SiteConfig) async throws -> String? {
        if !Self.shouldSyncCookie(site.siteType) {
            return nil
        }
        let config = try await storage.loadCookieCloudConfig()
        if !config.isConfigured {
            return nil
        }
        let remote = try await fetchRemoteData(config)
        guard let siteHost = Self.normalizeUrlHost(site.baseUrl) else {
            return nil
        }
        guard
            let bestCookie = Self.buildCookieHeaderForTarget(
                siteHost,
                cookiesByHost: remote.cookiesByHost
            )
        else {
            return nil
        }
        if bestCookie == (site.cookie ?? "") {
            return nil
        }
        return bestCookie
    }

    func applyPlan(
        _ plan: CookieCloudSyncPlan,
        selectedUpdates: [CookieCloudCandidate],
        selectedAdditions: [CookieCloudCandidate]
    ) async throws -> CookieCloudApplyResult {
        let result: CookieCloudApplyResult = try await storage
            .updateSiteConfigsAtomically(
                includeApiKeys: false,
                resolveFallbackConflicts: false
            ) { before -> ([SiteConfig], CookieCloudApplyResult) in
                var next = before
                var updatedCount = 0
                var addedCount = 0

                for candidate in selectedUpdates {
                    guard let site = candidate.site else {
                        continue
                    }
                    if let index = next.firstIndex(where: { $0.id == site.id }) {
                        next[index] = next[index].copyWith(cookie: candidate.cookie)
                        updatedCount += 1
                    }
                }

                for candidate in selectedAdditions {
                    guard let template = candidate.template else {
                        continue
                    }
                    let selectedUrl = Self.bestTemplateUrl(candidate.host, template)
                    let id =
                        "\(template.id)-\(Self.currentMilliseconds())"
                        + "-\(Int.random(in: 0..<1000))"
                    let site = try template
                        .toSiteConfig(
                            selectedUrl: selectedUrl,
                            cookie: candidate.cookie
                        )
                        .copyWith(id: id)
                    next.append(site)
                    addedCount += 1
                }

                return (
                    next.map { $0.copyWith(apiKey: nil) },
                    CookieCloudApplyResult(
                        updatedCount: updatedCount,
                        addedCount: addedCount
                    )
                )
            }

        await storage.saveCookieCloudLastSync(
            syncedAt: Date(),
            summary:
                "更新 \(result.updatedCount) 个站点，新增 \(result.addedCount) 个站点"
        )
        return result
    }

    private static func currentMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    static func bestTemplateUrl(
        _ host: String,
        _ template: SiteConfigTemplate
    ) -> String? {
        for url in template.baseUrls {
            if let urlHost = normalizeUrlHost(url), hostsRelated(host, urlHost) {
                return url
            }
        }
        if let primaryUrl = template.primaryUrl {
            return primaryUrl
        }
        return template.baseUrls.first
    }

    static func shouldSyncCookie(_ siteType: SiteType) -> Bool {
        siteType.usesCookieAuthentication
    }

    static func hasLocalSiteForTemplate(
        _ template: SiteConfigTemplate,
        localSites: [SiteConfig]
    ) -> Bool {
        for site in localSites {
            if !site.templateId.isEmpty, site.templateId == template.id {
                return true
            }
            guard let siteHost = normalizeUrlHost(site.baseUrl) else {
                continue
            }
            for url in template.baseUrls {
                guard let templateHost = normalizeUrlHost(url) else {
                    continue
                }
                if hostsRelated(siteHost, templateHost) {
                    return true
                }
            }
        }
        return false
    }

    static func bestTemplateUrlForCookies(
        _ template: SiteConfigTemplate,
        cookiesByHost: [String: String]
    ) -> String? {
        var urls: [String] = []
        if let primaryUrl = template.primaryUrl {
            urls.append(primaryUrl)
        }
        for url in template.baseUrls where url != template.primaryUrl {
            urls.append(url)
        }
        for url in urls {
            guard let host = normalizeUrlHost(url) else {
                continue
            }
            if buildCookieHeaderForTarget(host, cookiesByHost: cookiesByHost) != nil {
                return url
            }
        }
        return nil
    }

    static func isKnownCookieDomain(
        _ cookieDomain: String,
        localSites: [SiteConfig],
        templates: [SiteConfigTemplate]
    ) -> Bool {
        for site in localSites {
            if let host = normalizeUrlHost(site.baseUrl),
                cookieDomainCoversHost(cookieDomain, host)
            {
                return true
            }
        }
        for template in templates {
            for url in template.baseUrls {
                if let host = normalizeUrlHost(url),
                    cookieDomainCoversHost(cookieDomain, host)
                {
                    return true
                }
            }
        }
        return false
    }

    static func buildCookieHeaderForTarget(
        _ targetHost: String,
        cookiesByHost: [String: String]
    ) -> String? {
        var sources: [CookieDomainSource] = []
        for entry in cookiesByHost {
            guard let domain = normalizeCookieDomain(entry.key) else {
                continue
            }
            if entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            if !cookieDomainCoversHost(domain, targetHost) {
                continue
            }
            sources.append(
                CookieDomainSource(
                    domain: domain,
                    cookie: entry.value,
                    priority: cookieDomainPriority(domain, targetHost)
                )
            )
        }
        if sources.isEmpty {
            return nil
        }
        sources.sort { $0.priority < $1.priority }

        var valuesByName: [String: String] = [:]
        for source in sources {
            for (name, value) in parseCookieHeader(source.cookie) {
                valuesByName[name] = value
            }
        }
        if valuesByName.isEmpty {
            guard let last = sources.last else {
                return nil
            }
            return last.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return valuesByName
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    static func parseCookieHeader(_ cookie: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in cookie.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            guard
                let equalsIndex = trimmed.firstIndex(of: "="),
                equalsIndex != trimmed.startIndex
            else {
                continue
            }
            let name = String(trimmed[trimmed.startIndex..<equalsIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                continue
            }
            result[name] = value
        }
        return result
    }

    static func cookieDomainPriority(_ cookieDomain: String, _ targetHost: String) -> Int {
        let comparable = cookieDomainForComparison(cookieDomain)
        let labelCount = comparable.split(separator: ".").count
        let exactBonus = comparable == targetHost ? 1000 : 0
        return exactBonus + labelCount
    }

    static func normalizeUrlHost(_ value: String) -> String? {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.isEmpty {
            return nil
        }
        if !raw.contains("://") {
            raw = "https://\(raw)"
        }
        let host = URLComponents(string: raw)?.host?.lowercased() ?? ""
        return normalizePlainHost(host)
    }

    static func normalizeCookieDomain(_ value: String) -> String? {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.isEmpty {
            return nil
        }
        if raw.contains("://") {
            guard let host = URLComponents(string: raw)?.host, !host.isEmpty else {
                return nil
            }
            raw = host.lowercased()
        } else {
            raw = String(raw.split(separator: "/").first ?? "")
        }
        let hasLeadingDot = raw.hasPrefix(".")
        guard let host = normalizePlainHost(raw) else {
            return nil
        }
        return hasLeadingDot && !host.hasPrefix(".") ? ".\(host)" : host
    }

    static func normalizePlainHost(_ value: String) -> String? {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasSuffix(".") {
            host = String(host.dropLast())
        }
        while host.hasPrefix("..") {
            host = String(host.dropFirst(2))
        }
        return host.isEmpty ? nil : host
    }

    static func cookieDomainForComparison(_ cookieDomain: String) -> String {
        var domain = cookieDomain.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while domain.hasPrefix(".") {
            domain = String(domain.dropFirst())
        }
        if domain.hasSuffix(".") {
            domain = String(domain.dropLast())
        }
        return domain
    }

    static func cookieDomainCoversHost(_ cookieDomain: String, _ host: String) -> Bool {
        let comparableDomain = cookieDomainForComparison(cookieDomain)
        if comparableDomain.isEmpty {
            return false
        }
        return host == comparableDomain || host.hasSuffix(".\(comparableDomain)")
    }

    static func hostsRelated(_ a: String, _ b: String) -> Bool {
        if a == b {
            return true
        }
        return a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
    }
}
