import Foundation

enum SiteType: String, CaseIterable {
    case mteam = "M-Team"
    case nexusphp = "NexusPHP"
    case nexusphpweb = "NexusPHPWeb"
    case web = "Web"
    case rousi = "RousiPro"
    case gazelle = "Gazelle"
    case unit3d = "Unit3D"

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .mteam:
            return "mteam"
        case .nexusphp:
            return "nexusphp"
        case .nexusphpweb:
            return "nexusphpweb"
        case .web:
            return "web"
        case .rousi:
            return "rousi"
        case .gazelle:
            return "gazelle"
        case .unit3d:
            return "unit3d"
        }
    }

    var displayName: String {
        switch self {
        case .mteam:
            return "M-Team"
        case .nexusphp:
            return "NexusPHP(api)"
        case .nexusphpweb:
            return "NexusPHP(web)"
        case .web:
            return "Web (Alpha)"
        case .rousi:
            return "Rousi pro"
        case .gazelle:
            return "Gazelle (Alpha)"
        case .unit3d:
            return "Unit3D (beta)"
        }
    }

    var apiKeyLabel: String {
        switch self {
        case .mteam:
            return "API Key (x-api-key)"
        case .nexusphp:
            return "API Key (访问令牌)"
        case .nexusphpweb, .web, .gazelle:
            return "Cookie认证"
        case .rousi:
            return "paaskey认证"
        case .unit3d:
            return "API Key"
        }
    }

    var apiKeyHint: String {
        switch self {
        case .mteam:
            return "从 控制台-实验室-存储令牌 获取并粘贴此处"
        case .nexusphp:
            return "控制面板-设定首页-访问令牌（权限都勾上）"
        case .nexusphpweb, .web, .gazelle:
            return "通过网页登录获取认证信息"
        case .rousi:
            return "可以在网站的「账户设置」页面查看和重置自己的 Passkey。"
        case .unit3d:
            return "安全设置 - API Token"
        }
    }

    var usesCookieAuthentication: Bool {
        self == .nexusphpweb || self == .web || self == .gazelle
    }

    var supportsGazelleDownloadToken: Bool {
        self == .gazelle
    }

    var isAvailableForCustomSite: Bool {
        self != .web
    }

    static func fromId(_ id: String?) -> SiteType {
        SiteType(rawValue: id ?? "M-Team") ?? .mteam
    }
}

struct SiteFeatures {
    var supportMemberProfile: Bool
    var supportTorrentSearch: Bool
    var supportTorrentBrowse: Bool
    var supportTorrentDetail: Bool
    var supportDownload: Bool
    var supportCollection: Bool
    var supportHistory: Bool
    var supportCategories: Bool
    var supportAdvancedSearch: Bool
    var showCover: Bool
    var supportCommentDetail: Bool
    var nativeDetail: Bool

    init(
        supportMemberProfile: Bool = true,
        supportTorrentSearch: Bool = true,
        supportTorrentBrowse: Bool = true,
        supportTorrentDetail: Bool = true,
        supportDownload: Bool = true,
        supportCollection: Bool = true,
        supportHistory: Bool = true,
        supportCategories: Bool = true,
        supportAdvancedSearch: Bool = true,
        showCover: Bool = true,
        supportCommentDetail: Bool = false,
        nativeDetail: Bool = false
    ) {
        self.supportMemberProfile = supportMemberProfile
        self.supportTorrentSearch = supportTorrentSearch
        self.supportTorrentBrowse = supportTorrentBrowse
        self.supportTorrentDetail = supportTorrentDetail
        self.supportDownload = supportDownload
        self.supportCollection = supportCollection
        self.supportHistory = supportHistory
        self.supportCategories = supportCategories
        self.supportAdvancedSearch = supportAdvancedSearch
        self.showCover = showCover
        self.supportCommentDetail = supportCommentDetail
        self.nativeDetail = nativeDetail
    }

    private enum CodingKeys: String, CodingKey {
        case supportMemberProfile
        case supportTorrentSearch
        case supportTorrentBrowse
        case supportTorrentDetail
        case supportDownload
        case supportCollection
        case supportHistory
        case supportCategories
        case supportAdvancedSearch
        case showCover
        case supportCommentDetail
        case nativeDetail
        case userProfile
        case torrentSearch
        case torrentBrowse
        case torrentDetail
        case download
        case favorites
        case downloadHistory
        case categorySearch
        case advancedSearch
        case commentDetail
    }

    static func fromJson(_ json: [String: Any]) throws -> SiteFeatures {
        SiteFeatures(
            supportMemberProfile: try json.coalesceBool(
                "userProfile",
                "supportMemberProfile",
                default: true
            ),
            supportTorrentSearch: try json.coalesceBool(
                "torrentSearch",
                "supportTorrentSearch",
                default: true
            ),
            supportTorrentBrowse: try json.coalesceBool(
                "torrentBrowse",
                "supportTorrentBrowse",
                default: true
            ),
            supportTorrentDetail: try json.coalesceBool(
                "torrentDetail",
                "supportTorrentDetail",
                default: true
            ),
            supportDownload: try json.coalesceBool(
                "download",
                "supportDownload",
                default: true
            ),
            supportCollection: try json.coalesceBool(
                "favorites",
                "supportCollection",
                default: true
            ),
            supportHistory: try json.coalesceBool(
                "downloadHistory",
                "supportHistory",
                default: true
            ),
            supportCategories: try json.coalesceBool(
                "categorySearch",
                "supportCategories",
                default: true
            ),
            supportAdvancedSearch: try json.coalesceBool(
                "advancedSearch",
                "supportAdvancedSearch",
                default: true
            ),
            showCover: try json.coalesceBool("showCover", default: true),
            supportCommentDetail: try json.coalesceBool(
                "commentDetail",
                "supportCommentDetail",
                default: false
            ),
            nativeDetail: try json.coalesceBool("nativeDetail", default: false)
        )
    }

