import Foundation
import CoreFoundation

enum SecureStorageState {
    case unknown
    case ready
    case unavailable
}

enum SecureStorageProfile {
    case platformDefault
}

enum SecureStorageFailureStage {
    case profileProbe
    case cipherInitialization
    case runtimeOperation
}

struct SecureStorageUnavailableError: Error {
    let code: String
    let stage: SecureStorageFailureStage
    let failureType: String?

    init(
        code: String,
        stage: SecureStorageFailureStage = .runtimeOperation,
        failureType: String? = nil
    ) {
        self.code = code
        self.stage = stage
        self.failureType = failureType
    }
}

enum StorageError: Error {
    case siteConfigLoadFailed
    case downloaderConfigLoadFailed
    case invalidPayload(String)
}

enum ISO8601Codec {
    private static let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime]
        return value
    }()

    static func date(from raw: String) -> Date? {
        formatter.date(from: raw) ?? fallbackFormatter.date(from: raw)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

protocol SiteConfigStorable: Codable {
    var id: String { get }
    var apiKey: String? { get set }
    var cookie: String? { get set }
    var needsConfigUpdate: Bool { get }
}

extension SiteConfigStorable {
    var needsConfigUpdate: Bool { false }
}

struct CookieCloudConfig: Codable {
    var url: String
    var uuid: String
    var password: String
    var autoSyncEnabled: Bool
    var syncIntervalMinutes: Int
    var lastSyncAt: Date?
    var lastSyncSummary: String

    init(
        url: String = "",
        uuid: String = "",
        password: String = "",
        autoSyncEnabled: Bool = false,
        syncIntervalMinutes: Int = 360,
        lastSyncAt: Date? = nil,
        lastSyncSummary: String = ""
    ) {
        self.url = url
        self.uuid = uuid
        self.password = password
        self.autoSyncEnabled = autoSyncEnabled
        self.syncIntervalMinutes = syncIntervalMinutes
        self.lastSyncAt = lastSyncAt
        self.lastSyncSummary = lastSyncSummary
    }

    var isConfigured: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case uuid
        case password
        case autoSyncEnabled
        case syncIntervalMinutes
        case lastSyncAt
        case lastSyncSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        password =
            try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        autoSyncEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ??
            false
        syncIntervalMinutes =
            try container.decodeIfPresent(
                Int.self,
                forKey: .syncIntervalMinutes
            ) ?? 360
        let lastSyncAtRaw = try container.decodeIfPresent(
            String.self,
            forKey: .lastSyncAt
        )
        lastSyncAt = lastSyncAtRaw.flatMap { ISO8601Codec.date(from: $0) }
        lastSyncSummary =
            try container.decodeIfPresent(
                String.self,
                forKey: .lastSyncSummary
            ) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(password, forKey: .password)
        try container.encode(autoSyncEnabled, forKey: .autoSyncEnabled)
        try container.encode(syncIntervalMinutes, forKey: .syncIntervalMinutes)
        try container.encodeIfPresent(
            lastSyncAt.map { ISO8601Codec.string(from: $0) },
            forKey: .lastSyncAt
        )
        try container.encode(lastSyncSummary, forKey: .lastSyncSummary)
    }
}

private struct CookieCloudSecrets {
    var url: String
    var uuid: String
    var password: String

    var isEmpty: Bool {
        url.isEmpty && uuid.isEmpty && password.isEmpty
    }
}

private struct LegacyCookieCloudSecrets {
    let secrets: CookieCloudSecrets
    let hasConflict: Bool
}

private enum SensitiveMutation {
    case upsert(String)
    case delete
}

private func jsonString(_ object: Any) throws -> String {
    guard JSONSerialization.isValidJSONObject(object) else {
        throw StorageError.invalidPayload("json_encoding_failed")
    }
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys]
    )
    guard let raw = String(data: data, encoding: .utf8) else {
        throw StorageError.invalidPayload("json_encoding_failed")
    }
    return raw
}

private func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        throw StorageError.invalidPayload("json_encoding_failed")
    }
    return dictionary
}

private func decodeDictionary<T: Decodable>(
    _ type: T.Type,
    from dictionary: [String: Any]
) throws -> T {
    guard JSONSerialization.isValidJSONObject(dictionary) else {
        throw StorageError.invalidPayload("json_encoding_failed")
    }
    let data = try JSONSerialization.data(
        withJSONObject: dictionary,
        options: [.sortedKeys]
    )
    return try JSONDecoder().decode(type, from: data)
}

private func isBooleanValue(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

private func isIntegerValue(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) != CFBooleanGetTypeID()
}

private func unwrapJSONNull(_ value: Any?) -> Any? {
    value is NSNull ? nil : value
}

private func isStringList(_ value: Any?) -> Bool {
    guard let list = value as? [Any] else { return false }
    return list.allSatisfy { $0 is String }
}

final class StorageService {
    static let shared = StorageService()
    static let currentVersion = "1.2.0"

    private enum OperationQueue {
        case site
        case sensitive
        case health
    }

    private let defaults: KeyValueStore
    private let keychain: KeychainStore
    private let stateLock = NSLock()

    private var siteOperationTail: Task<Void, Never>?
    private var sensitiveOperationTail: Task<Void, Never>?
    private var healthOperationTail: Task<Void, Never>?
    private var initTask: Task<Void, Error>?

    private var secureStorageStateValue: SecureStorageState = .unknown
    private var secureStorageProfileValue: SecureStorageProfile?
    private var secureStorageFailureCodeValue: String?
    private var secureStorageFailureStageValue: SecureStorageFailureStage?
    private var secureStorageFailureTypeValue: String?

    private var siteConfigsCacheValue: [[String: Any]]?
    private var siteConfigsCacheDirty = true
    private var siteConfigsCacheNeedsUpdate = false
    private var siteApiKeysCache: [String: String?] = [:]
    private var siteCookiesCache: [String: String?] = [:]
    private var hasPendingConfigUpdates = false
    private var cookieCloudBundleCreatedThisRun = false
    private var visibleTagsCache: [String]?

