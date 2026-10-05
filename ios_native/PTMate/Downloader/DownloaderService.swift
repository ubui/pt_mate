import Foundation

private final class DownloaderConfigChangeBus: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]

    func makeStream() -> AsyncStream<String> {
        let id = UUID()
        return AsyncStream { continuation in
            self.lock.lock()
            self.continuations[id] = continuation
            self.lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func send(_ configId: String) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets {
            continuation.yield(configId)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}

actor DownloaderService {
    static let shared = DownloaderService()

    nonisolated let configChangeStream: AsyncStream<String>

    private let storageService: StorageService
    private let configChangeBus: DownloaderConfigChangeBus

    init(storageService: StorageService = .shared) {
        self.storageService = storageService
        let bus = DownloaderConfigChangeBus()
        self.configChangeBus = bus
        self.configChangeStream = bus.makeStream()
    }

    func clearCache() async {
        await DownloaderFactory.shared.clearCache()
    }

    func clearConfigCache(_ configId: String) async {
        await DownloaderFactory.shared.clearConfigCache(configId)
    }

    func notifyConfigChanged(_ configId: String) async {
        await clearConfigCache(configId)
        configChangeBus.send(configId)
    }

    func getClient(
        config: DownloaderConfig,
        password: String
    ) async throws -> DownloaderClient {
        let storage = storageService
        return try await DownloaderFactory.shared.getClient(
            config: config,
            password: password,
            onConfigUpdated: { updatedConfig in
                Task {
                    await DownloaderService.persistConfigUpdate(
                        updatedConfig,
                        storageService: storage
                    )
                }
            }
        )
    }

    func testConnection(
        config: DownloaderConfig,
        password: String
    ) async throws {
        try await DownloaderFactory.shared.testConnection(
            config: config,
            password: password
        )
    }

    func getTransferInfo(
        config: DownloaderConfig,
        password: String
    ) async throws -> TransferInfo {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        return try await client.getTransferInfo()
    }

    func getServerState(
        config: DownloaderConfig,
        password: String
    ) async throws -> ServerState {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        return try await client.getServerState()
    }

    func getTasks(
        config: DownloaderConfig,
        password: String,
        params: GetTasksParams? = nil
    ) async throws -> [DownloadTask] {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        return try await client.getTasks(params: params)
    }

    func addTask(
        config: DownloaderConfig,
        password: String,
        params: AddTaskParams,
        siteConfig: SiteConfig? = nil
    ) async throws {
        var effectiveParams = params
        let siteName = siteConfig?.name.trimmingCharacters(in: .whitespaces)
        if config.type.supportsTags,
           let siteName,
           !siteName.isEmpty,
           await storageService.loadAutoAddSiteTag() {
            let siteTag = "站点/\(siteName)"
            var tags = params.tags ?? []
            if !tags.contains(siteTag) {
                tags.append(siteTag)
            }
            effectiveParams = params.copyWith(tags: tags)
        }

        let addParams = effectiveParams
        let client = try await getClient(config: config, password: password)
        try await TimeoutRetry.retryOnTimeout {
            try await client.addTask(addParams, siteConfig: siteConfig)
        }
    }

    func pauseTasks(
        config: DownloaderConfig,
        password: String,
        hashes: [String]
    ) async throws {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        try await client.pauseTasks(hashes)
    }

    func resumeTasks(
        config: DownloaderConfig,
        password: String,
        hashes: [String]
    ) async throws {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        try await client.resumeTasks(hashes)
    }

    func deleteTasks(
        config: DownloaderConfig,
        password: String,
        hashes: [String],
        deleteFiles: Bool = false
    ) async throws {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        try await client.deleteTasks(hashes, deleteFiles: deleteFiles)
    }

    func getCategories(
        config: DownloaderConfig,
        password: String
    ) async throws -> [String] {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        return try await client.getCategories()
    }

    func getTags(
        config: DownloaderConfig,
        password: String
    ) async throws -> [String] {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        return try await client.getTags()
    }

    func getVersion(
        config: DownloaderConfig,
        password: String
    ) async throws -> String {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        return try await client.getVersion()
    }

    func getPaths(
        config: DownloaderConfig,
        password: String
    ) async throws -> [String] {
        let client = try await DownloaderFactory.shared.getClient(
            config: config,
            password: password
        )
        return try await client.getPaths()
    }

    func getUpdatedConfigAndSave(
        config: DownloaderConfig,
        password: String,
        autoSave: Bool = true
    ) async -> DownloaderConfig {
        if let qbittorrentConfig = config as? QbittorrentConfig,
           let version = qbittorrentConfig.version,
           !version.isEmpty {
            return config
        }

        do {
            let version = try await getVersion(config: config, password: password)

            let updatedConfig: DownloaderConfig
            if let qbittorrentConfig = config as? QbittorrentConfig {
                updatedConfig = qbittorrentConfig.copyWith(version: version)
            } else {
                updatedConfig = config
            }

            if autoSave {
                await saveUpdatedConfig(updatedConfig)
            }

            return updatedConfig
        } catch {
            return config
        }
    }

    func pauseTask(
        config: DownloaderConfig,
        password: String,
        hash: String
    ) async throws {
        try await pauseTasks(
            config: config,
            password: password,
            hashes: [hash]
        )
    }

    func resumeTask(
        config: DownloaderConfig,
        password: String,
        hash: String
    ) async throws {
        try await resumeTasks(
            config: config,
            password: password,
            hashes: [hash]
        )
    }

    func deleteTask(
        config: DownloaderConfig,
        password: String,
        hash: String,
        deleteFiles: Bool = false
    ) async throws {
        try await deleteTasks(
            config: config,
            password: password,
            hashes: [hash],
            deleteFiles: deleteFiles
        )
    }

    private func saveUpdatedConfig(_ updatedConfig: DownloaderConfig) async {
        do {
            let allConfigMaps = try await storageService.loadDownloaderConfigs()
            var allConfigs = try allConfigMaps.map { configMap in
                try DownloaderConfig.fromJson(configMap)
            }
            let defaultId = await storageService.loadDefaultDownloaderId()

            var configUpdated = false
            for index in allConfigs.indices {
                if allConfigs[index].id == updatedConfig.id {
                    allConfigs[index] = updatedConfig
                    configUpdated = true
                    break
                }
            }

            if configUpdated {
                try await storageService.saveDownloaderConfigs(
                    allConfigs,
                    defaultId: defaultId
                )

                await clearConfigCache(updatedConfig.id)
            }
        } catch {
        }
    }

    private static func persistConfigUpdate(
        _ updatedConfig: DownloaderConfig,
        storageService: StorageService
    ) async {
        do {
            var configs = try await storageService.loadDownloaderConfigs()
            let currentDefaultId = await storageService.loadDefaultDownloaderId()

            let configIndex = configs.firstIndex { configMap in
                (configMap["id"] as? String) == updatedConfig.id
            }
            if let configIndex {
                configs[configIndex] = updatedConfig.toJson()
                let parsedConfigs = try configs.map { configMap in
                    try DownloaderConfig.fromJson(configMap)
                }
                try await storageService.saveDownloaderConfigs(
                    parsedConfigs,
                    defaultId: currentDefaultId
                )
            }
        } catch {
        }
    }
}