    func toJson() -> [String: Any] {
        [
            "supportMemberProfile": supportMemberProfile,
            "supportTorrentSearch": supportTorrentSearch,
            "supportTorrentBrowse": supportTorrentBrowse,
            "supportTorrentDetail": supportTorrentDetail,
            "supportDownload": supportDownload,
            "supportCollection": supportCollection,
            "supportHistory": supportHistory,
            "supportCategories": supportCategories,
            "supportAdvancedSearch": supportAdvancedSearch,
            "showCover": showCover,
            "supportCommentDetail": supportCommentDetail,
            "nativeDetail": nativeDetail,
        ]
    }

    func copyWith(
        supportMemberProfile: Bool? = nil,
        supportTorrentSearch: Bool? = nil,
        supportTorrentBrowse: Bool? = nil,
        supportTorrentDetail: Bool? = nil,
        supportDownload: Bool? = nil,
        supportCollection: Bool? = nil,
        supportHistory: Bool? = nil,
        supportCategories: Bool? = nil,
        supportAdvancedSearch: Bool? = nil,
        showCover: Bool? = nil,
        supportCommentDetail: Bool? = nil,
        nativeDetail: Bool? = nil
    ) -> SiteFeatures {
        SiteFeatures(
            supportMemberProfile: supportMemberProfile ?? self.supportMemberProfile,
            supportTorrentSearch: supportTorrentSearch ?? self.supportTorrentSearch,
            supportTorrentBrowse: supportTorrentBrowse ?? self.supportTorrentBrowse,
            supportTorrentDetail: supportTorrentDetail ?? self.supportTorrentDetail,
            supportDownload: supportDownload ?? self.supportDownload,
            supportCollection: supportCollection ?? self.supportCollection,
            supportHistory: supportHistory ?? self.supportHistory,
            supportCategories: supportCategories ?? self.supportCategories,
            supportAdvancedSearch: supportAdvancedSearch ?? self.supportAdvancedSearch,
            showCover: showCover ?? self.showCover,
            supportCommentDetail: supportCommentDetail ?? self.supportCommentDetail,
            nativeDetail: nativeDetail ?? self.nativeDetail
        )
    }

    static let mteamDefault = SiteFeatures(supportCommentDetail: true)
}