    init(
        defaults: KeyValueStore = .standard,
        keychain: KeychainStore = .shared
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

    var secureStorageState: SecureStorageState {
        withStateLock { secureStorageStateValue }
    }

    var secureStorageProfile: SecureStorageProfile? {
        withStateLock { secureStorageProfileValue }
    }

    var secureStorageFailureCode: String? {
        withStateLock { secureStorageFailureCodeValue }
    }

    var secureStorageFailureStage: SecureStorageFailureStage? {
        withStateLock { secureStorageFailureStageValue }
    }

    var secureStorageFailureType: String? {
        withStateLock { secureStorageFailureTypeValue }
    }

    var isSecureStorageReady: Bool {
        secureStorageState == .ready
    }

    var canAccessSensitiveStorage: Bool {
        isSecureStorageReady
    }

    var visibleTags: [String] {
        withStateLock { visibleTagsCache ?? [] }
    }

    private func withStateLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func performSerialized<Result>(
        on queue: OperationQueue,
        _ operation: @escaping () async throws -> Result
    ) async throws -> Result {
        let task: Task<Result, Error> = withStateLock {
            let previous: Task<Void, Never>?
            switch queue {
            case .site:
                previous = siteOperationTail
            case .sensitive:
                previous = sensitiveOperationTail
            case .health:
                previous = healthOperationTail
            }
            let task = Task<Result, Error> {
                if let previous {
                    await previous.value
                }
                return try await operation()
            }
            let wrapper = Task { _ = try? await task.value }
            switch queue {
            case .site:
                siteOperationTail = wrapper
            case .sensitive:
                sensitiveOperationTail = wrapper
            case .health:
                healthOperationTail = wrapper
            }
            return task
        }
        return try await task.value
    }

    func initializeSecureStorage(force: Bool = false) async throws {
        if !force {
            let state = withStateLock { secureStorageStateValue }
            if state == .ready {
                return
            }
            if state == .unavailable {
                throw storedUnavailableError()
            }
        }
        let task: Task<Void, Error> = withStateLock {
            if !force, let existing = initTask {
                return existing
            }
            let created: Task<Void, Error> = Task { await self.runSecureStorageProbe() }
            initTask = created
            return created
        }
        try await task.value
        let state = withStateLock { secureStorageStateValue }
        if state == .unavailable {
            throw storedUnavailableError()
        }
    }

    private func runSecureStorageProbe() async {
        let probeKey = "__ptmate_secure_storage_probe__"
        let probeValue = "ptmate-secure-storage-probe"
        do {
            try await keychain.set(probeValue, for: probeKey)
            let value = try await keychain.string(for: probeKey)
            try await keychain.remove(probeKey)
            guard value == probeValue else {
                markSecureStorageUnavailable(
                    code: "secure_storage_probe_verification_failed",
                    stage: .cipherInitialization
                )
                return
            }
            withStateLock {
                secureStorageProfileValue = .platformDefault
                secureStorageStateValue = .ready
                secureStorageFailureCodeValue = nil
                secureStorageFailureStageValue = nil
                secureStorageFailureTypeValue = nil
            }
        } catch let error as KeychainError {
            markSecureStorageUnavailable(
                code: "secure_storage_unavailable",
                stage: .profileProbe,
                failureType: "keychain_\(error.status)"
            )
        } catch let error as SecureStorageUnavailableError {
            markSecureStorageUnavailable(
                code: error.code,
                stage: .profileProbe,
                failureType: error.failureType
            )
        } catch {
            markSecureStorageUnavailable(
                code: "secure_storage_unavailable",
                stage: .profileProbe,
                failureType: String(describing: type(of: error))
            )
        }
    }

    private func markSecureStorageUnavailable(
        code: String,
        stage: SecureStorageFailureStage,
        failureType: String? = nil
    ) {
        withStateLock {
            secureStorageProfileValue = .platformDefault
            secureStorageStateValue = .unavailable
            secureStorageFailureCodeValue = code
            secureStorageFailureStageValue = stage
            secureStorageFailureTypeValue = failureType
        }
    }

    private func storedUnavailableError() -> SecureStorageUnavailableError {
        let (code, stage, failureType) = withStateLock {
            (
                secureStorageFailureCodeValue,
                secureStorageFailureStageValue,
                secureStorageFailureTypeValue
            )
        }
        return SecureStorageUnavailableError(
            code: code ?? "secure_storage_unavailable",
            stage: stage ?? .runtimeOperation,
            failureType: failureType
        )
    }

    private func ensureSecureStorageReady() async throws {
        let ready = withStateLock { secureStorageStateValue == .ready }
        if ready {
            return
        }
        try await initializeSecureStorage()
    }

    private func readSecureValue(_ key: String) async throws -> String? {
        try await ensureSecureStorageReady()
        do {
            return try await keychain.string(for: key)
        } catch let error as KeychainError {
            throw SecureStorageUnavailableError(
                code: "secure_storage_unavailable",
                failureType: "keychain_\(error.status)"
            )
        }
    }

    private func writeSecureValue(key: String, value: String) async throws {
        try await ensureSecureStorageReady()
        do {
            try await keychain.set(value, for: key)
            let verified = try await keychain.string(for: key)
            guard verified == value else {
                throw SecureStorageUnavailableError(
                    code: "secure_direct_verification_failed"
                )
            }
        } catch let error as KeychainError {
            throw SecureStorageUnavailableError(
                code: "secure_storage_write_failed",
                failureType: "keychain_\(error.status)"
            )
        } catch let error as SecureStorageUnavailableError {
            throw error
        }
    }

    private func deleteSecureValue(key: String) async throws {
        try await ensureSecureStorageReady()
        do {
            try await keychain.remove(key)
            let verified = try await keychain.string(for: key)
            guard verified == nil else {
                throw SecureStorageUnavailableError(
                    code: "secure_direct_verification_failed"
                )
            }
        } catch let error as KeychainError {
            throw SecureStorageUnavailableError(
                code: "secure_storage_delete_failed",
                failureType: "keychain_\(error.status)"
            )
        } catch let error as SecureStorageUnavailableError {
            throw error
        }
    }

    private func readSensitiveValue(
        _ key: String,
        fallbackKey: String
    ) async throws -> String? {
        let secureValue = try await readSecureValue(key)
        let hasFallback = defaults.contains(fallbackKey)
        let fallbackValue = hasFallback ? defaults.string(fallbackKey) : nil
        if hasFallback && fallbackValue == nil {
            throw SecureStorageUnavailableError(code: "fallback_value_invalid")
        }

        if let secureValue {
            if hasFallback {
                if fallbackValue == secureValue {
                    removeSensitiveFallback(fallbackKey, resolveConflict: true)
                } else {
                    recordFallbackConflict(fallbackKey)
                }
            }
            return secureValue
        }

        guard hasFallback, let fallbackValue else {
            return nil
        }
        if fallbackConflictKeys().contains(fallbackKey) {
            return nil
        }
        try await writeSecureValue(key: key, value: fallbackValue)
        let verified = try await readSecureValue(key)
        guard verified == fallbackValue else {
            throw SecureStorageUnavailableError(
                code: "fallback_migration_verification_failed"
            )
        }
        removeSensitiveFallback(fallbackKey, resolveConflict: true)
        return fallbackValue
    }

    private func isPlaintextSensitivePreference(_ key: String) -> Bool {
        key == StorageKeys.siteConfigs ||
            key == StorageKeys.downloaderConfigs ||
            key == StorageKeys.legacySiteApiKeyFallback ||
            key == StorageKeys.proxyPasswordFallback ||
            key == StorageKeys.deviceIdFallback ||
            key == StorageKeys.cookieCloudUrl ||
            key == StorageKeys.cookieCloudUrlFallback ||
            key == StorageKeys.cookieCloudUuid ||
            key == StorageKeys.cookieCloudUuidFallback ||
            key == StorageKeys.cookieCloudPassword ||
            key == StorageKeys.cookieCloudPasswordFallback ||
            key == StorageKeys.cookieCloudSecretsV2Fallback ||
            key.hasPrefix("site.apiKey.fallback.") ||
            key.hasPrefix("site.cookie.fallback.") ||
            key.hasPrefix("downloader.password.fallback.") ||
            key.hasPrefix("qb.password.fallback.") ||
            key.hasPrefix("secureStorage.migrationConflict.qbPassword.") ||
            key.hasPrefix("webdav.password.fallback.")
    }

    private func fallbackConflictKeys() -> Set<String> {
        var conflicts = Set(
            defaults.stringList(StorageKeys.secureFallbackConflictsV1) ?? []
        )
        if conflicts.isEmpty,
            defaults.bool(StorageKeys.secureFallbackConflict) == true
        {
            conflicts = Set(
                defaults.allKeys.filter { isPlaintextSensitivePreference($0) }
            )
        }
        return conflicts
    }

    private func persistFallbackConflictKeys(_ conflicts: Set<String>) {
        let existing = conflicts
            .filter { defaults.contains($0) }
            .sorted()
        if existing.isEmpty {
            if defaults.contains(StorageKeys.secureFallbackConflictsV1) {
                defaults.remove(StorageKeys.secureFallbackConflictsV1)
            }
            if defaults.contains(StorageKeys.secureFallbackConflict) {
                defaults.remove(StorageKeys.secureFallbackConflict)
            }
            return
        }
        defaults.setStringList(
            existing,
            for: StorageKeys.secureFallbackConflictsV1
        )
        defaults.setBool(true, for: StorageKeys.secureFallbackConflict)
    }

    private func updateFallbackConflictKeys(
        _ update: (inout Set<String>) -> Void
    ) {
        var conflicts = fallbackConflictKeys()
        update(&conflicts)
        persistFallbackConflictKeys(conflicts)
    }

    private func recordFallbackConflict(_ key: String) {
        updateFallbackConflictKeys { _ = $0.insert(key) }
    }

    private func clearFallbackConflictMarker(_ key: String) {
        updateFallbackConflictKeys { _ = $0.remove(key) }
    }

    private func removeSensitiveFallback(
        _ fallbackKey: String,
        resolveConflict: Bool = false
    ) {
        var conflicts = fallbackConflictKeys()
        if conflicts.contains(fallbackKey) && !resolveConflict {
            return
        }
        if defaults.contains(fallbackKey) {
            defaults.remove(fallbackKey)
        }
        conflicts.remove(fallbackKey)
        persistFallbackConflictKeys(conflicts)
    }

    func hasSecureStorageFallbackConflict() async -> Bool {
        !fallbackConflictKeys().isEmpty ||
            (defaults.bool(StorageKeys.secureFallbackConflict) ?? false)
    }

    private func requirePreferenceMutation(
        _ failureCode: String,
        mutate: () -> Void,
        verify: () -> Bool
    ) throws {
        mutate()
        guard verify() else {
            throw SecureStorageUnavailableError(code: failureCode)
        }
    }

    func checkAndMigrate() async throws {
        try await performSerialized(on: .site) {
            try await self.checkAndMigrateLocked()
        }
    }

    private func checkAndMigrateLocked() async throws {
        let storedVersion = defaults.string(StorageKeys.appVersion)
        if storedVersion == nil {
            try await migrateFrom100To110()
            try requirePreferenceMutation(
                "app_version_commit_failed",
                mutate: {
                    defaults.setString(
                        Self.currentVersion,
                        for: StorageKeys.appVersion
                    )
                },
                verify: {
                    defaults.string(StorageKeys.appVersion) ==
                        Self.currentVersion
                }
            )
        } else if storedVersion != Self.currentVersion {
            if storedVersion == "1.0.0" {
                try await migrateFrom100To110()
            } else if storedVersion == "1.1.0" {
                try await migrateFrom110To120()
            }
            try requirePreferenceMutation(
                "app_version_commit_failed",
                mutate: {
                    defaults.setString(
                        Self.currentVersion,
                        for: StorageKeys.appVersion
                    )
                },
                verify: {
                    defaults.string(StorageKeys.appVersion) ==
                        Self.currentVersion
                }
            )
        }
        try await migrateKnownMobileFallbacks()
    }

    private func migrateFrom100To110() async throws {
        guard let qbConfigsStr = defaults.string(StorageKeys.legacyQbClientConfigs)
        else {
            return
        }
        do {
            guard
                let qbConfigs = (try? JSONSerialization.jsonObject(
                    with: Data(qbConfigsStr.utf8)
                )) as? [[String: Any]]
            else {
                return
            }
            var downloaderConfigs: [[String: Any]] = []
            for qbConfig in qbConfigs {
                let nested: [String: Any] = [
                    "host": qbConfig["host"] ?? "",
                    "port": qbConfig["port"] ?? 8080,
                    "username": qbConfig["username"] ?? "",
                    "useLocalRelay": qbConfig["useLocalRelay"] ?? false,
                    "version": qbConfig["version"] ?? "",
                ]
                let downloaderConfig: [String: Any] = [
                    "id": qbConfig["id"] ?? "",
                    "name": qbConfig["name"] ?? "",
                    "type": "qbittorrent",
                    "config": nested,
                ]
                downloaderConfigs.append(downloaderConfig)
                if let clientId = qbConfig["id"] as? String,
                    !clientId.isEmpty
                {
                    try await migrateLegacyQbPassword(clientId)
                    migrateLegacyQbCategories(clientId)
                    migrateLegacyQbTags(clientId)
                }
            }
            let encodedDownloaderConfigs = try jsonString(downloaderConfigs)
            try requirePreferenceMutation(
                "legacy_qb_config_verification_failed",
                mutate: {
                    defaults.setString(
                        encodedDownloaderConfigs,
                        for: StorageKeys.downloaderConfigs
                    )
                },
                verify: {
                    defaults.string(StorageKeys.downloaderConfigs) ==
                        encodedDownloaderConfigs
                }
            )
            if let defaultQbId = defaults.string(StorageKeys.legacyDefaultQbId) {
                try requirePreferenceMutation(
                    "legacy_qb_default_verification_failed",
                    mutate: {
                        defaults.setString(
                            defaultQbId,
                            for: StorageKeys.defaultDownloaderId
                        )
                    },
                    verify: {
                        defaults.string(StorageKeys.defaultDownloaderId) ==
                            defaultQbId
                    }
                )
            }
            try requirePreferenceMutation(
                "legacy_qb_config_cleanup_failed",
                mutate: {
                    defaults.remove(StorageKeys.legacyQbClientConfigs)
                },
                verify: {
                    !defaults.contains(StorageKeys.legacyQbClientConfigs)
                }
            )
            if defaults.contains(StorageKeys.legacyDefaultQbId) {
                try requirePreferenceMutation(
                    "legacy_qb_config_cleanup_failed",
                    mutate: {
                        defaults.remove(StorageKeys.legacyDefaultQbId)
                    },
                    verify: {
                        !defaults.contains(StorageKeys.legacyDefaultQbId)
                    }
                )
            }
        } catch let error as SecureStorageUnavailableError {
            throw error
        } catch {
            return
        }
    }

    private func migrateFrom110To120() async throws {}

    private func migrateLegacyQbCategories(_ clientId: String) {
        if let oldCategories = defaults.string(
            StorageKeys.legacyQbCategoriesKey(clientId)
        ) {
            defaults.setString(
                oldCategories,
                for: StorageKeys.downloaderCategoriesKey(clientId)
            )
            defaults.remove(StorageKeys.legacyQbCategoriesKey(clientId))
        }
    }

    private func migrateLegacyQbTags(_ clientId: String) {
        if let oldTags = defaults.string(
            StorageKeys.legacyQbTagsKey(clientId)
        ) {
            defaults.setString(
                oldTags,
                for: StorageKeys.downloaderTagsKey(clientId)
            )
            defaults.remove(StorageKeys.legacyQbTagsKey(clientId))
        }
    }

    private func cleanupLegacyQbPasswordSources(_ clientId: String) async throws {
        try await deleteSecureValue(
            key: StorageKeys.legacyQbPasswordKey(clientId)
        )
        removeSensitiveFallback(
            StorageKeys.legacyQbPasswordFallbackKey(clientId),
            resolveConflict: true
        )
        removeSensitiveFallback(
            StorageKeys.legacyQbPasswordConflictMarker(clientId),
            resolveConflict: true
        )
    }

    private func migrateLegacyQbPassword(_ clientId: String) async throws {
        let legacySecureKey = StorageKeys.legacyQbPasswordKey(clientId)
        let legacyFallbackKey = StorageKeys.legacyQbPasswordFallbackKey(clientId)
        let conflictMarker = StorageKeys.legacyQbPasswordConflictMarker(clientId)
        let oldSecure = try await readSecureValue(legacySecureKey)
        let hasLegacyFallback = defaults.contains(legacyFallbackKey)
        let oldFallback = hasLegacyFallback
            ? defaults.string(legacyFallbackKey)
            : nil
        if hasLegacyFallback && oldFallback == nil {
            throw SecureStorageUnavailableError(code: "fallback_value_invalid")
        }

        var candidates = Set<String>()
        if let oldSecure {
            candidates.insert(oldSecure)
        }
        if let oldFallback, !oldFallback.isEmpty {
            candidates.insert(oldFallback)
        }
        if candidates.isEmpty {
            try await cleanupLegacyQbPasswordSources(clientId)
            return
        }

        let target = try await readSensitiveValue(
            StorageKeys.downloaderPasswordKey(clientId),
            fallbackKey: StorageKeys.downloaderPasswordFallbackKey(clientId)
        )
        let hasConflict = candidates.count > 1 ||
            (target.map { !candidates.contains($0) } ?? false)
        if hasConflict {
            var conflicts = fallbackConflictKeys()
            if oldSecure != nil {
                defaults.setBool(true, for: conflictMarker)
                conflicts.insert(conflictMarker)
            }
            if hasLegacyFallback {
                conflicts.insert(legacyFallbackKey)
            }
            persistFallbackConflictKeys(conflicts)
            return
        }

        guard let candidate = candidates.first else {
            return
        }
        if target == nil && !candidate.isEmpty {
            try await saveDownloaderPasswordUnlocked(clientId, candidate)
            let verified = try await loadDownloaderPasswordUnlocked(clientId)
            guard verified == candidate else {
                throw SecureStorageUnavailableError(
                    code: "legacy_qb_password_verification_failed"
                )
            }
        }
        try await cleanupLegacyQbPasswordSources(clientId)
    }

    private func migrateKnownMobileFallbacks() async throws {
        let siteApiPrefix = "site.apiKey.fallback."
        let siteCookiePrefix = "site.cookie.fallback."
        let downloaderPrefix = "downloader.password.fallback."
        let legacyQbPrefix = "qb.password.fallback."
        let webdavPrefix = "webdav.password.fallback."
        for key in defaults.allKeys {
            if key.hasPrefix(siteApiPrefix) {
                let id = String(key.dropFirst(siteApiPrefix.count))
                if !id.isEmpty {
                    _ = try await readSensitiveValue(
                        StorageKeys.siteApiKey(id),
                        fallbackKey: key
                    )
                }
            } else if key.hasPrefix(siteCookiePrefix) {
                let id = String(key.dropFirst(siteCookiePrefix.count))
                if !id.isEmpty {
                    _ = try await readSensitiveValue(
                        StorageKeys.siteCookie(id),
                        fallbackKey: key
                    )
                }
            } else if key.hasPrefix(downloaderPrefix) {
                let id = String(key.dropFirst(downloaderPrefix.count))
                if !id.isEmpty {
                    _ = try await readSensitiveValue(
                        StorageKeys.downloaderPasswordKey(id),
                        fallbackKey: key
                    )
                }
            } else if key.hasPrefix(legacyQbPrefix) {
                let id = String(key.dropFirst(legacyQbPrefix.count))
                if !id.isEmpty {
                    try await migrateLegacyQbPassword(id)
                }
            } else if key.hasPrefix(webdavPrefix) {
                let id = String(key.dropFirst(webdavPrefix.count))
                if !id.isEmpty {
                    _ = try await readSensitiveValue(
                        StorageKeys.webdavPassword(id),
                        fallbackKey: key
                    )
                }
            }
        }
        if defaults.contains(StorageKeys.legacySiteApiKeyFallback) {
            _ = try await readSensitiveValue(
                StorageKeys.legacySiteApiKey,
                fallbackKey: StorageKeys.legacySiteApiKeyFallback
            )
        }
        if defaults.contains(StorageKeys.proxyPasswordFallback) {
            _ = try await readSensitiveValue(
                StorageKeys.proxyPassword,
                fallbackKey: StorageKeys.proxyPasswordFallback
            )
        }
        if defaults.contains(StorageKeys.deviceIdFallback) {
            _ = try await readSensitiveValue(
                StorageKeys.deviceId,
                fallbackKey: StorageKeys.deviceIdFallback
            )
        }
        try await migrateEmbeddedDownloaderPasswords()
        _ = try await loadCookieCloudSecretsUnlocked()
    }

    private func migrateEmbeddedDownloaderPasswords() async throws {
        guard
            let encoded = defaults.string(StorageKeys.downloaderConfigs),
            !encoded.isEmpty
        else {
            return
        }
        guard
            let decoded = (try? JSONSerialization.jsonObject(
                with: Data(encoded.utf8)
            )) as? [Any]
        else {
            throw SecureStorageUnavailableError(
                code: "embedded_downloader_password_config_invalid"
            )
        }

        var changed = false
        var hasConflict = false
        var sanitizedConfigs: [[String: Any]] = []
        for value in decoded {
            guard let dict = value as? [String: Any] else {
                throw SecureStorageUnavailableError(
                    code: "embedded_downloader_password_config_invalid"
                )
            }
            var sanitized = dict
            let nested = dict["config"] as? [String: Any]
            let nestedPassword = unwrapJSONNull(nested?["password"])
            let topLevelPassword = unwrapJSONNull(dict["password"])
            let hasPasswordField =
                nested?.keys.contains("password") ?? false ||
                dict.keys.contains("password")
            let nestedPasswordString = nestedPassword as? String
            let topLevelPasswordString = topLevelPassword as? String
            let nestedInvalidType =
                nestedPassword != nil && nestedPasswordString == nil
            let topLevelInvalidType =
                topLevelPassword != nil && topLevelPasswordString == nil
            let passwordsDisagree: Bool = {
                guard
                    let nestedPasswordString,
                    !nestedPasswordString.isEmpty,
                    let topLevelPasswordString,
                    !topLevelPasswordString.isEmpty
                else {
                    return false
                }
                return nestedPasswordString != topLevelPasswordString
            }()
            if nestedInvalidType || topLevelInvalidType || passwordsDisagree {
                hasConflict = true
                sanitizedConfigs.append(sanitized)
                continue
            }

            var password: String?
            if let nestedPasswordString, !nestedPasswordString.isEmpty {
                password = nestedPasswordString
            } else if let topLevelPasswordString,
                !topLevelPasswordString.isEmpty
            {
                password = topLevelPasswordString
            }

            if let password {
                guard let id = dict["id"] as? String, !id.isEmpty else {
                    hasConflict = true
                    sanitizedConfigs.append(sanitized)
                    continue
                }
                let securePassword = try await readSensitiveValue(
                    StorageKeys.downloaderPasswordKey(id),
                    fallbackKey: StorageKeys.downloaderPasswordFallbackKey(id)
                )
                if securePassword == nil {
                    try await saveDownloaderPasswordUnlocked(id, password)
                    let verified = try await loadDownloaderPasswordUnlocked(id)
                    guard verified == password else {
                        throw SecureStorageUnavailableError(
                            code: "embedded_downloader_password_verification_failed"
                        )
                    }
                } else if securePassword != password {
                    hasConflict = true
                    sanitizedConfigs.append(sanitized)
                    continue
                }
            }

            if hasPasswordField {
                sanitized.removeValue(forKey: "password")
                if var nested {
                    nested.removeValue(forKey: "password")
                    sanitized["config"] = nested
                }
                changed = true
            }
            sanitizedConfigs.append(sanitized)
        }

        if changed {
            let sanitizedEncoded = try jsonString(sanitizedConfigs)
            try requirePreferenceMutation(
                "embedded_downloader_password_cleanup_failed",
                mutate: {
                    defaults.setString(
                        sanitizedEncoded,
                        for: StorageKeys.downloaderConfigs
                    )
                },
                verify: {
                    defaults.string(StorageKeys.downloaderConfigs) ==
                        sanitizedEncoded
                }
            )
        }

        updateFallbackConflictKeys { conflicts in
            if hasConflict {
                conflicts.insert(StorageKeys.downloaderConfigs)
            } else {
                conflicts.remove(StorageKeys.downloaderConfigs)
            }
        }
    }

    func loadSiteConfigs<Config: SiteConfigStorable>(
        includeApiKeys: Bool = false
    ) async throws -> [Config] {
        try await performSerialized(on: .site) { () async throws -> [Config] in
            try await self.loadSiteConfigsUnlocked(
                includeApiKeys: includeApiKeys
            )
        }
    }

    private func loadSiteConfigsUnlocked<Config: SiteConfigStorable>(
        includeApiKeys: Bool
    ) async throws -> [Config] {
        try await ensureSecureStorageReady()
        do {
            return try await loadSiteConfigsBody(includeApiKeys: includeApiKeys)
        } catch let error as SecureStorageUnavailableError {
            throw error
        } catch {
            throw StorageError.siteConfigLoadFailed
        }
    }

    private func loadSiteConfigsBody<Config: SiteConfigStorable>(
        includeApiKeys: Bool
    ) async throws -> [Config] {
        guard let raw = defaults.string(StorageKeys.siteConfigs) else {
            withStateLock {
                siteConfigsCacheValue = nil
                siteConfigsCacheDirty = true
                siteConfigsCacheNeedsUpdate = false
            }
            return []
        }
        guard let jsonList = (try? JSONSerialization.jsonObject(
            with: Data(raw.utf8)
        )) as? [[String: Any]] else {
            throw StorageError.siteConfigLoadFailed
        }

        var baseConfigs: [Config] = []
        var hasUpdates = false
        var hasBlockingSiteConfigConflict = fallbackConflictKeys().contains(
            StorageKeys.siteConfigs
        )

        let cached = withStateLock {
            siteConfigsCacheDirty ? nil : siteConfigsCacheValue
        }
        if let cached {
            baseConfigs = try cached.map {
                try decodeDictionary(Config.self, from: $0)
            }
            hasUpdates = withStateLock { siteConfigsCacheNeedsUpdate }
        } else {
            var migratedList = jsonList
            var sanitizedLegacyCookie = false
            var sawLegacyCookie = false
            var legacyCookieConflict = false
            var parsed: [Config] = []
            for index in jsonList.indices {
                var config = try decodeDictionary(
                    Config.self,
                    from: jsonList[index]
                )
                if let plainCookie = config.cookie, !plainCookie.isEmpty {
                    sawLegacyCookie = true
                    var secureCookie = try await readSensitiveValue(
                        StorageKeys.siteCookie(config.id),
                        fallbackKey: StorageKeys.siteCookieFallback(config.id)
                    )
                    if secureCookie == nil {
                        try await writeSecureValue(
                            key: StorageKeys.siteCookie(config.id),
                            value: plainCookie
                        )
                        secureCookie = try await readSecureValue(
                            StorageKeys.siteCookie(config.id)
                        )
                        guard secureCookie == plainCookie else {
                            throw SecureStorageUnavailableError(
                                code: "legacy_site_cookie_verification_failed"
                            )
                        }
                    }
                    if secureCookie == plainCookie {
                        migratedList[index]["cookie"] = NSNull()
                        sanitizedLegacyCookie = true
                    } else {
                        legacyCookieConflict = true
                    }
                    if let secureCookie {
                        withStateLock {
                            siteCookiesCache[config.id] = .some(secureCookie)
                        }
                    }
                    config.cookie = nil
                }
                parsed.append(config)
            }

            if sanitizedLegacyCookie {
                let migratedEncoded = try jsonString(migratedList)
                try requirePreferenceMutation(
                    "legacy_site_cookie_cleanup_failed",
                    mutate: {
                        defaults.setString(
                            migratedEncoded,
                            for: StorageKeys.siteConfigs
                        )
                    },
                    verify: {
                        defaults.string(StorageKeys.siteConfigs) ==
                            migratedEncoded
                    }
                )
            }
            updateFallbackConflictKeys { conflicts in
                if legacyCookieConflict {
                    conflicts.insert(StorageKeys.siteConfigs)
                } else if sawLegacyCookie ||
                    conflicts.contains(StorageKeys.siteConfigs)
                {
                    conflicts.remove(StorageKeys.siteConfigs)
                }
            }
            hasBlockingSiteConfigConflict = legacyCookieConflict

            baseConfigs = parsed
            hasUpdates = parsed.contains { $0.needsConfigUpdate }
            withStateLock {
                siteConfigsCacheValue = migratedList
                siteConfigsCacheDirty = false
                siteConfigsCacheNeedsUpdate = hasUpdates
            }
        }

        var configs: [Config] = []
        for var config in baseConfigs {
            let cookie: String?
            if let cachedCookie = withStateLock({
                siteCookiesCache[config.id]
            }) {
                cookie = cachedCookie
            } else {
                cookie = try await readSensitiveValue(
                    StorageKeys.siteCookie(config.id),
                    fallbackKey: StorageKeys.siteCookieFallback(config.id)
                )
                withStateLock {
                    siteCookiesCache[config.id] = .some(cookie)
                }
            }
            if includeApiKeys {
                let apiKey: String?
                if let cachedKey = withStateLock({
                    siteApiKeysCache[config.id]
                }) {
                    apiKey = cachedKey
                } else {
                    apiKey = try await readSensitiveValue(
                        StorageKeys.siteApiKey(config.id),
                        fallbackKey: StorageKeys.siteApiKeyFallback(config.id)
                    )
                    withStateLock {
                        siteApiKeysCache[config.id] = .some(apiKey)
                    }
                }
                config.apiKey = apiKey
            }
            config.cookie = cookie
            configs.append(config)
        }

        if hasUpdates && includeApiKeys && !hasBlockingSiteConfigConflict {
            try await saveSiteConfigsUnlocked(
                configs,
                resolveFallbackConflicts: false
            )
        } else if hasUpdates,
            !includeApiKeys,
            !hasBlockingSiteConfigConflict
        {
            withStateLock { hasPendingConfigUpdates = true }
        }

        return configs
    }

    private func plainSiteConfigList(
        _ configs: [any SiteConfigStorable]
    ) throws -> [[String: Any]] {
        var list: [[String: Any]] = []
        for config in configs {
            var dictionary = try encodeToDictionary(config)
            dictionary["apiKey"] = NSNull()
            dictionary["cookie"] = NSNull()
            list.append(dictionary)
        }
        try validatePlainSiteConfigList(list)
        return list
    }

    private func validatePlainSiteConfigList(_ list: [[String: Any]]) throws {
        for dictionary in list {
            let apiKey = unwrapJSONNull(dictionary["apiKey"])
            let cookie = unwrapJSONNull(dictionary["cookie"])
            if apiKey != nil || cookie != nil {
                throw StorageError.invalidPayload(
                    "invalid_plain_site_config_payload"
                )
            }
        }
    }

    private func persistedPlainSiteIds() throws -> Set<String> {
        guard let raw = defaults.string(StorageKeys.siteConfigs) else {
            return []
        }
        guard let decoded = (try? JSONSerialization.jsonObject(
            with: Data(raw.utf8)
        )) as? [Any] else {
            throw StorageError.siteConfigLoadFailed
        }
        var ids = Set<String>()
        for value in decoded {
            guard let dictionary = value as? [String: Any],
                let id = dictionary["id"] as? String,
                !id.isEmpty
            else {
                throw StorageError.siteConfigLoadFailed
            }
            ids.insert(id)
        }
        return ids
    }

    private func persistPlainSiteConfigList(_ list: [[String: Any]]) throws {
        try validatePlainSiteConfigList(list)
        let encoded = try jsonString(list)
        try requirePreferenceMutation(
            "plain_site_config_commit_failed",
            mutate: {
                defaults.setString(encoded, for: StorageKeys.siteConfigs)
            },
            verify: {
                defaults.string(StorageKeys.siteConfigs) == encoded
            }
        )
        withStateLock {
            siteConfigsCacheValue = list
            siteConfigsCacheDirty = false
            siteConfigsCacheNeedsUpdate = false
            siteApiKeysCache.removeAll()
            siteCookiesCache.removeAll()
        }
    }

    private func saveSiteConfigsUnlocked(
        _ configs: [any SiteConfigStorable],
        resolveFallbackConflicts: Bool
    ) async throws {
        try await ensureSecureStorageReady()
        let plainList = try plainSiteConfigList(configs)
        let incomingSiteIds = Set(configs.map { $0.id })
        let removedSiteIds = try persistedPlainSiteIds()
            .subtracting(incomingSiteIds)

        var fallbackKeys: [(key: String, resolve: Bool)] = []
        for config in configs {
            if let apiKey = config.apiKey {
                let key = StorageKeys.siteApiKey(config.id)
                if apiKey.isEmpty {
                    try await deleteSecureValue(key: key)
                } else {
                    try await writeSecureValue(key: key, value: apiKey)
                }
                fallbackKeys.append(
                    (StorageKeys.siteApiKeyFallback(config.id), false)
                )
            }
            if let cookie = config.cookie {
                let key = StorageKeys.siteCookie(config.id)
                if cookie.isEmpty {
                    try await deleteSecureValue(key: key)
                } else {
                    try await writeSecureValue(key: key, value: cookie)
                }
                fallbackKeys.append(
                    (StorageKeys.siteCookieFallback(config.id), false)
                )
            }
        }
        for siteId in removedSiteIds {
            try await deleteSecureValue(key: StorageKeys.siteApiKey(siteId))
            try await deleteSecureValue(key: StorageKeys.siteCookie(siteId))
            fallbackKeys.append(
                (StorageKeys.siteApiKeyFallback(siteId), true)
            )
            fallbackKeys.append(
                (StorageKeys.siteCookieFallback(siteId), true)
            )
        }

        try persistPlainSiteConfigList(plainList)

        for entry in fallbackKeys {
            removeSensitiveFallback(
                entry.key,
                resolveConflict: entry.resolve || resolveFallbackConflicts
            )
        }
        if resolveFallbackConflicts {
            clearFallbackConflictMarker(StorageKeys.siteConfigs)
        }
    }

    func saveSiteConfigs(
        _ configs: [any SiteConfigStorable],
        resolveFallbackConflicts: Bool = false
    ) async throws {
        try await performSerialized(on: .site) {
            try await self.saveSiteConfigsUnlocked(
                configs,
                resolveFallbackConflicts: resolveFallbackConflicts
            )
        }
    }

    func addSiteConfig<Config: SiteConfigStorable>(
        _ config: Config
    ) async throws {
        try await performSerialized(on: .site) {
            var configs: [Config] = try await self.loadSiteConfigsUnlocked(
                includeApiKeys: false
            )
            configs = configs.map { item in
                var copy = item
                copy.apiKey = nil
                copy.cookie = nil
                return copy
            }
            configs.append(config)
            try await self.saveSiteConfigsUnlocked(
                configs,
                resolveFallbackConflicts: true
            )
        }
    }

    func updateSiteConfig<Config: SiteConfigStorable>(
        _ config: Config
    ) async throws {
        try await performSerialized(on: .site) {
            var configs: [Config] = try await self.loadSiteConfigsUnlocked(
                includeApiKeys: false
            )
            if let index = configs.firstIndex(where: { $0.id == config.id }) {
                configs = configs.map { item in
                    var copy = item
                    copy.apiKey = nil
                    copy.cookie = nil
                    return copy
                }
                configs[index] = config
                try await self.saveSiteConfigsUnlocked(
                    configs,
                    resolveFallbackConflicts: true
                )
            }
        }
    }

    func deleteSiteConfig(_ siteId: String) async throws {
        try await performSerialized(on: .site) {
            var remaining: [[String: Any]] = []
            if let raw = self.defaults.string(StorageKeys.siteConfigs) {
                guard let list = (try? JSONSerialization.jsonObject(
                    with: Data(raw.utf8)
                )) as? [[String: Any]] else {
                    throw StorageError.siteConfigLoadFailed
                }
                remaining = list.filter { ($0["id"] as? String) != siteId }
            }
            try await self.deleteSecureValue(
                key: StorageKeys.siteApiKey(siteId)
            )
            try await self.deleteSecureValue(
                key: StorageKeys.siteCookie(siteId)
            )
            try self.persistPlainSiteConfigList(remaining)
            self.removeSensitiveFallback(
                StorageKeys.siteApiKeyFallback(siteId),
                resolveConflict: true
            )
            self.removeSensitiveFallback(
                StorageKeys.siteCookieFallback(siteId),
                resolveConflict: true
            )
            if await self.getActiveSiteId() == siteId {
                await self.setActiveSiteId(nil)
            }
        }
    }

    func updateSiteConfigsAtomically<
        Config: SiteConfigStorable,
        Result
    >(
        includeApiKeys: Bool = false,
        resolveFallbackConflicts: Bool = false,
        update: @escaping ([Config]) async throws -> (
            configs: [Config], result: Result
        )
    ) async throws -> Result {
        try await performSerialized(on: .site) { () async throws -> Result in
            let current: [Config] = try await self.loadSiteConfigsUnlocked(
                includeApiKeys: includeApiKeys
            )
            let change = try await update(current)
            try await self.saveSiteConfigsUnlocked(
                change.configs,
                resolveFallbackConflicts: resolveFallbackConflicts
            )
            return change.result
        }
    }

    func setActiveSiteId(_ siteId: String?) async {
        defaults.setString(siteId, for: StorageKeys.activeSiteId)
    }

    func getActiveSiteId() async -> String? {
        defaults.string(StorageKeys.activeSiteId)
    }

    func getActiveSiteConfig<Config: SiteConfigStorable>() async throws
        -> Config?
    {
        try await performSerialized(on: .site) { () async throws -> Config? in
            guard let activeSiteId = await self.getActiveSiteId() else {
                return nil
            }
            do {
                let configs: [Config] = try await self.loadSiteConfigsUnlocked(
                    includeApiKeys: false
                )
                guard let base = configs.first(where: {
                    $0.id == activeSiteId
                }) else {
                    return nil
                }
                var result = base
                result.apiKey = try await self.readSensitiveValue(
                    StorageKeys.siteApiKey(activeSiteId),
                    fallbackKey: StorageKeys.siteApiKeyFallback(activeSiteId)
                )
                result.cookie = try await self.readSensitiveValue(
                    StorageKeys.siteCookie(activeSiteId),
                    fallbackKey: StorageKeys.siteCookieFallback(activeSiteId)
                )
                return result
            } catch let error as SecureStorageUnavailableError {
                throw error
            } catch {
                return nil
            }
        }
    }

    func siteConfigsCache<Config: SiteConfigStorable>() -> [Config]? {
        guard let dictionaries = withStateLock({ siteConfigsCacheValue })
        else {
            return nil
        }
        return try? dictionaries.map {
            try decodeDictionary(Config.self, from: $0)
        }
    }

    func persistPendingConfigUpdates<Config: SiteConfigStorable>(
        as type: Config.Type
    ) async throws {
        let pending = withStateLock { hasPendingConfigUpdates }
        guard pending else {
            return
        }
        let _: [Config] = try await loadSiteConfigs(includeApiKeys: true)
        withStateLock { hasPendingConfigUpdates = false }
    }

    func saveSite<Config: SiteConfigStorable>(_ config: Config) async throws {
        try await performSerialized(on: .sensitive) {
            var plain = try encodeToDictionary(config)
            plain["apiKey"] = NSNull()
            plain["cookie"] = NSNull()

            if let apiKey = config.apiKey, !apiKey.isEmpty {
                try await self.writeSecureValue(
                    key: StorageKeys.legacySiteApiKey,
                    value: apiKey
                )
            } else {
                try await self.deleteSecureValue(
                    key: StorageKeys.legacySiteApiKey
                )
            }
            self.removeSensitiveFallback(
                StorageKeys.legacySiteApiKeyFallback
            )

            if let cookie = config.cookie, !cookie.isEmpty {
                try await self.writeSecureValue(
                    key: StorageKeys.siteCookie(config.id),
                    value: cookie
                )
            } else {
                try await self.deleteSecureValue(
                    key: StorageKeys.siteCookie(config.id)
                )
            }
            self.removeSensitiveFallback(
                StorageKeys.siteCookieFallback(config.id)
            )

            let encodedPlain = try jsonString(plain)
            try self.requirePreferenceMutation(
                "plain_site_config_commit_failed",
                mutate: {
                    self.defaults.setString(
                        encodedPlain,
                        for: StorageKeys.siteConfig
                    )
                },
                verify: {
                    self.defaults.string(StorageKeys.siteConfig) ==
                        encodedPlain
                }
            )
        }
    }

    func loadSite<Config: SiteConfigStorable>() async throws -> Config? {
        try await performSerialized(on: .sensitive) { () async throws -> Config? in
            guard let raw = self.defaults.string(StorageKeys.siteConfig) else {
                return nil
            }
            guard let dictionary = (try? JSONSerialization.jsonObject(
                with: Data(raw.utf8)
            )) as? [String: Any] else {
                throw StorageError.siteConfigLoadFailed
            }
            var base: Config
            do {
                base = try decodeDictionary(Config.self, from: dictionary)
            } catch {
                throw StorageError.siteConfigLoadFailed
            }
            base.apiKey = try await self.readSensitiveValue(
                StorageKeys.legacySiteApiKey,
                fallbackKey: StorageKeys.legacySiteApiKeyFallback
            )
            base.cookie = try await self.readSensitiveValue(
                StorageKeys.siteCookie(base.id),
                fallbackKey: StorageKeys.siteCookieFallback(base.id)
            )
            return base
        }
    }

    private func parseCookieCloudBundle(
        _ encoded: String
    ) throws -> CookieCloudSecrets {
        guard let dictionary = (try? JSONSerialization.jsonObject(
            with: Data(encoded.utf8)
        )) as? [String: Any],
            let url = dictionary["url"] as? String,
            let uuid = dictionary["uuid"] as? String,
            let password = dictionary["password"] as? String
        else {
            throw SecureStorageUnavailableError(
                code: "cookie_cloud_bundle_invalid"
            )
        }
        return CookieCloudSecrets(url: url, uuid: uuid, password: password)
    }

    private func hasLegacyCookieCloudSecrets() async throws -> Bool {
        let preferenceKeys = [
            StorageKeys.cookieCloudUrl,
            StorageKeys.cookieCloudUrlFallback,
            StorageKeys.cookieCloudUuid,
            StorageKeys.cookieCloudUuidFallback,
            StorageKeys.cookieCloudPassword,
            StorageKeys.cookieCloudPasswordFallback,
        ]
        if preferenceKeys.contains(where: { defaults.contains($0) }) {
            return true
        }
        if try await readSecureValue(StorageKeys.cookieCloudUrl) != nil {
            return true
        }
        if try await readSecureValue(StorageKeys.cookieCloudUuid) != nil {
            return true
        }
        return try await readSecureValue(StorageKeys.cookieCloudPassword) != nil
    }

    private func setCookieCloudLegacyCleanupPending(_ pending: Bool) {
        if pending {
            if defaults.bool(StorageKeys.cookieCloudSecretsV2PendingCleanup) ==
                true
            {
                return
            }
            defaults.setBool(
                true,
                for: StorageKeys.cookieCloudSecretsV2PendingCleanup
            )
            return
        }
        guard defaults.contains(StorageKeys.cookieCloudSecretsV2PendingCleanup)
        else {
            return
        }
        defaults.remove(StorageKeys.cookieCloudSecretsV2PendingCleanup)
    }

    private func cleanupLegacyCookieCloudSecrets(
        resolveConflicts: Bool
    ) async throws {
        let legacyPreferenceKeys = [
            StorageKeys.cookieCloudUrl,
            StorageKeys.cookieCloudUrlFallback,
            StorageKeys.cookieCloudUuid,
            StorageKeys.cookieCloudUuidFallback,
            StorageKeys.cookieCloudPassword,
            StorageKeys.cookieCloudPasswordFallback,
        ]
        let conflicts = fallbackConflictKeys()
        if !resolveConflicts &&
            legacyPreferenceKeys.contains(where: { conflicts.contains($0) })
        {
            return
        }

        try await deleteSecureValue(key: StorageKeys.cookieCloudUrl)
        try await deleteSecureValue(key: StorageKeys.cookieCloudUuid)
        try await deleteSecureValue(key: StorageKeys.cookieCloudPassword)

        for key in legacyPreferenceKeys {
            removeSensitiveFallback(key, resolveConflict: resolveConflicts)
        }
        setCookieCloudLegacyCleanupPending(false)
        updateFallbackConflictKeys { _ = $0 }
    }

    private func loadLegacyCookieCloudValue(
        key: String,
        fallbackKey: String
    ) async throws -> (value: String, hasConflict: Bool) {
        let plaintextValue = defaults.string(key)
        let fallbackValue = defaults.string(fallbackKey)
        var secureValue = try await readSensitiveValue(
            key,
            fallbackKey: fallbackKey
        )
        var hasConflict = false

        if let secureValueCurrent = secureValue {
            if let fallbackValue, !fallbackValue.isEmpty,
                fallbackValue != secureValueCurrent
            {
                hasConflict = true
            }
            if let plaintextValue, !plaintextValue.isEmpty {
                if plaintextValue == secureValueCurrent {
                    removeSensitiveFallback(key, resolveConflict: true)
                } else {
                    hasConflict = true
                    recordFallbackConflict(key)
                }
            }
        } else if let plaintextValue, !plaintextValue.isEmpty {
            try await writeSecureValue(key: key, value: plaintextValue)
            let verified = try await readSensitiveValue(
                key,
                fallbackKey: fallbackKey
            )
            guard verified == plaintextValue else {
                throw SecureStorageUnavailableError(
                    code: "fallback_migration_verification_failed"
                )
            }
            secureValue = plaintextValue
            removeSensitiveFallback(key, resolveConflict: true)
        }
        return (secureValue ?? "", hasConflict)
    }

    private func loadLegacyCookieCloudSecrets() async throws
        -> LegacyCookieCloudSecrets
    {
        let url = try await loadLegacyCookieCloudValue(
            key: StorageKeys.cookieCloudUrl,
            fallbackKey: StorageKeys.cookieCloudUrlFallback
        )
        let uuid = try await loadLegacyCookieCloudValue(
            key: StorageKeys.cookieCloudUuid,
            fallbackKey: StorageKeys.cookieCloudUuidFallback
        )
        let password = try await loadLegacyCookieCloudValue(
            key: StorageKeys.cookieCloudPassword,
            fallbackKey: StorageKeys.cookieCloudPasswordFallback
        )
        return LegacyCookieCloudSecrets(
            secrets: CookieCloudSecrets(
                url: url.value,
                uuid: uuid.value,
                password: password.value
            ),
            hasConflict: url.hasConflict || uuid.hasConflict || password.hasConflict
        )
    }

    private func saveCookieCloudSecretsUnlocked(
        _ secrets: CookieCloudSecrets,
        scheduleLegacyCleanup: Bool = true,
        resolveLegacyConflicts: Bool = false,
        companionConfig: CookieCloudConfig? = nil
    ) async throws {
        let encoded = try jsonString([
            "url": secrets.url,
            "uuid": secrets.uuid,
            "password": secrets.password,
        ])
        try await writeSecureValue(
            key: StorageKeys.cookieCloudSecretsV2,
            value: encoded
        )
        if let companionConfig {
            try persistCookieCloudPreferences(companionConfig)
        }
        removeSensitiveFallback(
            StorageKeys.cookieCloudSecretsV2Fallback,
            resolveConflict: resolveLegacyConflicts
        )
        let verified = try await readSensitiveValue(
            StorageKeys.cookieCloudSecretsV2,
            fallbackKey: StorageKeys.cookieCloudSecretsV2Fallback
        )
        guard verified == encoded else {
            throw SecureStorageUnavailableError(
                code: "cookie_cloud_bundle_verification_failed"
            )
        }
        setCookieCloudLegacyCleanupPending(scheduleLegacyCleanup)
        withStateLock { cookieCloudBundleCreatedThisRun = true }
        if resolveLegacyConflicts {
            try await cleanupLegacyCookieCloudSecrets(resolveConflicts: true)
        }
    }

    private func loadCookieCloudSecretsUnlocked() async throws
        -> CookieCloudSecrets
    {
        if let encoded = try await readSensitiveValue(
            StorageKeys.cookieCloudSecretsV2,
            fallbackKey: StorageKeys.cookieCloudSecretsV2Fallback
        ) {
            let secrets = try parseCookieCloudBundle(encoded)
            var shouldCleanup =
                defaults.bool(StorageKeys.cookieCloudSecretsV2PendingCleanup) ??
                false
            let bundleCreatedThisRun = withStateLock {
                cookieCloudBundleCreatedThisRun
            }
            if !shouldCleanup, !bundleCreatedThisRun,
                fallbackConflictKeys().isEmpty
            {
                shouldCleanup = try await hasLegacyCookieCloudSecrets()
            }
            if shouldCleanup, !bundleCreatedThisRun {
                try await cleanupLegacyCookieCloudSecrets(
                    resolveConflicts: false
                )
            }
            return secrets
        }

        let legacy = try await loadLegacyCookieCloudSecrets()
        if !legacy.secrets.isEmpty {
            try await saveCookieCloudSecretsUnlocked(
                legacy.secrets,
                scheduleLegacyCleanup: !legacy.hasConflict
            )
        }
        return legacy.secrets
    }

    private func loadCookieCloudSecrets() async throws -> CookieCloudSecrets {
        try await performSerialized(on: .sensitive) {
            try await self.loadCookieCloudSecretsUnlocked()
        }
    }

    func loadCookieCloudConfig() async throws -> CookieCloudConfig {
        try await performSerialized(on: .sensitive) { () async throws -> CookieCloudConfig in
            let lastSyncAtRaw = self.defaults.string(
                StorageKeys.cookieCloudLastSyncAt
            )
            let secrets = try await self.loadCookieCloudSecretsUnlocked()
            return CookieCloudConfig(
                url: secrets.url,
                uuid: secrets.uuid,
                password: secrets.password,
                autoSyncEnabled:
                    self.defaults.bool(StorageKeys.cookieCloudAutoSyncEnabled) ??
                    false,
                syncIntervalMinutes:
                    self.defaults.int(
                        StorageKeys.cookieCloudSyncIntervalMinutes
                    ) ?? 360,
                lastSyncAt: lastSyncAtRaw.flatMap {
                    ISO8601Codec.date(from: $0)
                },
                lastSyncSummary:
                    self.defaults.string(
                        StorageKeys.cookieCloudLastSyncSummary
                    ) ?? ""
            )
        }
    }

    func saveCookieCloudConfig(_ config: CookieCloudConfig) async throws {
        try await performSerialized(on: .sensitive) {
            try await self.saveCookieCloudSecretsUnlocked(
                CookieCloudSecrets(
                    url: config.url.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    uuid: config.uuid.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    password: config.password
                ),
                resolveLegacyConflicts: true,
                companionConfig: config
            )
        }
    }

    func saveCookieCloudUrl(_ url: String) async throws {
        try await performSerialized(on: .sensitive) {
            let current = try await self.loadCookieCloudSecretsUnlocked()
            try await self.saveCookieCloudSecretsUnlocked(
                CookieCloudSecrets(
                    url: url,
                    uuid: current.uuid,
                    password: current.password
                ),
                resolveLegacyConflicts: true
            )
        }
    }

    func saveCookieCloudUuid(_ uuid: String) async throws {
        try await performSerialized(on: .sensitive) {
            let current = try await self.loadCookieCloudSecretsUnlocked()
            try await self.saveCookieCloudSecretsUnlocked(
                CookieCloudSecrets(
                    url: current.url,
                    uuid: uuid,
                    password: current.password
                ),
                resolveLegacyConflicts: true
            )
        }
    }

    func saveCookieCloudPassword(_ password: String) async throws {
        try await performSerialized(on: .sensitive) {
            let current = try await self.loadCookieCloudSecretsUnlocked()
            try await self.saveCookieCloudSecretsUnlocked(
                CookieCloudSecrets(
                    url: current.url,
                    uuid: current.uuid,
                    password: password
                ),
                resolveLegacyConflicts: true
            )
        }
    }

    func loadCookieCloudUrl() async throws -> String {
        try await loadCookieCloudSecrets().url
    }

    func loadCookieCloudUuid() async throws -> String {
        try await loadCookieCloudSecrets().uuid
    }

    func loadCookieCloudPassword() async throws -> String {
        try await loadCookieCloudSecrets().password
    }

    func saveCookieCloudLastSync(syncedAt: Date, summary: String) async {
        withStateLock {
            defaults.setString(
                ISO8601Codec.string(from: syncedAt),
                for: StorageKeys.cookieCloudLastSyncAt
            )
            defaults.setString(
                summary,
                for: StorageKeys.cookieCloudLastSyncSummary
            )
        }
    }

    private func encodeCookieCloudPreferences(
        _ config: CookieCloudConfig
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "autoSyncEnabled": config.autoSyncEnabled,
            "syncIntervalMinutes": config.syncIntervalMinutes,
            "lastSyncSummary": config.lastSyncSummary,
        ]
        if let lastSyncAt = config.lastSyncAt {
            payload["lastSyncAt"] = ISO8601Codec.string(from: lastSyncAt)
        } else {
            payload["lastSyncAt"] = NSNull()
        }
        return payload
    }

