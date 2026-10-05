import Foundation

actor DownloaderFactory {
    static let shared = DownloaderFactory()

    private var clientCache: [String: DownloaderClient] = [:]

    private var passwordCache: [String: String] = [:]

    static func getSupportedTypes() -> [DownloaderType] {
        DownloaderType.allCases
    }

    static func isTypeSupported(_ type: DownloaderType) -> Bool {
        DownloaderType.allCases.contains(type)
    }

    func getClient(
        config: DownloaderConfig,
        password: String,
        onConfigUpdated: ((DownloaderConfig) -> Void)? = nil
    ) throws -> DownloaderClient {
        let configId = config.id
        let cachedPassword = passwordCache[configId]

        if let cached = clientCache[configId], cachedPassword == password {
            return cached
        }

        clientCache.removeValue(forKey: configId)

        let client = try createClient(
            config: config,
            password: password,
            onConfigUpdated: onConfigUpdated
        )

        clientCache[configId] = client
        passwordCache[configId] = password

        return client
    }

    func testConnection(
        config: DownloaderConfig,
        password: String
    ) async throws {
        let client = try getClient(config: config, password: password)
        try await client.testConnection()
    }

    func clearCache() {
        clientCache.removeAll()
        passwordCache.removeAll()
    }

    func clearConfigCache(_ configId: String) {
        clientCache.removeValue(forKey: configId)
        passwordCache.removeValue(forKey: configId)
    }

    func getCachedClientCount() -> Int {
        clientCache.count
    }

    func hasCachedClient(_ configId: String) -> Bool {
        clientCache[configId] != nil
    }

    private func createClient(
        config: DownloaderConfig,
        password: String,
        onConfigUpdated: ((DownloaderConfig) -> Void)?
    ) throws -> DownloaderClient {
        switch config.type {
        case .qbittorrent:
            guard let qbittorrentConfig = config as? QbittorrentConfig else {
                throw ModelsError.argumentException(
                    "Invalid config type for qBittorrent: \(Swift.type(of: config))"
                )
            }
            let handler: ((QbittorrentConfig) -> Void)?
            if let onConfigUpdated {
                handler = { updatedConfig in onConfigUpdated(updatedConfig) }
            } else {
                handler = nil
            }
            return QBittorrentClient(
                config: qbittorrentConfig,
                password: password,
                onConfigUpdated: handler
            )
        case .transmission:
            guard let transmissionConfig = config as? TransmissionConfig else {
                throw ModelsError.argumentException(
                    "Invalid config type for Transmission: \(Swift.type(of: config))"
                )
            }
            let handler: ((TransmissionConfig) -> Void)?
            if let onConfigUpdated {
                handler = { updatedConfig in onConfigUpdated(updatedConfig) }
            } else {
                handler = nil
            }
            return TransmissionClient(
                config: transmissionConfig,
                password: password,
                onConfigUpdated: handler
            )
        case .rutorrent:
            guard config is RuTorrentConfig else {
                throw ModelsError.argumentException(
                    "Invalid config type for ruTorrent: \(Swift.type(of: config))"
                )
            }
            throw ModelsError.argumentException(
                "ruTorrent 下载器在 iOS 端尚未实现，当前仅支持 qBittorrent 与 Transmission"
            )
        }
    }
}