extension SiteFeatures: Codable {
    init(from decoder: Decoder) throws {
        self = try SiteFeatures.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension SiteFeatures: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct SiteSearchItem: Hashable {
    var id: String
    var additionalParams: [String: Any]?

    init(id: String, additionalParams: [String: Any]? = nil) {
        self.id = id
        self.additionalParams = additionalParams
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case additionalParams
    }

    static func fromJson(_ json: [String: Any]) throws -> SiteSearchItem {
        SiteSearchItem(
            id: try JSONCast.string(json["id"]),
            additionalParams: try JSONCast.optionalMap(json["additionalParams"])
        )
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "additionalParams": anyOrNil(additionalParams),
        ]
    }

    func copyWith(
        id: String? = nil,
        additionalParams: [String: Any]? = nil
    ) -> SiteSearchItem {
        SiteSearchItem(
            id: id ?? self.id,
            additionalParams: additionalParams ?? self.additionalParams
        )
    }

    static func == (lhs: SiteSearchItem, rhs: SiteSearchItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension SiteSearchItem: Codable {
    init(from decoder: Decoder) throws {
        self = try SiteSearchItem.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension SiteSearchItem: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct AggregateSearchConfig {
    var id: String
    var name: String
    var type: String
    var enabledSites: [SiteSearchItem]
    var isActive: Bool

    init(
        id: String,
        name: String,
        type: String = "custom",
        enabledSites: [SiteSearchItem] = [],
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabledSites = enabledSites
        self.isActive = isActive
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case enabledSites
        case isActive
    }

    static func fromJson(_ json: [String: Any]) throws -> AggregateSearchConfig {
        var enabledSites: [SiteSearchItem] = []
        if let raw = json.firstValue("enabledSites") {
            let list = try JSONCast.list(raw)
            for element in list {
                enabledSites.append(
                    try SiteSearchItem.fromJson(try JSONCast.map(element))
                )
            }
        }

        return AggregateSearchConfig(
            id: try JSONCast.optionalString(json["id"]) ?? legacyIdentifier(),
            name: try JSONCast.string(json["name"]),
            type: try JSONCast.optionalString(json["type"]) ?? "custom",
            enabledSites: enabledSites,
            isActive: try json.coalesceBool("isActive", default: true)
        )
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "type": type,
            "enabledSites": enabledSites.map { $0.toJson() },
            "isActive": isActive,
        ]
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        type: String? = nil,
        enabledSites: [SiteSearchItem]? = nil,
        isActive: Bool? = nil
    ) -> AggregateSearchConfig {
        AggregateSearchConfig(
            id: id ?? self.id,
            name: name ?? self.name,
            type: type ?? self.type,
            enabledSites: enabledSites ?? self.enabledSites,
            isActive: isActive ?? self.isActive
        )
    }

    static func createDefaultConfig(_ allSiteIds: [String]) -> AggregateSearchConfig {
        AggregateSearchConfig(
            id: "all-sites",
            name: "所有",
            type: "all",
            enabledSites: [],
            isActive: true
        )
    }

    var isAllSitesType: Bool {
        type == "all"
    }

    var canEdit: Bool {
        type != "all"
    }

    var canDelete: Bool {
        type != "all"
    }

    func getEnabledSiteIds(_ allSiteIds: [String]) -> [String] {
        if type == "all" {
            return allSiteIds
        }
        return enabledSites.map { $0.id }
    }

    func getEnabledSites(_ allSiteIds: [String]) -> [SiteSearchItem] {
        if type == "all" {
            var configuredSites: [String: SiteSearchItem] = [:]
            for site in enabledSites {
                configuredSites[site.id] = site
            }
            return allSiteIds.map { id in
                if let configured = configuredSites[id] {
                    return configured
                }
                return SiteSearchItem(id: id)
            }
        }
        return enabledSites
    }
}

extension AggregateSearchConfig: Codable {
    init(from decoder: Decoder) throws {
        self = try AggregateSearchConfig.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension AggregateSearchConfig: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct AggregateSearchSettings {
    var searchConfigs: [AggregateSearchConfig]
    var searchThreads: Int

    init(
        searchConfigs: [AggregateSearchConfig] = [],
        searchThreads: Int = 3
    ) {
        self.searchConfigs = searchConfigs
        self.searchThreads = searchThreads
    }

    private enum CodingKeys: String, CodingKey {
        case searchConfigs
        case searchThreads
    }

    static func fromJson(_ json: [String: Any]) throws -> AggregateSearchSettings {
        var configs: [AggregateSearchConfig] = []
        if let raw = json.firstValue("searchConfigs") {
            do {
                let list = try JSONCast.list(raw)
                configs = try list.map {
                    try AggregateSearchConfig.fromJson(try JSONCast.map($0))
                }
            } catch {
                configs = []
            }
        }

        return AggregateSearchSettings(
            searchConfigs: configs,
            searchThreads: try JSONCast.optionalInt(json["searchThreads"]) ?? 3
        )
    }

    func toJson() -> [String: Any] {
        [
            "searchConfigs": searchConfigs.map { $0.toJson() },
            "searchThreads": searchThreads,
        ]
    }

    func copyWith(
        searchConfigs: [AggregateSearchConfig]? = nil,
        searchThreads: Int? = nil
    ) -> AggregateSearchSettings {
        AggregateSearchSettings(
            searchConfigs: searchConfigs ?? self.searchConfigs,
            searchThreads: searchThreads ?? self.searchThreads
        )
    }
}

extension AggregateSearchSettings: Codable {
    init(from decoder: Decoder) throws {
        self = try AggregateSearchSettings.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension AggregateSearchSettings: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct SiteConfigLoadResult {
    var config: SiteConfig
    var needsUpdate: Bool

    init(config: SiteConfig, needsUpdate: Bool) {
        self.config = config
        self.needsUpdate = needsUpdate
    }
}

struct SiteConfig {
    var id: String
    var name: String
    var baseUrl: String
    var apiKey: String?
    var passKey: String?
    var authKey: String?
    var cookie: String?
    var userId: String?
    var siteType: SiteType
    var isActive: Bool
    var searchCategories: [SearchCategoryConfig]
    var features: SiteFeatures
    var templateId: String
    var siteColor: Int?
    var operationIntervalMs: Int

    init(
        id: String,
        name: String,
        baseUrl: String,
        apiKey: String? = nil,
        passKey: String? = nil,
        authKey: String? = nil,
        cookie: String? = nil,
        userId: String? = nil,
        siteType: SiteType = .mteam,
        isActive: Bool = true,
        searchCategories: [SearchCategoryConfig] = [],
        features: SiteFeatures = .mteamDefault,
        templateId: String = "",
        siteColor: Int? = nil,
        operationIntervalMs: Int = 500
    ) {
        self.id = id
        self.name = name
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.passKey = passKey
        self.authKey = authKey
        self.cookie = cookie
        self.userId = userId
        self.siteType = siteType
        self.isActive = isActive
        self.searchCategories = searchCategories
        self.features = features
        self.templateId = templateId
        self.siteColor = siteColor
        self.operationIntervalMs = operationIntervalMs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseUrl
        case apiKey
        case passKey
        case authKey
        case cookie
        case userId
        case siteType
        case isActive
        case searchCategories
        case features
        case templateId
        case siteColor
        case operationIntervalMs
    }

    private static func parseSiteColor(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let int = strictIntValue(value) {
            return int
        }
        if let string = value as? String {
            let v = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.hasPrefix("#") {
                let hex = String(v.dropFirst())
                let candidate = hex.count == 6 ? "FF" + hex : hex
                return Int(candidate, radix: 16)
            }
        }
        return nil
    }

    private static func getTemplateIdByBaseUrl(_ baseUrl: String) -> String {
        let normalizedBaseUrl = baseUrl.hasSuffix("/")
            ? String(baseUrl.dropLast())
            : baseUrl

        let fallbackMapping: [String: String] = [
            "https://api.mteam.cc": "mteam",
            "https://www.ptskit.org": "ptskit",
            "https://www.hxpt.org": "hxpt",
            "https://zmpt.cc": "zmpt",
            "https://www.afun.tv": "afun",
            "https://cangbao.tv": "cangbao",
            "https://lajidui.org": "lajidui",
            "https://ptfans.org": "ptfans",
            "https://xingyunge.org": "xingyunge",
        ]

        return fallbackMapping[normalizedBaseUrl] ?? "-1"
    }

    static func getTemplateIdByBaseUrlAsync(
        _ baseUrl: String,
        getUrlToTemplateIdMapping: (() async throws -> [String: String])? = nil
    ) async -> String {
        let normalizedBaseUrl = baseUrl.hasSuffix("/")
            ? String(baseUrl.dropLast())
            : baseUrl

        let quick = getTemplateIdByBaseUrl(normalizedBaseUrl)
        if quick != "-1" {
            return quick
        }

        if let getUrlToTemplateIdMapping {
            do {
                let urlMapping = try await getUrlToTemplateIdMapping()
                if let templateId = urlMapping[normalizedBaseUrl] {
                    return templateId
                }
            } catch {
            }
        }

        return "-1"
    }

    static func fromJson(_ json: [String: Any]) throws -> SiteConfig {
        var categories: [SearchCategoryConfig] = []
        if let raw = json.firstValue("searchCategories") {
            do {
                let list = try JSONCast.list(raw)
                categories = try list.map {
                    try SearchCategoryConfig.fromJson(try JSONCast.map($0))
                }
            } catch {
                categories = SearchCategoryConfig.getDefaultConfigs()
            }
        } else {
            categories = SearchCategoryConfig.getDefaultConfigs()
        }

        var features = SiteFeatures.mteamDefault
        if let raw = json.firstValue("features") {
            do {
                features = try SiteFeatures.fromJson(try JSONCast.map(raw))
            } catch {
                features = SiteFeatures.mteamDefault
            }
        }

        var templateId = try JSONCast.optionalString(json["templateId"]) ?? ""
        if templateId.isEmpty {
            let baseUrl = try JSONCast.string(json["baseUrl"])
            templateId = getTemplateIdByBaseUrl(baseUrl)
        }

        let siteColor = parseSiteColor(json.firstValue("siteColor"))

        return SiteConfig(
            id: try JSONCast.optionalString(json["id"]) ?? legacyIdentifier(),
            name: try JSONCast.string(json["name"]),
            baseUrl: try JSONCast.string(json["baseUrl"]),
            apiKey: try JSONCast.optionalString(json["apiKey"]),
            passKey: try JSONCast.optionalString(json["passKey"]),
            authKey: try JSONCast.optionalString(json["authKey"]),
            cookie: try JSONCast.optionalString(json["cookie"]),
            userId: try JSONCast.optionalString(json["userId"]),
            siteType: SiteType.fromId(
                try JSONCast.optionalString(json["siteType"])
            ),
            isActive: try json.coalesceBool("isActive", default: true),
            searchCategories: categories,
            features: features,
            templateId: templateId,
            siteColor: siteColor,
            operationIntervalMs: try JSONCast.optionalInt(
                json["operationIntervalMs"]
            ) ?? 500
        )
    }

    static func fromJsonAsync(
        _ json: [String: Any],
        loadPresetSiteTemplates: (() async throws -> [SiteConfigTemplate])? = nil,
        getUrlToTemplateIdMapping: (() async throws -> [String: String])? = nil
    ) async throws -> SiteConfigLoadResult {
        var categories: [SearchCategoryConfig] = []
        if let raw = json.firstValue("searchCategories") {
            do {
                let list = try JSONCast.list(raw)
                categories = try list.map {
                    try SearchCategoryConfig.fromJson(try JSONCast.map($0))
                }
            } catch {
                categories = SearchCategoryConfig.getDefaultConfigs()
            }
        } else {
            categories = SearchCategoryConfig.getDefaultConfigs()
        }

        var features = SiteFeatures.mteamDefault
        if let raw = json.firstValue("features") {
            do {
                features = try SiteFeatures.fromJson(try JSONCast.map(raw))
            } catch {
                features = SiteFeatures.mteamDefault
            }
        }

        var templateId = try JSONCast.optionalString(json["templateId"]) ?? ""
        var needsUpdate = false

        if templateId.isEmpty || templateId == "-1" {
            let baseUrl = try JSONCast.string(json["baseUrl"])
            templateId = await getTemplateIdByBaseUrlAsync(
                baseUrl,
                getUrlToTemplateIdMapping: getUrlToTemplateIdMapping
            )
            needsUpdate = !templateId.isEmpty && templateId != "-1"
        } else {
            do {
                guard let loadPresetSiteTemplates else {
                    throw ModelsError.argumentException(
                        "loadPresetSiteTemplates unavailable"
                    )
                }
                let templates = try await loadPresetSiteTemplates()
                let templateExists = templates.contains { $0.id == templateId }
                if !templateExists {
                    let baseUrl = try JSONCast.string(json["baseUrl"])
                    let newTemplateId = await getTemplateIdByBaseUrlAsync(
                        baseUrl,
                        getUrlToTemplateIdMapping: getUrlToTemplateIdMapping
                    )
                    if !newTemplateId.isEmpty && newTemplateId != "-1" {
                        templateId = newTemplateId
                        needsUpdate = true
                    }
                }
            } catch {
            }
        }

        if templateId == "mteam-api" {
            templateId = "mteam"
            needsUpdate = true
        }

        let siteColor = parseSiteColor(json.firstValue("siteColor"))

        let config = SiteConfig(
            id: try JSONCast.optionalString(json["id"]) ?? legacyIdentifier(),
            name: try JSONCast.string(json["name"]),
            baseUrl: try JSONCast.string(json["baseUrl"]),
            apiKey: try JSONCast.optionalString(json["apiKey"]),
            passKey: try JSONCast.optionalString(json["passKey"]),
            authKey: try JSONCast.optionalString(json["authKey"]),
            cookie: try JSONCast.optionalString(json["cookie"]),
            userId: try JSONCast.optionalString(json["userId"]),
            siteType: SiteType.fromId(
                try JSONCast.optionalString(json["siteType"])
            ),
            isActive: try json.coalesceBool("isActive", default: true),
            searchCategories: categories,
            features: features,
            templateId: templateId,
            siteColor: siteColor,
            operationIntervalMs: try JSONCast.optionalInt(
                json["operationIntervalMs"]
            ) ?? 500
        )

        return SiteConfigLoadResult(config: config, needsUpdate: needsUpdate)
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "baseUrl": baseUrl,
            "apiKey": anyOrNil(apiKey),
            "passKey": anyOrNil(passKey),
            "authKey": anyOrNil(authKey),
            "cookie": anyOrNil(cookie),
            "userId": anyOrNil(userId),
            "siteType": siteType.id,
            "isActive": isActive,
            "searchCategories": searchCategories.map { $0.toJson() },
            "features": features.toJson(),
            "templateId": templateId,
            "siteColor": anyOrNil(siteColor),
            "operationIntervalMs": operationIntervalMs,
        ]
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        baseUrl: String? = nil,
        apiKey: String? = nil,
        passKey: String? = nil,
        authKey: String? = nil,
        cookie: String? = nil,
        userId: String? = nil,
        siteType: SiteType? = nil,
        isActive: Bool? = nil,
        searchCategories: [SearchCategoryConfig]? = nil,
        features: SiteFeatures? = nil,
        templateId: String? = nil,
        siteColor: Int? = nil,
        operationIntervalMs: Int? = nil,
        clearApiKey: Bool = false,
        clearCookie: Bool = false
    ) -> SiteConfig {
        SiteConfig(
            id: id ?? self.id,
            name: name ?? self.name,
            baseUrl: baseUrl ?? self.baseUrl,
            apiKey: clearApiKey ? nil : (apiKey ?? self.apiKey),
            passKey: passKey ?? self.passKey,
            authKey: authKey ?? self.authKey,
            cookie: clearCookie ? nil : (cookie ?? self.cookie),
            userId: userId ?? self.userId,
            siteType: siteType ?? self.siteType,
            isActive: isActive ?? self.isActive,
            searchCategories: searchCategories ?? self.searchCategories,
            features: features ?? self.features,
            templateId: templateId ?? self.templateId,
            siteColor: siteColor ?? self.siteColor,
            operationIntervalMs: operationIntervalMs ?? self.operationIntervalMs
        )
    }
}

extension SiteConfig: SiteConfigStorable {}

extension SiteConfig: Codable {
    init(from decoder: Decoder) throws {
        self = try SiteConfig.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension SiteConfig: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct SiteConfigTemplate {
    var id: String
    var name: String
    var isShow: Bool
    var baseUrls: [String]
    var primaryUrl: String?
    var siteType: SiteType
    var searchCategories: [SearchCategoryConfig]
    var features: SiteFeatures
    var discountMapping: [String: String]
    var tagMapping: [String: String]
    var infoFinder: [String: Any]?
    var request: [String: Any]?
    var logo: String?
    var operationIntervalMs: Int

    init(
        id: String,
        name: String,
        isShow: Bool = true,
        baseUrls: [String],
        primaryUrl: String? = nil,
        siteType: SiteType = .mteam,
        searchCategories: [SearchCategoryConfig] = [],
        features: SiteFeatures = .mteamDefault,
        discountMapping: [String: String] = [:],
        tagMapping: [String: String] = [:],
        infoFinder: [String: Any]? = nil,
        request: [String: Any]? = nil,
        logo: String? = nil,
        operationIntervalMs: Int = 500
    ) {
        self.id = id
        self.name = name
        self.isShow = isShow
        self.baseUrls = baseUrls
        self.primaryUrl = primaryUrl
        self.siteType = siteType
        self.searchCategories = searchCategories
        self.features = features
        self.discountMapping = discountMapping
        self.tagMapping = tagMapping
        self.infoFinder = infoFinder
        self.request = request
        self.logo = logo
        self.operationIntervalMs = operationIntervalMs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isShow
        case baseUrls
        case baseUrl
        case primaryUrl
        case siteType
        case searchCategories
        case features
        case discountMapping
        case tagMapping
        case infoFinder
        case request
        case logo
        case operationIntervalMs
    }

    static func fromJson(_ json: [String: Any]) throws -> SiteConfigTemplate {
        var categories: [SearchCategoryConfig] = []
        if let raw = json.firstValue("searchCategories") {
            do {
                let list = try JSONCast.list(raw)
                categories = try list.map {
                    try SearchCategoryConfig.fromJson(try JSONCast.map($0))
                }
            } catch {
                categories = SearchCategoryConfig.getDefaultConfigs()
            }
        } else {
            categories = SearchCategoryConfig.getDefaultConfigs()
        }

        var features = SiteFeatures.mteamDefault
        if let raw = json.firstValue("features") {
            do {
                features = try SiteFeatures.fromJson(try JSONCast.map(raw))
            } catch {
                features = SiteFeatures.mteamDefault
            }
        }

        var baseUrls: [String] = []
        if let raw = json.firstValue("baseUrls") {
            baseUrls = try JSONCast.stringList(raw)
        } else if let raw = json.firstValue("baseUrl") {
            baseUrls = [try JSONCast.string(raw)]
        }

        var discountMapping: [String: String] = [:]
        if let raw = json.firstValue("discountMapping") {
            do {
                let map = try JSONCast.map(raw)
                var parsed: [String: String] = [:]
                for (key, value) in map {
                    parsed[key] = try JSONCast.string(value)
                }
                discountMapping = parsed
            } catch {
                discountMapping = [:]
            }
        }

        var infoFinder: [String: Any]?
        if let raw = json.firstValue("infoFinder") {
            infoFinder = try? JSONCast.map(raw)
        }

        var tagMapping: [String: String] = [:]
        if let raw = json.firstValue("tagMapping") {
            let map = try JSONCast.map(raw)
            var parsed: [String: String] = [:]
            for (key, value) in map {
                parsed[key] = try JSONCast.string(value)
            }
            tagMapping = parsed
        }

        return SiteConfigTemplate(
            id: try JSONCast.string(json["id"]),
            name: try JSONCast.string(json["name"]),
            isShow: try json.coalesceBool("isShow", default: true),
            baseUrls: baseUrls,
            primaryUrl: try JSONCast.optionalString(json["primaryUrl"]),
            siteType: SiteType.fromId(
                try JSONCast.optionalString(json["siteType"])
            ),
            searchCategories: categories,
            features: features,
            discountMapping: discountMapping,
            tagMapping: tagMapping,
            infoFinder: infoFinder,
            request: try JSONCast.optionalMap(json["request"]),
            logo: try JSONCast.optionalString(json["logo"]),
            operationIntervalMs: try JSONCast.optionalInt(
                json["operationIntervalMs"]
            ) ?? 500
        )
    }

    func toJson() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "name": name,
            "isShow": isShow,
            "baseUrls": baseUrls,
            "primaryUrl": anyOrNil(primaryUrl),
            "siteType": siteType.id,
            "searchCategories": searchCategories.map { $0.toJson() },
            "features": features.toJson(),
            "discountMapping": discountMapping,
            "tagMapping": tagMapping,
            "infoFinder": anyOrNil(infoFinder),
            "request": anyOrNil(request),
            "operationIntervalMs": operationIntervalMs,
        ]
        if let logo {
            result["logo"] = logo
        }
        return result
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        isShow: Bool? = nil,
        baseUrls: [String]? = nil,
        primaryUrl: String? = nil,
        siteType: SiteType? = nil,
        searchCategories: [SearchCategoryConfig]? = nil,
        features: SiteFeatures? = nil,
        discountMapping: [String: String]? = nil,
        tagMapping: [String: String]? = nil,
        infoFinder: [String: Any]? = nil,
        request: [String: Any]? = nil,
        logo: String? = nil,
        operationIntervalMs: Int? = nil
    ) -> SiteConfigTemplate {
        SiteConfigTemplate(
            id: id ?? self.id,
            name: name ?? self.name,
            isShow: isShow ?? self.isShow,
            baseUrls: baseUrls ?? self.baseUrls,
            primaryUrl: primaryUrl ?? self.primaryUrl,
            siteType: siteType ?? self.siteType,
            searchCategories: searchCategories ?? self.searchCategories,
            features: features ?? self.features,
            discountMapping: discountMapping ?? self.discountMapping,
            tagMapping: tagMapping ?? self.tagMapping,
            infoFinder: infoFinder ?? self.infoFinder,
            request: request ?? self.request,
            logo: logo ?? self.logo,
            operationIntervalMs: operationIntervalMs ?? self.operationIntervalMs
        )
    }

    func toSiteConfig(
        selectedUrl: String? = nil,
        apiKey: String? = nil,
        passKey: String? = nil,
        cookie: String? = nil,
        userId: String? = nil,
        isActive: Bool = true
    ) throws -> SiteConfig {
        let baseUrl: String
        if let selectedUrl {
            baseUrl = selectedUrl
        } else if let primaryUrl, baseUrls.contains(primaryUrl) {
            baseUrl = primaryUrl
        } else if !baseUrls.isEmpty {
            baseUrl = baseUrls[0]
        } else {
            throw ModelsError.argumentException(
                "No valid baseUrl available in template"
            )
        }

        return SiteConfig(
            id: id,
            name: name,
            baseUrl: baseUrl,
            apiKey: apiKey,
            passKey: passKey,
            cookie: cookie,
            userId: userId,
            siteType: siteType,
            isActive: isActive,
            searchCategories: searchCategories,
            features: features,
            templateId: id,
            operationIntervalMs: operationIntervalMs
        )
    }

    var displayUrl: String {
        if let primaryUrl, baseUrls.contains(primaryUrl) {
            return primaryUrl
        }
        return baseUrls.isEmpty ? "" : baseUrls[0]
    }
}

extension SiteConfigTemplate: Codable {
    init(from decoder: Decoder) throws {
        self = try SiteConfigTemplate.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension SiteConfigTemplate: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct SearchCategoryConfig {
    var id: String
    var displayName: String
    var parameters: String

    init(id: String, displayName: String, parameters: String) {
        self.id = id
        self.displayName = displayName
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case parameters
    }

    static func fromJson(_ json: [String: Any]) throws -> SearchCategoryConfig {
        SearchCategoryConfig(
            id: try JSONCast.string(json["id"]),
            displayName: try JSONCast.string(json["displayName"]),
            parameters: try JSONCast.string(json["parameters"])
        )
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "displayName": displayName,
            "parameters": parameters,
        ]
    }

    func copyWith(
        id: String? = nil,
        displayName: String? = nil,
        parameters: String? = nil
    ) -> SearchCategoryConfig {
        SearchCategoryConfig(
            id: id ?? self.id,
            displayName: displayName ?? self.displayName,
            parameters: parameters ?? self.parameters
        )
    }

    func parseParameters() -> [String: Any] {
        var result: [String: Any] = [:]
        let trimmed = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return result
        }

        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            if let data = trimmed.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data),
                let jsonResult = object as? [String: Any]
            {
                return jsonResult
            }
        }

        let parts = trimmed.split(separator: ";", omittingEmptySubsequences: false)
        for part in parts {
            let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPart.isEmpty {
                continue
            }
            guard let colonIndex = trimmedPart.firstIndex(of: ":") else {
                continue
            }
            let key = String(trimmedPart[trimmedPart.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStr = String(
                trimmedPart[trimmedPart.index(after: colonIndex)...]
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                if valueStr.hasPrefix("[") || valueStr.hasPrefix("{") {
                    guard let data = valueStr.data(using: .utf8) else {
                        throw ModelsError.formatException(
                            "Invalid JSON value: \(valueStr)"
                        )
                    }
                    result[key] = try JSONSerialization.jsonObject(with: data)
                } else if valueStr.hasPrefix("\""), valueStr.hasSuffix("\""),
                    valueStr.count >= 2
                {
                    result[key] = String(valueStr.dropFirst().dropLast())
                } else if valueStr.lowercased() == "true" {
                    result[key] = true
                } else if valueStr.lowercased() == "false" {
                    result[key] = false
                } else if valueStr.lowercased() == "null" {
                    result[key] = NSNull()
                } else if let intValue = dartParseInt(valueStr) {
                    result[key] = intValue
                } else if let doubleValue = dartDoubleFromString(valueStr) {
                    result[key] = doubleValue
                } else {
                    result[key] = valueStr
                }
            } catch {
                result[key] = valueStr
            }
        }
        return result
    }

    static func getDefaultConfigs() -> [SearchCategoryConfig] {
        [
            SearchCategoryConfig(
                id: "normal",
                displayName: "综合",
                parameters: #"{"mode": "normal"}"#
            ),
            SearchCategoryConfig(
                id: "tvshow",
                displayName: "电视",
                parameters: #"{"mode": "tvshow"}"#
            ),
            SearchCategoryConfig(
                id: "movie",
                displayName: "电影",
                parameters: #"{"mode": "movie"}"#
            ),
        ]
    }
}

extension SearchCategoryConfig: Codable {
    init(from decoder: Decoder) throws {
        self = try SearchCategoryConfig.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension SearchCategoryConfig: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct QbClientConfig {
    var id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String?
    var useLocalRelay: Bool
    var version: String?

    init(
        id: String,
        name: String,
        host: String,
        port: Int,
        username: String,
        password: String? = nil,
        useLocalRelay: Bool = false,
        version: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useLocalRelay = useLocalRelay
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case username
        case useLocalRelay
        case version
    }

    static func fromJson(_ json: [String: Any]) throws -> QbClientConfig {
        QbClientConfig(
            id: try JSONCast.string(json["id"]),
            name: try JSONCast.string(json["name"]),
            host: try JSONCast.string(json["host"]),
            port: try dartDoubleToInt(try JSONCast.num(json["port"])),
            username: try JSONCast.string(json["username"]),
            useLocalRelay: try json.coalesceBool(
                "useLocalRelay",
                default: false
            ),
            version: try JSONCast.optionalString(json["version"])
        )
    }

    func toJson() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "name": name,
            "host": host,
            "port": port,
            "username": username,
            "useLocalRelay": useLocalRelay,
        ]
        if let version {
            result["version"] = version
        }
        return result
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        useLocalRelay: Bool? = nil,
        version: String? = nil
    ) -> QbClientConfig {
        QbClientConfig(
            id: id ?? self.id,
            name: name ?? self.name,
            host: host ?? self.host,
            port: port ?? self.port,
            username: username ?? self.username,
            password: password ?? self.password,
            useLocalRelay: useLocalRelay ?? self.useLocalRelay,
            version: version ?? self.version
        )
    }
}

extension QbClientConfig: Codable {
    init(from decoder: Decoder) throws {
        self = try QbClientConfig.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

enum WebDAVSyncStatus: String, CaseIterable {
    case idle
    case syncing
    case uploading
    case downloading
    case success
    case error
}

struct WebDAVConfig {
    var id: String
    var name: String
    var serverUrl: String
    var username: String
    var remotePath: String
    var isEnabled: Bool
    var autoSync: Bool
    var syncIntervalMinutes: Int
    var lastSyncTime: Date?
    var lastSyncStatus: WebDAVSyncStatus
    var lastSyncError: String?

    init(
        id: String,
        name: String,
        serverUrl: String,
        username: String,
        remotePath: String = "/PTMate/backups/",
        isEnabled: Bool = false,
        autoSync: Bool = false,
        syncIntervalMinutes: Int = 60,
        lastSyncTime: Date? = nil,
        lastSyncStatus: WebDAVSyncStatus = .idle,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.serverUrl = serverUrl
        self.username = username
        self.remotePath = remotePath
        self.isEnabled = isEnabled
        self.autoSync = autoSync
        self.syncIntervalMinutes = syncIntervalMinutes
        self.lastSyncTime = lastSyncTime
        self.lastSyncStatus = lastSyncStatus
        self.lastSyncError = lastSyncError
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case serverUrl
        case username
        case remotePath
        case isEnabled
        case autoSync
        case syncIntervalMinutes
        case lastSyncTime
        case lastSyncStatus
        case lastSyncError
    }

    static func fromJson(_ json: [String: Any]) throws -> WebDAVConfig {
        var lastSyncTime: Date?
        if let raw = json.firstValue("lastSyncTime") {
            lastSyncTime = try dartParseDateTime(try JSONCast.string(raw))
        }

        return WebDAVConfig(
            id: try JSONCast.string(json["id"]),
            name: try JSONCast.string(json["name"]),
            serverUrl: try JSONCast.string(json["serverUrl"]),
            username: try JSONCast.string(json["username"]),
            remotePath: try JSONCast.optionalString(json["remotePath"])
                ?? "/PTMate/backups/",
            isEnabled: try json.coalesceBool("isEnabled", default: false),
            autoSync: try json.coalesceBool("autoSync", default: false),
            syncIntervalMinutes: try JSONCast.optionalInt(
                json["syncIntervalMinutes"]
            ) ?? 60,
            lastSyncTime: lastSyncTime,
            lastSyncStatus: WebDAVSyncStatus(
                rawValue: try JSONCast.optionalString(json["lastSyncStatus"])
                    ?? "idle"
            ) ?? .idle,
            lastSyncError: try JSONCast.optionalString(json["lastSyncError"])
        )
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "serverUrl": serverUrl,
            "username": username,
            "remotePath": remotePath,
            "isEnabled": isEnabled,
            "autoSync": autoSync,
            "syncIntervalMinutes": syncIntervalMinutes,
            "lastSyncTime": anyOrNil(lastSyncTime.map(dartToIso8601String)),
            "lastSyncStatus": lastSyncStatus.rawValue,
            "lastSyncError": anyOrNil(lastSyncError),
        ]
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        serverUrl: String? = nil,
        username: String? = nil,
        remotePath: String? = nil,
        isEnabled: Bool? = nil,
        autoSync: Bool? = nil,
        syncIntervalMinutes: Int? = nil,
        lastSyncTime: Date? = nil,
        lastSyncStatus: WebDAVSyncStatus? = nil,
        lastSyncError: String? = nil
    ) -> WebDAVConfig {
        WebDAVConfig(
            id: id ?? self.id,
            name: name ?? self.name,
            serverUrl: serverUrl ?? self.serverUrl,
            username: username ?? self.username,
            remotePath: remotePath ?? self.remotePath,
            isEnabled: isEnabled ?? self.isEnabled,
            autoSync: autoSync ?? self.autoSync,
            syncIntervalMinutes: syncIntervalMinutes ?? self.syncIntervalMinutes,
            lastSyncTime: lastSyncTime ?? self.lastSyncTime,
            lastSyncStatus: lastSyncStatus ?? self.lastSyncStatus,
            lastSyncError: lastSyncError ?? self.lastSyncError
        )
    }

    static func createDefault() -> WebDAVConfig {
        WebDAVConfig(
            id: "default-\(Int64((Date().timeIntervalSince1970 * 1000).rounded()))",
            name: "默认WebDAV配置",
            serverUrl: "",
            username: ""
        )
    }

    static func getPresets() -> [WebDAVPreset] {
        [
            WebDAVPreset(
                name: "坚果云",
                serverUrl: "https://dav.jianguoyun.com/dav/",
                description:
                    "使用坚果云的WebDAV服务，需要在坚果云设置中开启第三方应用管理并创建应用密码"
            ),
            WebDAVPreset(
                name: "Nextcloud",
                serverUrl: "https://your-nextcloud.com/remote.php/dav/files/username/",
                description: "自建或第三方Nextcloud服务，请替换为您的实际服务器地址"
            ),
            WebDAVPreset(
                name: "ownCloud",
                serverUrl: "https://your-owncloud.com/remote.php/webdav/",
                description: "自建或第三方ownCloud服务，请替换为您的实际服务器地址"
            ),
            WebDAVPreset(
                name: "Box",
                serverUrl: "https://dav.box.com/dav/",
                description: "Box云存储的WebDAV接口"
            ),
        ]
    }
}

extension WebDAVConfig: Codable {
    init(from decoder: Decoder) throws {
        self = try WebDAVConfig.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

extension WebDAVConfig: CustomStringConvertible {
    var description: String {
        jsonEncodeString(toJson())
    }
}

struct WebDAVPreset {
    var name: String
    var serverUrl: String
    var description: String

    init(name: String, serverUrl: String, description: String) {
        self.name = name
        self.serverUrl = serverUrl
        self.description = description
    }
}

enum Defaults {
    static func getDefaultSearchCategories() -> [SearchCategoryConfig] {
        SearchCategoryConfig.getDefaultConfigs()
    }

    static func getDefaultSiteFeatures() -> SiteFeatures {
        SiteFeatures.mteamDefault
    }
}

struct HealthStatus {
    var ok: Bool
    var notApplicable: Bool
    var message: String?
    var username: String?
    var profile: MemberProfile?
    var updatedAt: Date

    init(
        ok: Bool,
        notApplicable: Bool = false,
        message: String? = nil,
        username: String? = nil,
        profile: MemberProfile? = nil,
        updatedAt: Date
    ) {
        self.ok = ok
        self.notApplicable = notApplicable
        self.message = message
        self.username = username
        self.profile = profile
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case notApplicable
        case message
        case username
        case profile
        case updatedAt
    }

    static func fromJson(_ json: [String: Any]) -> HealthStatus {
        let ok = dartBoolFromLooseJSON(json["ok"])
        let notApplicable = dartBoolFromLooseJSON(json["notApplicable"])
        let message = json.firstValue("message").map(dartToString)
        let username = json.firstValue("username").map(dartToString)
        let updatedAt = (try? dartParseDateTime(
            json.firstValue("updatedAt").map(dartToString)
                ?? dartToIso8601String(Date())
        )) ?? Date()

        var profile: MemberProfile?
        if let raw = json.firstValue("profile"), let map = raw as? [String: Any] {
            profile = try? MemberProfile.fromJson(map)
        }

        return HealthStatus(
            ok: ok,
            notApplicable: notApplicable,
            message: message,
            username: username,
            profile: profile,
            updatedAt: updatedAt
        )
    }

    func toJson() -> [String: Any] {
        [
            "ok": ok,
            "notApplicable": notApplicable,
            "message": anyOrNil(message),
            "username": anyOrNil(username),
            "profile": anyOrNil(profile?.toJson()),
            "updatedAt": dartToIso8601String(updatedAt),
        ]
    }

    static func isLastAccessOverMonth(_ lastAccess: Date?) -> Bool {
        guard let lastAccess else { return false }
        let now = Date()
        return Int(now.timeIntervalSince(lastAccess) / 86400) >= 30
    }
}

extension HealthStatus: Codable {
    init(from decoder: Decoder) throws {
        self = HealthStatus.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}