    private func validateCookieCloudPreferencesPayload(
        _ payload: [String: Any]
    ) throws {
        let lastSyncAt = unwrapJSONNull(payload["lastSyncAt"])
        if !isBooleanValue(payload["autoSyncEnabled"]) ||
            !isIntegerValue(payload["syncIntervalMinutes"]) ||
            !(payload["lastSyncSummary"] is String) ||
            !(lastSyncAt == nil || lastSyncAt is String)
        {
            throw StorageError.invalidPayload(
                "invalid_cookie_cloud_preferences_payload"
            )
        }
    }

    private func persistCookieCloudPreferences(
        _ config: CookieCloudConfig
    ) throws {
        let payload = encodeCookieCloudPreferences(config)
        try validateCookieCloudPreferencesPayload(payload)
        try requirePreferenceMutation(
            "cookie_cloud_preferences_commit_failed",
            mutate: {
                defaults.setBool(
                    config.autoSyncEnabled,
                    for: StorageKeys.cookieCloudAutoSyncEnabled
                )
                defaults.setInt(
                    config.syncIntervalMinutes,
                    for: StorageKeys.cookieCloudSyncIntervalMinutes
                )
                if let lastSyncAt = config.lastSyncAt {
                    defaults.setString(
                        ISO8601Codec.string(from: lastSyncAt),
                        for: StorageKeys.cookieCloudLastSyncAt
                    )
                } else {
                    defaults.remove(StorageKeys.cookieCloudLastSyncAt)
                }
                defaults.setString(
                    config.lastSyncSummary,
                    for: StorageKeys.cookieCloudLastSyncSummary
                )
            },
            verify: {
                defaults.bool(StorageKeys.cookieCloudAutoSyncEnabled) ==
                    config.autoSyncEnabled &&
                    defaults.int(
                        StorageKeys.cookieCloudSyncIntervalMinutes
                    ) == config.syncIntervalMinutes &&
                    defaults.string(StorageKeys.cookieCloudLastSyncSummary) ==
                    config.lastSyncSummary &&
                    defaults.string(StorageKeys.cookieCloudLastSyncAt) ==
                    config.lastSyncAt.map {
                        ISO8601Codec.string(from: $0)
                    }
            }
        )
    }

