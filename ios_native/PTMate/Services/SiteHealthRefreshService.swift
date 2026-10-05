import Foundation

struct SiteHealthSecureStorageOperationEpoch: Equatable {
    fileprivate let generation: Int

    fileprivate init(generation: Int) {
        self.generation = generation
    }
}

final class SiteHealthRefreshService: @unchecked Sendable {
    static let shared = SiteHealthRefreshService()

    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    @TaskLocal private static var currentEpoch: SiteHealthSecureStorageOperationEpoch?

    private final class GenerationTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var generationValue = 0
        private var signatureValue: String?

        func synchronize(_ signature: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            if signatureValue != signature {
                signatureValue = signature
                generationValue += 1
            }
            return generationValue
        }
    }

    private struct ConnectionTestFailure: Error, CustomStringConvertible {
        let message: String

        var description: String {
            "Exception: \(message)"
        }
    }

    private final class RefreshRunState: @unchecked Sendable {
        typealias StatusCallback = (String, HealthStatus) -> Void

        private let lock = NSLock()
        private let onStatus: StatusCallback?
        private var statusesValue: [String: HealthStatus] = [:]
        private var failureValue: Error?

        init(onStatus: StatusCallback?) {
            self.onStatus = onStatus
        }

        var statuses: [String: HealthStatus] {
            lock.lock()
            defer { lock.unlock() }
            return statusesValue
        }

        var failure: Error? {
            lock.lock()
            defer { lock.unlock() }
            return failureValue
        }

        func recordStatus(siteId: String, status: HealthStatus) {
            lock.lock()
            statusesValue[siteId] = status
            let callback = onStatus
            lock.unlock()
            callback?(siteId, status)
        }

        func recordFailure(_ error: Error) {
            lock.lock()
            if failureValue == nil {
                failureValue = error
            }
            lock.unlock()
        }
    }

    private let storage = StorageService.shared
    private let generations = GenerationTracker()

    private init() {}

    func refreshIfNeeded() async throws -> [String: HealthStatus]? {
        do {
            return try await runWithCurrentSecureStorageOperation {
                [self] epoch in
                if try await !shouldRefresh() {
                    return nil
                }
                try requireSecureStorageOperationEpoch(epoch)
                return try await refreshAllSitesInCurrentEpoch(
                    force: true,
                    persistLastRefreshTime: true,
                    onStatus: nil,
                    epoch: epoch
                )
            }
        } catch is SecureStorageUnavailableError {
            return nil
        }
    }

    func refreshAllSites(
        force: Bool = false,
        persistLastRefreshTime: Bool = false,
        onStatus: ((String, HealthStatus) -> Void)? = nil,
        expectedSecureStorageEpoch: SiteHealthSecureStorageOperationEpoch? = nil
    ) async throws -> [String: HealthStatus] {
        if let expected = expectedSecureStorageEpoch {
            return try await runWithSecureStorageOperationEpoch(expected) {
                [self] epoch in
                try await refreshAllSitesInCurrentEpoch(
                    force: force,
                    persistLastRefreshTime: persistLastRefreshTime,
                    onStatus: onStatus,
                    epoch: epoch
                )
            }
        }
        return try await runWithCurrentSecureStorageOperation { [self] epoch in
            try await refreshAllSitesInCurrentEpoch(
                force: force,
                persistLastRefreshTime: persistLastRefreshTime,
                onStatus: onStatus,
                epoch: epoch
            )
        }
    }

    private func refreshAllSitesInCurrentEpoch(
        force: Bool,
        persistLastRefreshTime: Bool,
        onStatus: ((String, HealthStatus) -> Void)?,
        epoch: SiteHealthSecureStorageOperationEpoch
    ) async throws -> [String: HealthStatus] {
        try requireSecureStorageOperationEpoch(epoch)
        if !force, try await !shouldRefresh() {
            try requireSecureStorageOperationEpoch(epoch)
            return [:]
        }

        let allSites: [SiteConfig] = try await storage.loadSiteConfigs(
            includeApiKeys: true
        )
        try requireSecureStorageOperationEpoch(epoch)
        if allSites.isEmpty {
            if persistLastRefreshTime {
                try requireSecureStorageOperationEpoch(epoch)
                await storage.saveLastSiteHealthRefreshCheck(Date())
            }
            return [:]
        }

        let settings = await storage.loadAggregateSearchSettings(
            as: AggregateSearchSettings.self,
            defaultFactory: { siteIds in
                AggregateSearchSettings(
                    searchConfigs: [
                        AggregateSearchConfig.createDefaultConfig(siteIds)
                    ],
                    searchThreads: 3
                )
            }
        )
        let maxConcurrency = settings.searchThreads <= 0 ? 1 : settings.searchThreads
        let runState = RefreshRunState(onStatus: onStatus)

        await withTaskGroup(of: Void.self) { group in
            var index = 0
            var active = 0

            while true {
                if !isSecureStorageOperationEpochCurrent(epoch) {
                    runState.recordFailure(
                        SecureStorageUnavailableError(
                            code: storage.canAccessSensitiveStorage
                                ? "secure_storage_operation_invalidated"
                                : storage.secureStorageFailureCode
                                    ?? "secure_storage_not_ready"
                        )
                    )
                }
                if runState.failure != nil {
                    index = allSites.count
                }

                while active < maxConcurrency && index < allSites.count {
                    let site = allSites[index]
                    index += 1
                    active += 1
                    group.addTask { [self] in
                        do {
                            let status = try await checkSingleSite(
                                site,
                                expectedSecureStorageEpoch: epoch
                            )
                            try requireSecureStorageOperationEpoch(epoch)
                            runState.recordStatus(siteId: site.id, status: status)
                        } catch {
                            runState.recordFailure(error)
                        }
                    }
                }

                if active == 0 {
                    break
                }
                _ = await group.next()
                active -= 1
            }
            group.cancelAll()
        }

        if let failure = runState.failure {
            throw failure
        }
        try requireSecureStorageOperationEpoch(epoch)

        let statuses = runState.statuses
        try await storage.mergeHealthStatuses(
            statuses.reduce(into: [String: [String: Any]]()) { result, entry in
                result[entry.key] = entry.value.toJson()
            }
        )

        if persistLastRefreshTime {
            try requireSecureStorageOperationEpoch(epoch)
            await storage.saveLastSiteHealthRefreshCheck(Date())
        }

        return statuses
    }

    func refreshSingleSite(
        _ site: SiteConfig,
        recreateAdapter: Bool = false,
        expectedSecureStorageEpoch: SiteHealthSecureStorageOperationEpoch? = nil
    ) async throws -> HealthStatus {
        if let expected = expectedSecureStorageEpoch {
            return try await runWithSecureStorageOperationEpoch(expected) {
                [self] epoch in
                try await refreshSingleSiteInCurrentEpoch(
                    site,
                    recreateAdapter: recreateAdapter,
                    epoch: epoch
                )
            }
        }
        return try await runWithCurrentSecureStorageOperation { [self] epoch in
            try await refreshSingleSiteInCurrentEpoch(
                site,
                recreateAdapter: recreateAdapter,
                epoch: epoch
            )
        }
    }

    private func refreshSingleSiteInCurrentEpoch(
        _ site: SiteConfig,
        recreateAdapter: Bool,
        epoch: SiteHealthSecureStorageOperationEpoch
    ) async throws -> HealthStatus {
        try requireSecureStorageOperationEpoch(epoch)
        if recreateAdapter {
            await ApiService.shared.removeAdapter(site.id)
        }

        let status = try await checkSingleSite(
            site,
            expectedSecureStorageEpoch: epoch
        )
        try requireSecureStorageOperationEpoch(epoch)
        try await storage.mergeHealthStatuses([site.id: status.toJson()])
        return status
    }

    func checkSingleSite(
        _ site: SiteConfig,
        expectedSecureStorageEpoch: SiteHealthSecureStorageOperationEpoch? = nil
    ) async throws -> HealthStatus {
        if let expected = expectedSecureStorageEpoch {
            return try await runWithSecureStorageOperationEpoch(expected) {
                [self] epoch in
                try await checkSingleSiteInCurrentEpoch(site, epoch)
            }
        }
        return try await runWithCurrentSecureStorageOperation { [self] epoch in
            try await checkSingleSiteInCurrentEpoch(site, epoch)
        }
    }

    private func checkSingleSiteInCurrentEpoch(
        _ site: SiteConfig,
        _ epoch: SiteHealthSecureStorageOperationEpoch
    ) async throws -> HealthStatus {
        try requireSecureStorageOperationEpoch(epoch)
        if !site.features.supportMemberProfile {
            do {
                let adapter = try await ApiService.shared.getAdapter(site)
                let ok = try await adapter.testConnection()
                try requireSecureStorageOperationEpoch(epoch)
                if !ok {
                    throw ConnectionTestFailure(message: "连接测试失败")
                }
                return HealthStatus(
                    ok: true,
                    notApplicable: true,
                    message: "连接正常（不支持用户资料）",
                    username: nil,
                    profile: nil,
                    updatedAt: Date()
                )
            } catch let error as SecureStorageUnavailableError {
                throw error
            } catch {
                return HealthStatus(
                    ok: false,
                    notApplicable: true,
                    message: errorText(error),
                    username: nil,
                    profile: nil,
                    updatedAt: Date()
                )
            }
        }

        do {
            let adapter = try await ApiService.shared.getAdapter(site)
            let profile = try await adapter.fetchMemberProfile(
                apiKey: site.apiKey
            )
            try requireSecureStorageOperationEpoch(epoch)
            return HealthStatus(
                ok: true,
                message: "正常",
                username: profile.username,
                profile: profile,
                updatedAt: Date()
            )
        } catch let error as SecureStorageUnavailableError {
            throw error
        } catch {
            return HealthStatus(
                ok: false,
                message: errorText(error),
                username: nil,
                profile: nil,
                updatedAt: Date()
            )
        }
    }

    private func shouldRefresh() async throws -> Bool {
        let lastCheck = await storage.loadLastSiteHealthRefreshCheck()
        if lastCheck == nil {
            return true
        }

        return Date().timeIntervalSince(lastCheck!) >= Self.refreshInterval
    }

    private func errorText(_ error: Error) -> String {
        if let siteError = error as? SiteException {
            return siteError.descriptionText
        }
        return String(describing: error)
    }

    private func captureSecureStorageOperationEpoch()
        throws -> SiteHealthSecureStorageOperationEpoch
    {
        if let inherited = Self.currentEpoch {
            try requireSecureStorageOperationEpoch(inherited)
            return inherited
        }
        if !storage.canAccessSensitiveStorage {
            throw SecureStorageUnavailableError(
                code: storage.secureStorageFailureCode ?? "secure_storage_not_ready"
            )
        }
        return SiteHealthSecureStorageOperationEpoch(
            generation: generations.synchronize(currentSecureStorageSignature())
        )
    }

    private func isSecureStorageOperationEpochCurrent(
        _ epoch: SiteHealthSecureStorageOperationEpoch
    ) -> Bool {
        storage.canAccessSensitiveStorage &&
            generations.synchronize(currentSecureStorageSignature()) == epoch.generation
    }

    private func requireSecureStorageOperationEpoch(
        _ epoch: SiteHealthSecureStorageOperationEpoch
    ) throws {
        if !isSecureStorageOperationEpochCurrent(epoch) {
            throw SecureStorageUnavailableError(
                code: "secure_storage_operation_invalidated"
            )
        }
    }

    private func currentSecureStorageSignature() -> String {
        if storage.canAccessSensitiveStorage {
            return "ready"
        }
        return "unavailable:" + (storage.secureStorageFailureCode ?? "")
    }

    private func runWithSecureStorageOperationEpoch<T>(
        _ epoch: SiteHealthSecureStorageOperationEpoch,
        _ operation: (SiteHealthSecureStorageOperationEpoch) async throws -> T
    ) async throws -> T {
        try requireSecureStorageOperationEpoch(epoch)
        if let inherited = Self.currentEpoch, inherited != epoch {
            throw SecureStorageUnavailableError(
                code: "secure_storage_operation_invalidated"
            )
        }
        return try await Self.$currentEpoch.withValue(epoch) {
            try await operation(epoch)
        }
    }

    private func runWithCurrentSecureStorageOperation<T>(
        _ operation: (SiteHealthSecureStorageOperationEpoch) async throws -> T
    ) async throws -> T {
        if let inherited = Self.currentEpoch {
            try requireSecureStorageOperationEpoch(inherited)
            return try await operation(inherited)
        }
        if storage.canAccessSensitiveStorage {
            let epoch = try captureSecureStorageOperationEpoch()
            return try await runWithSecureStorageOperationEpoch(epoch, operation)
        }
        try await storage.initializeSecureStorage()
        if let inherited = Self.currentEpoch {
            try requireSecureStorageOperationEpoch(inherited)
            return try await operation(inherited)
        }
        let epoch = try captureSecureStorageOperationEpoch()
        return try await runWithSecureStorageOperationEpoch(epoch, operation)
    }
}