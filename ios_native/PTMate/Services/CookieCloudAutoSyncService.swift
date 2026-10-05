import Foundation

actor CookieCloudAutoSyncService {
    static let shared = CookieCloudAutoSyncService()

    private let storage: StorageService
    private let serviceFactory: (StorageService) -> CookieCloudService
    private var running = false

    init(
        storage: StorageService = .shared,
        serviceFactory: @escaping (StorageService) -> CookieCloudService = { storage in
            CookieCloudService(storage: storage)
        }
    ) {
        self.storage = storage
        self.serviceFactory = serviceFactory
    }

    func syncIfNeeded(force: Bool = false) async {
        guard !running else {
            return
        }
        running = true
        defer {
            running = false
        }
        do {
            try await runSyncIfNeeded(force: force)
        } catch is SecureStorageUnavailableError {
            return
        } catch {
            return
        }
    }

    private func runSyncIfNeeded(force: Bool) async throws {
        let config = try await storage.loadCookieCloudConfig()
        if !config.autoSyncEnabled || !config.isConfigured {
            return
        }
        if !force, let lastSyncAt = config.lastSyncAt {
            let dueAt = lastSyncAt.addingTimeInterval(
                Double(config.syncIntervalMinutes) * 60
            )
            if Date() < dueAt {
                return
            }
        }

        let service = serviceFactory(storage)
        let plan = try await service.fetchSyncPlan(config: config)
        let updates = plan.updates
        if updates.isEmpty {
            await storage.saveCookieCloudLastSync(
                syncedAt: Date(),
                summary: "没有可更新的站点"
            )
            return
        }
        _ = try await service.applyPlan(
            plan,
            selectedUpdates: updates,
            selectedAdditions: []
        )
    }
}