    func saveThemeMode(_ mode: String) async {
        defaults.setString(mode, for: StorageKeys.themeMode)
    }

    func loadThemeMode() async -> String? {
        defaults.string(StorageKeys.themeMode)
    }

    func saveUseDynamicColor(_ useDynamic: Bool) async {
        defaults.setBool(useDynamic, for: StorageKeys.themeUseDynamic)
    }

    func loadUseDynamicColor() async -> Bool? {
        defaults.bool(StorageKeys.themeUseDynamic)
    }

    func saveSeedColor(_ argb: Int) async {
        defaults.setInt(argb, for: StorageKeys.themeSeedColor)
    }

    func loadSeedColor() async -> Int? {
        defaults.int(StorageKeys.themeSeedColor)
    }

    func saveAutoLoadImages(_ autoLoad: Bool) async {
        defaults.setBool(autoLoad, for: StorageKeys.autoLoadImages)
    }

    func loadAutoLoadImages() async -> Bool {
        defaults.bool(StorageKeys.autoLoadImages) ?? true
    }

    func saveShowCoverImages(_ show: Bool) async {
        defaults.setBool(show, for: StorageKeys.showCoverImages)
    }

    func loadShowCoverImages() async -> Bool {
        defaults.bool(StorageKeys.showCoverImages) ?? true
    }

