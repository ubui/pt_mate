import Foundation

enum StorageKeys {
    static let appVersion = "app.version"

    static let siteConfigs = "app.sites"
    static let activeSiteId = "app.activeSiteId"

    static let siteConfig = "app.site"

    static let legacyQbClientConfigs = "qb.clients"
    static let legacyDefaultQbId = "qb.defaultId"
    static func legacyQbPasswordKey(_ id: String) -> String {
        "qb.password.\(id)"
    }

    static func legacyQbPasswordFallbackKey(_ id: String) -> String {
        "qb.password.fallback.\(id)"
    }

    static func legacyQbPasswordConflictMarker(_ id: String) -> String {
        "secureStorage.migrationConflict.qbPassword.\(id)"
    }

    static func legacyQbCategoriesKey(_ id: String) -> String {
        "qb.categories.\(id)"
    }

    static func legacyQbTagsKey(_ id: String) -> String {
        "qb.tags.\(id)"
    }

    static let downloaderConfigs = "downloader.configs"
    static let defaultDownloaderId = "downloader.defaultId"
    static func downloaderPasswordKey(_ id: String) -> String {
        "downloader.password.\(id)"
    }

    static func downloaderPasswordFallbackKey(_ id: String) -> String {
        "downloader.password.fallback.\(id)"
    }

    static func downloaderCategoriesKey(_ id: String) -> String {
        "downloader.categories.\(id)"
    }

    static func downloaderTagsKey(_ id: String) -> String {
        "downloader.tags.\(id)"
    }

    static func downloaderPathsKey(_ id: String) -> String {
        "downloader.paths.\(id)"
    }

    static let defaultDownloadCategory = "download.defaultCategory"
    static let defaultDownloadTags = "download.defaultTags"
    static let autoAddSiteTag = "download.autoAddSiteTag"
    static let defaultDownloadSavePath = "download.defaultSavePath"
    static let localDownloadLastDirectory = "download.localLastDirectory"
    static let defaultDownloadToLocal = "download.defaultToLocal"
    static let defaultDownloadStartPaused = "download.defaultStartPaused"

    static func siteApiKey(_ siteId: String) -> String {
        "site.apiKey.\(siteId)"
    }

    static func siteApiKeyFallback(_ siteId: String) -> String {
        "site.apiKey.fallback.\(siteId)"
    }

    static func siteCookie(_ siteId: String) -> String {
        "site.cookie.\(siteId)"
    }

    static func siteCookieFallback(_ siteId: String) -> String {
        "site.cookie.fallback.\(siteId)"
    }

    static let legacySiteApiKey = "site.apiKey"
    static let legacySiteApiKeyFallback = "site.apiKey.fallback"

    static let webdavConfig = "webdav_config"
    static let webdavConfigHistory = "webdav_config_history"
    static func webdavPassword(_ configId: String) -> String {
        "webdav.password.\(configId)"
    }

    static func webdavPasswordFallback(_ configId: String) -> String {
        "webdav.password.fallback.\(configId)"
    }

    static let deviceId = "device_id"
    static let deviceIdFallback = "device_id.fallback"

    static let themeMode = "theme.mode"
    static let themeUseDynamic = "theme.useDynamic"
    static let themeSeedColor = "theme.seedColor"

    static let autoLoadImages = "images.autoLoad"
    static let showCoverImages = "images.showCover"
    static let logToFileEnabled = "logging.toFile"
    static let visibleTags = "ui.visibleTags"

    static let aggregateSearchSettings = "aggregateSearch.settings"

    static let healthStatuses = "app.healthStatuses"
    static let lastSiteHealthRefreshCheck = "app.lastSiteHealthRefreshCheck"

    static let proxyEnabled = "network.proxyEnabled"
    static let proxyHost = "network.proxyHost"
    static let proxyPort = "network.proxyPort"
    static let proxyUsername = "network.proxyUsername"
    static let proxyPassword = "network.proxyPassword"
    static let proxyPasswordFallback = "network.proxyPassword.fallback"
    static let proxyBypassLan = "network.proxyBypassLan"
    static let proxyBypassRules = "network.proxyBypassRules"

    static let cookieCloudUrl = "cookieCloud.url"
    static let cookieCloudUrlFallback = "cookieCloud.url.fallback"
    static let cookieCloudUuid = "cookieCloud.uuid"
    static let cookieCloudUuidFallback = "cookieCloud.uuid.fallback"
    static let cookieCloudPassword = "cookieCloud.password"
    static let cookieCloudPasswordFallback = "cookieCloud.password.fallback"
    static let cookieCloudSecretsV2 = "cookieCloud.secrets.v2"
    static let cookieCloudSecretsV2Fallback = "cookieCloud.secrets.v2.fallback"
    static let cookieCloudSecretsV2PendingCleanup =
        "cookieCloud.secrets.v2.pendingCleanup"
    static let cookieCloudAutoSyncEnabled = "cookieCloud.autoSync"
    static let cookieCloudSyncIntervalMinutes =
        "cookieCloud.syncIntervalMinutes"
    static let cookieCloudLastSyncAt = "cookieCloud.lastSyncAt"
    static let cookieCloudLastSyncSummary = "cookieCloud.lastSyncSummary"
    static let secureFallbackConflict = "secureStorage.fallbackConflict"
    static let secureFallbackConflictsV1 =
        "secureStorage.fallbackConflicts.v1"
    static let pendingSensitiveCompanionV1 =
        "secureStorage.pendingCompanionPreferences.v1"
    static let secureStorageNamespaceInitializedV1 =
        "secureStorage.namespaceInitialized.v1"
    static let secureStorageEncryptedEntriesExpectedV1 =
        "secureStorage.encryptedEntriesExpected.v1"
}
