import Foundation

actor SiteConfigService {
    static let shared = SiteConfigService()

    private static let configPath = "assets/site_configs.json"
    private static let sitesManifestPath = "assets/sites_manifest.json"
    private static let sitesBasePath = "assets/sites"

    private var presetTemplatesCache: [SiteConfigTemplate]?
    private var urlToTemplateIdMappingCache: [String: String]?
    private var defaultTemplatesCache: [String: Any]?
    private var templateCache: [String: SiteConfigTemplate?] = [:]

    private init() {}

    static func getDefaultFeatures() -> SiteFeatures {
        .mteamDefault
    }

    func loadPresetSiteTemplates() async -> [SiteConfigTemplate] {
        if let cached = presetTemplatesCache {
            return cached
        }
        var templates: [SiteConfigTemplate] = []
        var urlMapping: [String: String] = [:]
        for filePath in await getPresetSiteFiles() {
            guard let data = await assetData(filePath),
                let siteJson = Self.parseDict(data)
            else { continue }
            let merged = await mergeSiteConfigWithTypeDefault(siteJson)
            guard let template = try? SiteConfigTemplate.fromJson(merged) else { continue }
            templates.append(template)
            for url in template.baseUrls {
                urlMapping[Self.normalizeUrl(url)] = template.id
            }
        }
        presetTemplatesCache = templates
        urlToTemplateIdMappingCache = urlMapping
        return templates
    }

    func loadPresetSites() async -> [SiteConfig] {
        var sites: [SiteConfig] = []
        for template in await loadPresetSiteTemplates() {
            if let config = try? template.toSiteConfig() {
                sites.append(config)
            }
        }
        return sites
    }

    func getTemplateById(_ templateId: String, siteType: SiteType) async -> SiteConfigTemplate? {
        let cacheKey = "\(templateId)|\(siteType.id)"
        if templateCache.keys.contains(cacheKey) {
            return templateCache[cacheKey]!
        }
        var result: SiteConfigTemplate?
        if !templateId.isEmpty, templateId != "-1" {
            let templates = await loadPresetSiteTemplates()
            result = templates.first { $0.id == templateId }
        }
        if result == nil {
            if let defaultTemplate = await getDefaultTemplateConfig(siteType) {
                result = Self.convertDefaultTemplate(
                    templateId,
                    defaultTemplate,
                    siteType
                )
            }
        }
        templateCache.updateValue(result, forKey: cacheKey)
        return result
    }

    func getDiscountMapping(_ baseUrl: String) async -> [String: String] {
        let normalizedBaseUrl = Self.normalizeUrl(baseUrl)
        for template in await loadPresetSiteTemplates() {
            if template.baseUrls.contains(where: { Self.normalizeUrl($0) == normalizedBaseUrl }) {
                return template.discountMapping
            }
        }
        return [:]
    }

    func getDefaultSearchCategories(_ baseUrl: String) async -> [SearchCategoryConfig] {
        let normalizedBaseUrl = Self.normalizeUrl(baseUrl)
        for template in await loadPresetSiteTemplates() {
            if template.baseUrls.contains(where: { Self.normalizeUrl($0) == normalizedBaseUrl }) {
                return template.searchCategories
            }
        }
        return []
    }

    func getUrlToTemplateIdMapping() async -> [String: String] {
        if urlToTemplateIdMappingCache == nil {
            _ = await loadPresetSiteTemplates()
        }
        return urlToTemplateIdMappingCache ?? [:]
    }

    func clearAllCache() {
        presetTemplatesCache = nil
        urlToTemplateIdMappingCache = nil
        defaultTemplatesCache = nil
        templateCache.removeAll()
    }

    func clearTemplateCache() {
        clearAllCache()
    }

    private func getPresetSiteFiles() async -> [String] {
        guard let data = await assetData(Self.sitesManifestPath),
            let manifest = Self.parseDict(data),
            let sites = manifest["sites"] as? [String]
        else { return [] }
        return sites.map { "\(Self.sitesBasePath)/\($0)" }
    }

    private func mergeSiteConfigWithTypeDefault(_ siteJson: [String: Any]) async -> [String: Any] {
        let siteType = Self.parseSiteType(siteJson["siteType"] as? String)
        guard let defaultTemplate = await getDefaultTemplateConfig(siteType) else {
            return siteJson
        }
        return Self.mergeMissingKeys(target: siteJson, defaults: defaultTemplate)
    }

    private func getDefaultTemplateConfig(_ siteType: SiteType) async -> [String: Any]? {
        if defaultTemplatesCache == nil {
            guard let data = await assetData(Self.configPath),
                let json = Self.parseDict(data),
                let defaults = json["defaultTemplates"] as? [String: Any]
            else { return nil }
            defaultTemplatesCache = defaults
        }
        guard let cache = defaultTemplatesCache,
            let template = cache[siteType.id] as? [String: Any]
        else { return nil }
        return template
    }

    private func assetData(_ relativePath: String) async -> Data? {
        let url = Bundle.main.bundleURL.appendingPathComponent(relativePath)
        return await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
    }

    private static func parseDict(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func parseSiteType(_ id: String?) -> SiteType {
        guard let id else { return .mteam }
        return SiteType.allCases.first { $0.id == id } ?? .mteam
    }

    private static func normalizeUrl(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    private static func presentValue(_ dict: [String: Any], _ key: String) -> Any? {
        guard let value = dict[key], !(value is NSNull) else { return nil }
        return value
    }

    private static func mergeMissingKeys(
        target: [String: Any],
        defaults: [String: Any],
        deepMergeMaps: Bool = false
    ) -> [String: Any] {
        var merged = target
        for (key, defaultValue) in defaults {
            if merged[key] == nil {
                merged[key] = cloneValue(defaultValue)
                continue
            }
            if let existingDict = merged[key] as? [String: Any],
                let defaultDict = defaultValue as? [String: Any],
                deepMergeMaps || key == "features" || key == "discountMapping"
                    || key == "tagMapping"
            {
                merged[key] = mergeMissingKeys(
                    target: existingDict,
                    defaults: defaultDict,
                    deepMergeMaps: true
                )
            }
        }
        return merged
    }

    private static func cloneValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in dict {
                out[key] = cloneValue(item)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { cloneValue($0) }
        }
        return value
    }

    private static func convertDefaultTemplate(
        _ templateId: String,
        _ defaultTemplate: [String: Any],
        _ siteType: SiteType
    ) -> SiteConfigTemplate? {
        var categories: [SearchCategoryConfig] = []
        if let categoriesValue = presentValue(defaultTemplate, "searchCategories") {
            guard let list = categoriesValue as? [[String: Any]] else { return nil }
            for item in list {
                guard let category = try? SearchCategoryConfig.fromJson(item) else { return nil }
                categories.append(category)
            }
        }

        var features = SiteFeatures.mteamDefault
        if let featuresValue = presentValue(defaultTemplate, "features") {
            guard let dict = featuresValue as? [String: Any],
                let parsed = try? SiteFeatures.fromJson(dict)
            else { return nil }
            features = parsed
        }

        var discountMapping: [String: String] = [:]
        if let value = presentValue(defaultTemplate, "discountMapping") {
            guard let dict = value as? [String: String] else { return nil }
            discountMapping = dict
        }

        var tagMapping: [String: String] = [:]
        if let value = presentValue(defaultTemplate, "tagMapping") {
            guard let dict = value as? [String: String] else { return nil }
            tagMapping = dict
        }

        var infoFinder: [String: Any]?
        if let value = presentValue(defaultTemplate, "infoFinder") {
            guard let dict = value as? [String: Any] else { return nil }
            infoFinder = dict
        }

        var request: [String: Any]?
        if let value = presentValue(defaultTemplate, "request") {
            guard let dict = value as? [String: Any] else { return nil }
            request = dict
        }

        return SiteConfigTemplate(
            id: templateId,
            name: (defaultTemplate["name"] as? String) ?? templateId,
            baseUrls: [(defaultTemplate["baseUrl"] as? String) ?? "https://"],
            siteType: siteType,
            searchCategories: categories,
            features: features,
            discountMapping: discountMapping,
            tagMapping: tagMapping,
            infoFinder: infoFinder,
            request: request,
            operationIntervalMs: (defaultTemplate["operationIntervalMs"] as? Int) ?? 500
        )
    }
}