    func saveLogToFileEnabled(_ enabled: Bool) async {
        defaults.setBool(enabled, for: StorageKeys.logToFileEnabled)
    }

    func loadLogToFileEnabled() async -> Bool {
        defaults.bool(StorageKeys.logToFileEnabled) ?? false
    }

    func saveProxyEnabled(_ enabled: Bool) async {
        defaults.setBool(enabled, for: StorageKeys.proxyEnabled)
    }

    func loadProxyEnabled() async -> Bool {
        defaults.bool(StorageKeys.proxyEnabled) ?? false
    }

    func saveProxyHost(_ host: String) async {
        defaults.setString(host, for: StorageKeys.proxyHost)
    }

    func loadProxyHost() async -> String {
        defaults.string(StorageKeys.proxyHost) ?? ""
    }

    func saveProxyPort(_ port: Int) async {
        defaults.setInt(port, for: StorageKeys.proxyPort)
    }

    func loadProxyPort() async -> Int {
        defaults.int(StorageKeys.proxyPort) ?? 7890
    }

    func saveProxyUsername(_ username: String) async {
        defaults.setString(username, for: StorageKeys.proxyUsername)
    }

    func loadProxyUsername() async -> String {
        defaults.string(StorageKeys.proxyUsername) ?? ""
    }

    func saveProxyPassword(_ password: String) async throws {
        try await performSerialized(on: .sensitive) {
            if password.isEmpty {
                try await self.deleteSecureValue(
                    key: StorageKeys.proxyPassword
                )
            } else {
                try await self.writeSecureValue(
                    key: StorageKeys.proxyPassword,
                    value: password
                )
            }
            self.removeSensitiveFallback(
                StorageKeys.proxyPasswordFallback,
                resolveConflict: true
            )
        }
    }

    func loadProxyPassword() async throws -> String {
        try await performSerialized(on: .sensitive) {
            (try await self.readSensitiveValue(
                StorageKeys.proxyPassword,
                fallbackKey: StorageKeys.proxyPasswordFallback
            )) ?? ""
        }
    }

    func saveProxyBypassLan(_ bypass: Bool) async {
        defaults.setBool(bypass, for: StorageKeys.proxyBypassLan)
    }

    func loadProxyBypassLan() async -> Bool {
        defaults.bool(StorageKeys.proxyBypassLan) ?? true
    }

    func saveProxyBypassRules(_ rules: [String]) async {
        defaults.setStringList(rules, for: StorageKeys.proxyBypassRules)
    }

    func loadProxyBypassRules() async -> [String] {
        defaults.stringList(StorageKeys.proxyBypassRules) ?? []
    }

    func saveDefaultDownloadCategory(_ category: String?) async {
        if let category, !category.isEmpty {
            defaults.setString(category, for: StorageKeys.defaultDownloadCategory)
        } else {
            defaults.remove(StorageKeys.defaultDownloadCategory)
        }
    }

    func loadDefaultDownloadCategory() async -> String? {
        defaults.string(StorageKeys.defaultDownloadCategory)
    }

    func saveDefaultDownloadTags(_ tags: [String]) async {
        if !tags.isEmpty {
            defaults.setStringList(tags, for: StorageKeys.defaultDownloadTags)
        } else {
            defaults.remove(StorageKeys.defaultDownloadTags)
        }
    }

    func loadDefaultDownloadTags() async -> [String] {
        defaults.stringList(StorageKeys.defaultDownloadTags) ?? []
    }

    func saveAutoAddSiteTag(_ enabled: Bool) async {
        defaults.setBool(enabled, for: StorageKeys.autoAddSiteTag)
    }

    func loadAutoAddSiteTag() async -> Bool {
        defaults.bool(StorageKeys.autoAddSiteTag) ?? false
    }

    func saveDefaultDownloadSavePath(_ savePath: String?) async {
        if let savePath, !savePath.isEmpty {
            defaults.setString(
                savePath,
                for: StorageKeys.defaultDownloadSavePath
            )
        } else {
            defaults.remove(StorageKeys.defaultDownloadSavePath)
        }
    }

    func loadDefaultDownloadSavePath() async -> String? {
        defaults.string(StorageKeys.defaultDownloadSavePath)
    }

    func saveLocalDownloadLastDirectory(_ directory: String?) async {
        if let directory, !directory.isEmpty {
            defaults.setString(
                directory,
                for: StorageKeys.localDownloadLastDirectory
            )
        } else {
            defaults.remove(StorageKeys.localDownloadLastDirectory)
        }
    }

    func loadLocalDownloadLastDirectory() async -> String? {
        defaults.string(StorageKeys.localDownloadLastDirectory)
    }

    func saveDefaultDownloadToLocal(_ downloadToLocal: Bool) async {
        defaults.setBool(
            downloadToLocal,
            for: StorageKeys.defaultDownloadToLocal
        )
    }

    func loadDefaultDownloadToLocal() async -> Bool {
        defaults.bool(StorageKeys.defaultDownloadToLocal) ?? false
    }

    func saveDefaultDownloadStartPaused(_ startPaused: Bool) async {
        defaults.setBool(
            startPaused,
            for: StorageKeys.defaultDownloadStartPaused
        )
    }

    func loadDefaultDownloadStartPaused() async -> Bool {
        defaults.bool(StorageKeys.defaultDownloadStartPaused) ?? false
    }

    func saveWebDAVPassword(_ configId: String, _ password: String?) async throws
    {
        try await performSerialized(on: .sensitive) {
            let key = StorageKeys.webdavPassword(configId)
            let fallbackKey = StorageKeys.webdavPasswordFallback(configId)
            if let password, !password.isEmpty {
                try await self.writeSecureValue(key: key, value: password)
            } else {
                try await self.deleteSecureValue(key: key)
            }
            self.removeSensitiveFallback(fallbackKey, resolveConflict: true)
        }
    }

    func loadWebDAVPassword(_ configId: String) async throws -> String? {
        try await performSerialized(on: .sensitive) {
            try await self.readSensitiveValue(
                StorageKeys.webdavPassword(configId),
                fallbackKey: StorageKeys.webdavPasswordFallback(configId)
            )
        }
    }

    func deleteWebDAVPassword(_ configId: String) async throws {
        try await saveWebDAVPassword(configId, nil)
    }

    func saveAggregateSearchSettings<Settings: Encodable>(
        _ settings: Settings
    ) async throws {
        let data = try JSONEncoder().encode(settings)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw StorageError.invalidPayload("json_encoding_failed")
        }
        defaults.setString(raw, for: StorageKeys.aggregateSearchSettings)
    }

    func loadAggregateSearchSettings<Settings: Decodable>(
        as type: Settings.Type,
        defaultFactory: (_ siteIds: [String]) -> Settings
    ) async -> Settings {
        if let raw = defaults.string(StorageKeys.aggregateSearchSettings),
            let data = raw.data(using: .utf8),
            let value = try? JSONDecoder().decode(type, from: data)
        {
            return value
        }
        return defaultFactory(plainSiteIds())
    }

    private func plainSiteIds() -> [String] {
        guard let raw = defaults.string(StorageKeys.siteConfigs),
            let list = (try? JSONSerialization.jsonObject(
                with: Data(raw.utf8)
            )) as? [[String: Any]]
        else {
            return []
        }
        return list.compactMap { $0["id"] as? String }
    }

    func saveDownloaderConfigs<Configs: Encodable>(
        _ configs: [Configs],
        defaultId: String? = nil
    ) async throws {
        var sanitizedList: [[String: Any]] = []
        for config in configs {
            var dictionary = try encodeToDictionary(config)
            var nested = dictionary["config"] as? [String: Any] ?? [:]
            nested.removeValue(forKey: "password")
            dictionary["config"] = nested
            sanitizedList.append(dictionary)
        }
        let encoded = try jsonString(sanitizedList)
        try requirePreferenceMutation(
            "downloader_config_commit_failed",
            mutate: {
                defaults.setString(
                    encoded,
                    for: StorageKeys.downloaderConfigs
                )
            },
            verify: {
                defaults.string(StorageKeys.downloaderConfigs) == encoded
            }
        )
        updateFallbackConflictKeys {
            _ = $0.remove(StorageKeys.downloaderConfigs)
        }
        if let defaultId {
            try requirePreferenceMutation(
                "downloader_config_commit_failed",
                mutate: {
                    defaults.setString(
                        defaultId,
                        for: StorageKeys.defaultDownloaderId
                    )
                },
                verify: {
                    defaults.string(StorageKeys.defaultDownloaderId) ==
                        defaultId
                }
            )
        } else if defaults.contains(StorageKeys.defaultDownloaderId) {
            try requirePreferenceMutation(
                "downloader_config_commit_failed",
                mutate: {
                    defaults.remove(StorageKeys.defaultDownloaderId)
                },
                verify: {
                    !defaults.contains(StorageKeys.defaultDownloaderId)
                }
            )
        }
    }

    func loadDownloaderConfigs() async throws -> [[String: Any]] {
        guard let raw = defaults.string(StorageKeys.downloaderConfigs) else {
            return []
        }
        guard let list = (try? JSONSerialization.jsonObject(
            with: Data(raw.utf8)
        )) as? [[String: Any]] else {
            throw StorageError.downloaderConfigLoadFailed
        }
        return list
    }

    func loadDefaultDownloaderId() async -> String? {
        defaults.string(StorageKeys.defaultDownloaderId)
    }

    func saveVisibleTags(_ tags: [String]) async {
        withStateLock {
            defaults.setStringList(tags, for: StorageKeys.visibleTags)
            visibleTagsCache = tags
        }
    }

    func loadVisibleTags(fallback: [String]) async {
        withStateLock {
            let stored = defaults.stringList(StorageKeys.visibleTags)
            visibleTagsCache = stored ?? fallback
        }
    }

    private func saveDownloaderPasswordUnlocked(
        _ id: String,
        _ password: String
    ) async throws {
        let key = StorageKeys.downloaderPasswordKey(id)
        let fallbackKey = StorageKeys.downloaderPasswordFallbackKey(id)
        if password.isEmpty {
            try await cleanupLegacyQbPasswordSources(id)
            try await deleteSecureValue(key: key)
            removeSensitiveFallback(fallbackKey, resolveConflict: true)
            return
        }
        try await writeSecureValue(key: key, value: password)
        removeSensitiveFallback(fallbackKey, resolveConflict: true)
        try await cleanupLegacyQbPasswordSources(id)
    }

    private func loadDownloaderPasswordUnlocked(_ id: String) async throws
        -> String?
    {
        try await readSensitiveValue(
            StorageKeys.downloaderPasswordKey(id),
            fallbackKey: StorageKeys.downloaderPasswordFallbackKey(id)
        )
    }

    func saveDownloaderPassword(_ id: String, _ password: String) async throws {
        try await performSerialized(on: .sensitive) {
            try await self.saveDownloaderPasswordUnlocked(id, password)
        }
    }

    func loadDownloaderPassword(_ id: String) async throws -> String? {
        try await performSerialized(on: .sensitive) {
            try await self.loadDownloaderPasswordUnlocked(id)
        }
    }

    func deleteDownloaderPassword(_ id: String) async throws {
        try await performSerialized(on: .sensitive) {
            let key = StorageKeys.downloaderPasswordKey(id)
            let fallbackKey = StorageKeys.downloaderPasswordFallbackKey(id)
            try await self.cleanupLegacyQbPasswordSources(id)
            try await self.deleteSecureValue(key: key)
            self.removeSensitiveFallback(fallbackKey, resolveConflict: true)
        }
    }

    func saveDownloaderCategories(_ id: String, _ categories: [String]) async {
        defaults.setStringList(
            categories,
            for: StorageKeys.downloaderCategoriesKey(id)
        )
    }

    func loadDownloaderCategories(_ id: String) async -> [String] {
        defaults.stringList(StorageKeys.downloaderCategoriesKey(id)) ?? []
    }

    func saveDownloaderTags(_ id: String, _ tags: [String]) async {
        defaults.setStringList(tags, for: StorageKeys.downloaderTagsKey(id))
    }

    func loadDownloaderTags(_ id: String) async -> [String] {
        defaults.stringList(StorageKeys.downloaderTagsKey(id)) ?? []
    }

    func saveDownloaderPaths(_ id: String, _ paths: [String]) async {
        defaults.setStringList(paths, for: StorageKeys.downloaderPathsKey(id))
    }

    func loadDownloaderPaths(_ id: String) async -> [String] {
        defaults.stringList(StorageKeys.downloaderPathsKey(id)) ?? []
    }

    func saveDeviceId(_ deviceId: String) async throws {
        try await performSerialized(on: .sensitive) {
            if deviceId.isEmpty {
                try await self.deleteSecureValue(key: StorageKeys.deviceId)
            } else {
                try await self.writeSecureValue(
                    key: StorageKeys.deviceId,
                    value: deviceId
                )
            }
            self.removeSensitiveFallback(
                StorageKeys.deviceIdFallback,
                resolveConflict: true
            )
        }
    }

    func loadDeviceId() async throws -> String? {
        try await performSerialized(on: .sensitive) {
            try await self.readSensitiveValue(
                StorageKeys.deviceId,
                fallbackKey: StorageKeys.deviceIdFallback
            )
        }
    }

    func deleteDeviceId() async throws {
        try await performSerialized(on: .sensitive) {
            try await self.deleteSecureValue(key: StorageKeys.deviceId)
            self.removeSensitiveFallback(
                StorageKeys.deviceIdFallback,
                resolveConflict: true
            )
        }
    }

    func saveHealthStatuses(
        _ statuses: [String: [String: Any]]
    ) async throws {
        let encoded = try jsonString(statuses)
        try await performSerialized(on: .health) {
            try self.requirePreferenceMutation(
                "health_statuses_commit_failed",
                mutate: {
                    self.defaults.setString(
                        encoded,
                        for: StorageKeys.healthStatuses
                    )
                },
                verify: {
                    self.defaults.string(StorageKeys.healthStatuses) == encoded
                }
            )
        }
    }

    func mergeHealthStatuses(
        _ statuses: [String: [String: Any]],
        preferNewer: Bool = true
    ) async throws {
        _ = try jsonString(statuses)
        try await performSerialized(on: .health) {
            try self.applyHealthStatusMerge(
                statuses,
                preferNewer: preferNewer
            )
        }
    }

    private func applyHealthStatusMerge(
        _ incoming: [String: [String: Any]],
        preferNewer: Bool
    ) throws {
        try withStateLock {
            var merged = readHealthStatusesLocked()
            for (siteId, nextStatus) in incoming {
                guard let currentStatus = merged[siteId] else {
                    merged[siteId] = nextStatus
                    continue
                }
                if !preferNewer {
                    merged[siteId] = nextStatus
                    continue
                }
                let currentUpdatedAt = healthStatusUpdatedAt(currentStatus)
                let nextUpdatedAt = healthStatusUpdatedAt(nextStatus)
                if currentUpdatedAt == nil || nextUpdatedAt == nil ||
                    !(currentUpdatedAt! > nextUpdatedAt!)
                {
                    merged[siteId] = nextStatus
                }
            }
            let mergedEncoded = try jsonString(merged)
            try requirePreferenceMutation(
                "health_statuses_commit_failed",
                mutate: {
                    defaults.setString(
                        mergedEncoded,
                        for: StorageKeys.healthStatuses
                    )
                },
                verify: {
                    defaults.string(StorageKeys.healthStatuses) == mergedEncoded
                }
            )
        }
    }

    func loadHealthStatuses() async -> [String: [String: Any]] {
        withStateLock { readHealthStatusesLocked() }
    }

    private func readHealthStatusesLocked() -> [String: [String: Any]] {
        guard let raw = defaults.string(StorageKeys.healthStatuses),
            let data = raw.data(using: .utf8),
            let decoded = try? JSONSerialization.jsonObject(with: data),
            let map = decoded as? [String: Any]
        else {
            return [:]
        }
        var result: [String: [String: Any]] = [:]
        for (key, value) in map {
            result[key] = value as? [String: Any] ?? [:]
        }
        return result
    }

    private func healthStatusUpdatedAt(
        _ status: [String: Any]
    ) -> Date? {
        guard let raw = status["updatedAt"] as? String, !raw.isEmpty else {
            return nil
        }
        return ISO8601Codec.date(from: raw)
    }

    func saveLastSiteHealthRefreshCheck(_ time: Date) async {
        withStateLock {
            defaults.setInt(
                Int(time.timeIntervalSince1970 * 1000),
                for: StorageKeys.lastSiteHealthRefreshCheck
            )
        }
    }

    func loadLastSiteHealthRefreshCheck() async -> Date? {
        withStateLock {
            guard let timestamp = defaults.int(
                StorageKeys.lastSiteHealthRefreshCheck
            ) else {
                return nil
            }
            return Date(
                timeIntervalSince1970: Double(timestamp) / 1000.0
            )
        }
    }

    private func validateBackupPreferencesPayload(
        _ payload: [String: Any]
    ) throws {
        let allowedKeys: Set<String> = [
            "activeSiteId",
            "downloaderConfigs",
            "defaultDownloaderId",
            "themeMode",
            "dynamicColor",
            "seedColor",
            "autoLoadImages",
            "defaultDownloadCategory",
            "defaultDownloadTags",
            "autoAddSiteTag",
            "defaultDownloadSavePath",
            "proxyEnabled",
            "proxyHost",
            "proxyPort",
            "proxyUsername",
            "proxyBypassLan",
            "proxyBypassRules",
            "downloaderCategoriesCache",
            "downloaderTagsCache",
            "aggregateSearchSettings",
            "webdavConfig",
            "webdavConfigHistory",
        ]
        let invalidType: Bool = {
            if payload.keys.contains(where: { !allowedKeys.contains($0) }) {
                return true
            }
            if let value = payload["activeSiteId"],
                !(value is String)
            {
                return true
            }
            if let value = unwrapJSONNull(payload["defaultDownloaderId"]),
                !(value is String)
            {
                return true
            }
            if let value = payload["themeMode"],
                !(value is String)
            {
                return true
            }
            if let value = payload["dynamicColor"],
                !isBooleanValue(value)
            {
                return true
            }
            if let value = payload["seedColor"],
                !isIntegerValue(value)
            {
                return true
            }
            if let value = payload["autoLoadImages"],
                !isBooleanValue(value)
            {
                return true
            }
            if let value = payload["autoAddSiteTag"],
                !isBooleanValue(value)
            {
                return true
            }
            if let value = payload["defaultDownloadCategory"],
                !(value is String)
            {
                return true
            }
            if let value = payload["defaultDownloadSavePath"],
                !(value is String)
            {
                return true
            }
            if let value = payload["proxyEnabled"],
                !isBooleanValue(value)
            {
                return true
            }
            if let value = payload["proxyHost"],
                !(value is String)
            {
                return true
            }
            if let value = payload["proxyPort"],
                !isIntegerValue(value)
            {
                return true
            }
            if let value = payload["proxyUsername"],
                !(value is String)
            {
                return true
            }
            if let value = payload["proxyBypassLan"],
                !isBooleanValue(value)
            {
                return true
            }
            if payload["defaultDownloadTags"] != nil,
                !isStringList(unwrapJSONNull(payload["defaultDownloadTags"]))
            {
                return true
            }
            if payload["proxyBypassRules"] != nil,
                !isStringList(unwrapJSONNull(payload["proxyBypassRules"]))
            {
                return true
            }
            if let downloaderConfigs = unwrapJSONNull(
                payload["downloaderConfigs"]
            ) {
                guard let list = downloaderConfigs as? [Any] else {
                    return true
                }
                for value in list {
                    guard let dictionary = value as? [String: Any] else {
                        return true
                    }
                    let source =
                        dictionary["config"] as? [String: Any] ?? dictionary
                    if let password = unwrapJSONNull(source["password"]) {
                        guard let passwordString = password as? String else {
                            return true
                        }
                        if !passwordString.isEmpty {
                            return true
                        }
                    }
                }
            }
            for key in [
                "downloaderCategoriesCache",
                "downloaderTagsCache",
            ] {
                if let rawValue = payload[key],
                    let value = unwrapJSONNull(rawValue)
                {
                    guard let map = value as? [String: Any] else {
                        return true
                    }
                    for (entryKey, entryValue) in map {
                        if entryKey.isEmpty ||
                            !isStringList(unwrapJSONNull(entryValue))
                        {
                            return true
                        }
                    }
                }
            }
            if let aggregate = unwrapJSONNull(payload["aggregateSearchSettings"]),
                !(aggregate is [String: Any])
            {
                return true
            }
            if let webdavConfig = unwrapJSONNull(payload["webdavConfig"]),
                !(webdavConfig is [String: Any])
            {
                return true
            }
            if let webdavHistory = unwrapJSONNull(
                payload["webdavConfigHistory"]
            ) {
                guard let list = webdavHistory as? [Any] else {
                    return true
                }
                for value in list {
                    if !(value is [String: Any]) {
                        return true
                    }
                }
            }
            return false
        }()
        if invalidType {
            throw StorageError.invalidPayload(
                "invalid_backup_preferences_payload"
            )
        }
    }

    func validateBackupRestorePayload(
        cookieCloudConfig: CookieCloudConfig? = nil,
        backupPreferences: [String: Any]
    ) throws {
        if let cookieCloudConfig {
            let payload = encodeCookieCloudPreferences(cookieCloudConfig)
            try validateCookieCloudPreferencesPayload(payload)
        }
        try validateBackupPreferencesPayload(backupPreferences)
    }

    func validateBackupRestorePayload<Config: SiteConfigStorable>(
        siteConfigs: [Config],
        cookieCloudConfig: CookieCloudConfig? = nil,
        backupPreferences: [String: Any]
    ) throws {
        let plainList = try plainSiteConfigList(siteConfigs)
        try validatePlainSiteConfigList(plainList)
        if let cookieCloudConfig {
            let payload = encodeCookieCloudPreferences(cookieCloudConfig)
            try validateCookieCloudPreferencesPayload(payload)
        }
        try validateBackupPreferencesPayload(backupPreferences)
    }

    private func persistBackupPreferenceSnapshot(
        _ snapshot: [String: Any]
    ) throws {
        try validateBackupPreferencesPayload(snapshot)

        func persistString(_ name: String, _ key: String) throws {
            guard let value = snapshot[name] else { return }
            guard let stringValue = value as? String else {
                throw StorageError.invalidPayload(
                    "invalid_backup_preferences_payload"
                )
            }
            try requirePreferenceMutation(
                "backup_preferences_commit_failed",
                mutate: { self.defaults.setString(stringValue, for: key) },
                verify: { self.defaults.string(key) == stringValue }
            )
        }

        func persistBool(_ name: String, _ key: String) throws {
            guard let value = snapshot[name] else { return }
            guard let boolValue = value as? Bool, isBooleanValue(value) else {
                throw StorageError.invalidPayload(
                    "invalid_backup_preferences_payload"
                )
            }
            try requirePreferenceMutation(
                "backup_preferences_commit_failed",
                mutate: { self.defaults.setBool(boolValue, for: key) },
                verify: { self.defaults.bool(key) == boolValue }
            )
        }

        func persistInt(_ name: String, _ key: String) throws {
            guard let value = snapshot[name] else { return }
            guard isIntegerValue(value),
                let intValue = (value as? NSNumber)?.intValue
            else {
                throw StorageError.invalidPayload(
                    "invalid_backup_preferences_payload"
                )
            }
            try requirePreferenceMutation(
                "backup_preferences_commit_failed",
                mutate: { self.defaults.setInt(intValue, for: key) },
                verify: { self.defaults.int(key) == intValue }
            )
        }

        func persistStringList(_ name: String, _ key: String) throws {
            guard let value = snapshot[name] else { return }
            guard let list = value as? [String] else {
                throw StorageError.invalidPayload(
                    "invalid_backup_preferences_payload"
                )
            }
            try requirePreferenceMutation(
                "backup_preferences_commit_failed",
                mutate: { self.defaults.setStringList(list, for: key) },
                verify: { self.defaults.stringList(key) == list }
            )
        }

        try persistString("activeSiteId", StorageKeys.activeSiteId)

        if let downloaderConfigs = snapshot["downloaderConfigs"] {
            let encoded = try jsonString(downloaderConfigs)
            try requirePreferenceMutation(
                "backup_preferences_commit_failed",
                mutate: {
                    defaults.setString(
                        encoded,
                        for: StorageKeys.downloaderConfigs
                    )
                },
                verify: {
                    defaults.string(StorageKeys.downloaderConfigs) == encoded
                }
            )
        }

        if let defaultDownloaderId = snapshot["defaultDownloaderId"] {
            if defaultDownloaderId is NSNull {
                try requirePreferenceMutation(
                    "backup_preferences_commit_failed",
                    mutate: {
                        defaults.remove(StorageKeys.defaultDownloaderId)
                    },
                    verify: {
                        !defaults.contains(StorageKeys.defaultDownloaderId)
                    }
                )
            } else if let stringValue = defaultDownloaderId as? String {
                try requirePreferenceMutation(
                    "backup_preferences_commit_failed",
                    mutate: {
                        defaults.setString(
                            stringValue,
                            for: StorageKeys.defaultDownloaderId
                        )
                    },
                    verify: {
                        defaults.string(StorageKeys.defaultDownloaderId) ==
                            stringValue
                    }
                )
            }
        }

        try persistString("themeMode", StorageKeys.themeMode)
        try persistBool("dynamicColor", StorageKeys.themeUseDynamic)
        try persistInt("seedColor", StorageKeys.themeSeedColor)
        try persistBool("autoLoadImages", StorageKeys.autoLoadImages)
        try persistBool("autoAddSiteTag", StorageKeys.autoAddSiteTag)
        try persistString(
            "defaultDownloadCategory",
            StorageKeys.defaultDownloadCategory
        )
        try persistStringList(
            "defaultDownloadTags",
            StorageKeys.defaultDownloadTags
        )
        try persistString(
            "defaultDownloadSavePath",
            StorageKeys.defaultDownloadSavePath
        )
        try persistBool("proxyEnabled", StorageKeys.proxyEnabled)
        try persistString("proxyHost", StorageKeys.proxyHost)
        try persistInt("proxyPort", StorageKeys.proxyPort)
        try persistString("proxyUsername", StorageKeys.proxyUsername)
        try persistBool("proxyBypassLan", StorageKeys.proxyBypassLan)
        try persistStringList(
            "proxyBypassRules",
            StorageKeys.proxyBypassRules
        )

        func persistStringListMap(
            _ name: String,
            _ key: (String) -> String
        ) throws {
            guard let values = snapshot[name] else { return }
            guard let map = values as? [String: Any] else {
                throw StorageError.invalidPayload(
                    "invalid_backup_preferences_payload"
                )
            }
            for (entryKey, entryValue) in map {
                guard let list = entryValue as? [String] else {
                    throw StorageError.invalidPayload(
                        "invalid_backup_preferences_payload"
                    )
                }
                let preferenceKey = key(entryKey)
                try requirePreferenceMutation(
                    "backup_preferences_commit_failed",
                    mutate: {
                        self.defaults.setStringList(list, for: preferenceKey)
                    },
                    verify: {
                        self.defaults.stringList(preferenceKey) == list
                    }
                )
            }
        }

        try persistStringListMap(
            "downloaderCategoriesCache",
            { StorageKeys.downloaderCategoriesKey($0) }
        )
        try persistStringListMap(
            "downloaderTagsCache",
            { StorageKeys.downloaderTagsKey($0) }
        )

        if let aggregate = snapshot["aggregateSearchSettings"] {
            let encoded = try jsonString(aggregate)
            try requirePreferenceMutation(
                "backup_preferences_commit_failed",
                mutate: {
                    defaults.setString(
                        encoded,
                        for: StorageKeys.aggregateSearchSettings
                    )
                },
                verify: {
                    defaults.string(StorageKeys.aggregateSearchSettings) ==
                        encoded
                }
            )
        }

        if let webdavConfig = snapshot["webdavConfig"] {
            if webdavConfig is NSNull {
                try requirePreferenceMutation(
                    "backup_preferences_commit_failed",
                    mutate: { defaults.remove(StorageKeys.webdavConfig) },
                    verify: { !defaults.contains(StorageKeys.webdavConfig) }
                )
            } else {
                let encoded = try jsonString(webdavConfig)
                try requirePreferenceMutation(
                    "backup_preferences_commit_failed",
                    mutate: {
                        defaults.setString(
                            encoded,
                            for: StorageKeys.webdavConfig
                        )
                    },
                    verify: {
                        defaults.string(StorageKeys.webdavConfig) == encoded
                    }
                )
            }
        }

        if let webdavHistory = snapshot["webdavConfigHistory"] {
            let encoded = try jsonString(webdavHistory)
            try requirePreferenceMutation(
                "backup_preferences_commit_failed",
                mutate: {
                    defaults.setString(
                        encoded,
                        for: StorageKeys.webdavConfigHistory
                    )
                },
                verify: {
                    defaults.string(StorageKeys.webdavConfigHistory) == encoded
                }
            )
        }
    }

    func restoreSensitiveBackupData(
        cookieCloudConfig: CookieCloudConfig? = nil,
        downloaderPasswords: [String: String]? = nil,
        downloaderIds: Set<String>? = nil,
        deviceId: String? = nil,
        webdavPasswords: [String: String]? = nil,
        webdavIds: Set<String>? = nil,
        backupPreferences: [String: Any]? = nil,
        hasProxyPassword: Bool = false,
        proxyPassword: String = ""
    ) async throws {
        try await restoreSensitiveBackupDataLocked(
            siteConfigs: Optional<
                [any SiteConfigStorable]
            >.none,
            cookieCloudConfig: cookieCloudConfig,
            downloaderPasswords: downloaderPasswords,
            downloaderIds: downloaderIds,
            deviceId: deviceId,
            webdavPasswords: webdavPasswords,
            webdavIds: webdavIds,
            backupPreferences: backupPreferences,
            hasProxyPassword: hasProxyPassword,
            proxyPassword: proxyPassword
        )
    }

    func restoreSensitiveBackupData<Config: SiteConfigStorable>(
        siteConfigs: [Config],
        cookieCloudConfig: CookieCloudConfig? = nil,
        downloaderPasswords: [String: String]? = nil,
        downloaderIds: Set<String>? = nil,
        deviceId: String? = nil,
        webdavPasswords: [String: String]? = nil,
        webdavIds: Set<String>? = nil,
        backupPreferences: [String: Any]? = nil,
        hasProxyPassword: Bool = false,
        proxyPassword: String = ""
    ) async throws {
        try await restoreSensitiveBackupDataLocked(
            siteConfigs: siteConfigs.map { $0 as any SiteConfigStorable },
            cookieCloudConfig: cookieCloudConfig,
            downloaderPasswords: downloaderPasswords,
            downloaderIds: downloaderIds,
            deviceId: deviceId,
            webdavPasswords: webdavPasswords,
            webdavIds: webdavIds,
            backupPreferences: backupPreferences,
            hasProxyPassword: hasProxyPassword,
            proxyPassword: proxyPassword
        )
    }

    private func restoreSensitiveBackupDataLocked(
        siteConfigs: [any SiteConfigStorable]?,
        cookieCloudConfig: CookieCloudConfig?,
        downloaderPasswords: [String: String]?,
        downloaderIds: Set<String>?,
        deviceId: String?,
        webdavPasswords: [String: String]?,
        webdavIds: Set<String>?,
        backupPreferences: [String: Any]?,
        hasProxyPassword: Bool,
        proxyPassword: String
    ) async throws {
        var validatedBackupPreferences: [String: Any]?
        if let backupPreferences {
            try validateBackupPreferencesPayload(backupPreferences)
            validatedBackupPreferences = backupPreferences
        }
        try await performSerialized(on: .site) {
            var mutations: [String: SensitiveMutation] = [:]
            var fallbackKeys: [String] = []
            var plainCommitted = false
            var cookieCloudPreferencesCommitted = false

            let encodedPlainSiteConfigs: [[String: Any]]?
            if let siteConfigs {
                encodedPlainSiteConfigs = try self.plainSiteConfigList(
                    siteConfigs
                )
            } else {
                encodedPlainSiteConfigs = nil
            }

            if let siteConfigs {
                let existingIds = try self.persistedPlainSiteIds(
                    failureCode: "backup_restore_invalid_existing_site_config"
                )
                let restoredIds = Set(siteConfigs.map { $0.id })
                for removedId in existingIds.subtracting(restoredIds) {
                    mutations[StorageKeys.siteApiKey(removedId)] = .delete
                    mutations[StorageKeys.siteCookie(removedId)] = .delete
                    fallbackKeys.append(
                        StorageKeys.siteApiKeyFallback(removedId)
                    )
                    fallbackKeys.append(
                        StorageKeys.siteCookieFallback(removedId)
                    )
                }
                for config in siteConfigs {
                    let apiKeyKey = StorageKeys.siteApiKey(config.id)
                    if let apiKey = config.apiKey, !apiKey.isEmpty {
                        mutations[apiKeyKey] = .upsert(apiKey)
                    } else {
                        mutations[apiKeyKey] = .delete
                    }
                    fallbackKeys.append(
                        StorageKeys.siteApiKeyFallback(config.id)
                    )

                    let cookieKey = StorageKeys.siteCookie(config.id)
                    if let cookie = config.cookie, !cookie.isEmpty {
                        mutations[cookieKey] = .upsert(cookie)
                    } else {
                        mutations[cookieKey] = .delete
                    }
                    fallbackKeys.append(
                        StorageKeys.siteCookieFallback(config.id)
                    )
                }
            }

            if let cookieCloudConfig {
                let secrets = CookieCloudSecrets(
                    url: cookieCloudConfig.url.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    uuid: cookieCloudConfig.uuid.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    password: cookieCloudConfig.password
                )
                let encoded = try jsonString([
                    "url": secrets.url,
                    "uuid": secrets.uuid,
                    "password": secrets.password,
                ])
                mutations[StorageKeys.cookieCloudSecretsV2] = .upsert(encoded)
                fallbackKeys.append(StorageKeys.cookieCloudSecretsV2Fallback)
            }

            var restoredDownloaderIds = Set(downloaderIds ?? [])
            if let downloaderPasswords {
                restoredDownloaderIds.formUnion(downloaderPasswords.keys)
            }
            var downloaderIdsWithLegacySourcesToDelete = Set<String>()
            if let downloaderIds {
                let existingIds = try self.persistedPlainSiteIds(
                    failureCode:
                        "backup_restore_invalid_existing_downloader_config",
                    key: StorageKeys.downloaderConfigs
                )
                for removedId in existingIds.subtracting(downloaderIds) {
                    mutations[StorageKeys.downloaderPasswordKey(removedId)] =
                        .delete
                    fallbackKeys.append(
                        StorageKeys.downloaderPasswordFallbackKey(removedId)
                    )
                    downloaderIdsWithLegacySourcesToDelete.insert(removedId)
                }
            }
            for id in restoredDownloaderIds {
                let key = StorageKeys.downloaderPasswordKey(id)
                let password = downloaderPasswords?[id] ?? ""
                if password.isEmpty {
                    mutations[key] = .delete
                    downloaderIdsWithLegacySourcesToDelete.insert(id)
                } else {
                    mutations[key] = .upsert(password)
                }
                fallbackKeys.append(
                    StorageKeys.downloaderPasswordFallbackKey(id)
                )
            }

            if hasProxyPassword {
                if proxyPassword.isEmpty {
                    mutations[StorageKeys.proxyPassword] = .delete
                } else {
                    mutations[StorageKeys.proxyPassword] = .upsert(
                        proxyPassword
                    )
                }
                fallbackKeys.append(StorageKeys.proxyPasswordFallback)
            }

            if let deviceId {
                if deviceId.isEmpty {
                    mutations[StorageKeys.deviceId] = .delete
                } else {
                    mutations[StorageKeys.deviceId] = .upsert(deviceId)
                }
                fallbackKeys.append(StorageKeys.deviceIdFallback)
            }

            var restoredWebdavIds = Set(webdavIds ?? [])
            if let webdavPasswords {
                restoredWebdavIds.formUnion(webdavPasswords.keys)
            }
            for id in restoredWebdavIds {
                let key = StorageKeys.webdavPassword(id)
                let password = webdavPasswords?[id] ?? ""
                if password.isEmpty {
                    mutations[key] = .delete
                } else {
                    mutations[key] = .upsert(password)
                }
                fallbackKeys.append(StorageKeys.webdavPasswordFallback(id))
            }

            let hasCompanionPayloads = encodedPlainSiteConfigs != nil ||
                cookieCloudConfig != nil ||
                validatedBackupPreferences != nil
            if !mutations.isEmpty || hasCompanionPayloads {
                for downloaderId in downloaderIdsWithLegacySourcesToDelete {
                    try await self.cleanupLegacyQbPasswordSources(downloaderId)
                }
                for (key, mutation) in mutations {
                    switch mutation {
                    case .upsert(let value):
                        try await self.writeSecureValue(
                            key: key,
                            value: value
                        )
                    case .delete:
                        try await self.deleteSecureValue(key: key)
                    }
                }
                if let encodedPlainSiteConfigs {
                    try self.persistPlainSiteConfigList(
                        encodedPlainSiteConfigs
                    )
                    plainCommitted = true
                }
                if let cookieCloudConfig {
                    try self.persistCookieCloudPreferences(cookieCloudConfig)
                    cookieCloudPreferencesCommitted = true
                }
                if let validatedBackupPreferences {
                    try self.persistBackupPreferenceSnapshot(
                        validatedBackupPreferences
                    )
                }
                for fallbackKey in fallbackKeys {
                    self.removeSensitiveFallback(
                        fallbackKey,
                        resolveConflict: true
                    )
                }
                let remainingDownloaderIds = restoredDownloaderIds
                    .subtracting(downloaderIdsWithLegacySourcesToDelete)
                for downloaderId in remainingDownloaderIds {
                    try await self.cleanupLegacyQbPasswordSources(
                        downloaderId
                    )
                }
            }

            if siteConfigs != nil {
                if !plainCommitted, let encodedPlainSiteConfigs {
                    try self.persistPlainSiteConfigList(encodedPlainSiteConfigs)
                }
                self.withStateLock {
                    self.siteApiKeysCache.removeAll()
                    self.siteCookiesCache.removeAll()
                }
                self.clearFallbackConflictMarker(StorageKeys.siteConfigs)
            }
            if let cookieCloudConfig {
                self.setCookieCloudLegacyCleanupPending(true)
                self.withStateLock {
                    self.cookieCloudBundleCreatedThisRun = true
                }
                if !cookieCloudPreferencesCommitted {
                    try self.persistCookieCloudPreferences(cookieCloudConfig)
                }
            }
        }
    }

    private func persistedPlainSiteIds(
        failureCode: String,
        key: String = StorageKeys.siteConfigs
    ) throws -> Set<String> {
        guard let raw = defaults.string(key) else {
            return []
        }
        guard let decoded = (try? JSONSerialization.jsonObject(
            with: Data(raw.utf8)
        )) as? [Any] else {
            throw SecureStorageUnavailableError(code: failureCode)
        }
        var ids = Set<String>()
        for value in decoded {
            guard let dictionary = value as? [String: Any],
                let id = dictionary["id"] as? String,
                !id.isEmpty
            else {
                throw SecureStorageUnavailableError(code: failureCode)
            }
            ids.insert(id)
        }
        return ids
    }
}
