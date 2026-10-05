import Foundation

actor ApiService {
    static let shared = ApiService()

    private var adapters: [String: SiteAdapter] = [:]
    private var activeAdapterValue: SiteAdapter?

    private init() {}

    var activeAdapter: SiteAdapter? {
        activeAdapterValue
    }

    func initialize() async throws {
        let totalStart = Date()
        let activeSite: SiteConfig? = try await StorageService.shared.getActiveSiteConfig()
        if let activeSite {
            let initAdapterStart = Date()
            await initAdapter(activeSite)
            #if DEBUG
            print(
                "ApiService.initialize: 初始化活跃适配器耗时=\(Self.elapsedMilliseconds(since: initAdapterStart))ms"
            )
            #endif
        }
        #if DEBUG
        print("ApiService.initialize: 总耗时=\(Self.elapsedMilliseconds(since: totalStart))ms")
        #endif
    }

    func getAdapter(_ siteConfig: SiteConfig) async throws -> SiteAdapter {
        let adapterId = siteConfig.id

        if let cached = adapters[adapterId] {
            return cached
        }

        let adapter = try await createAndInitAdapter(siteConfig, logLabel: "getAdapter")
        adapters[adapterId] = adapter

        return adapter
    }

    func createTemporaryAdapter(_ siteConfig: SiteConfig) async throws -> SiteAdapter {
        try await createAndInitAdapter(
            siteConfig,
            logLabel: "createTemporaryAdapter"
        )
    }

    private func createAndInitAdapter(
        _ siteConfig: SiteConfig,
        logLabel: String
    ) async throws -> SiteAdapter {
        let adapter = try SiteAdapterFactory.createAdapter(siteConfig)
        let initStart = Date()
        try await adapter.initialize(siteConfig)
        #if DEBUG
        print(
            "ApiService.\(logLabel): 适配器(\(siteConfig.siteType.id))初始化耗时=\(Self.elapsedMilliseconds(since: initStart))ms"
        )
        #endif
        return adapter
    }

    func setActiveSite(_ siteConfig: SiteConfig) async throws {
        removeAdapter(siteConfig.id)
        activeAdapterValue = try await getAdapter(siteConfig)
    }

    func removeAdapter(_ siteId: String) {
        adapters.removeValue(forKey: siteId)
        if activeAdapterValue?.siteConfig.id == siteId {
            activeAdapterValue = nil
        }
    }

    func clearAdapters() {
        adapters.removeAll()
        activeAdapterValue = nil
    }

    private func initAdapter(_ siteConfig: SiteConfig) async {
        do {
            activeAdapterValue = try await getAdapter(siteConfig)
        } catch {
            #if DEBUG
            print("ApiService.initAdapter: 初始化站点适配器失败 (\(siteConfig.name)): \(error)")
            #endif
        }
    }

    func fetchMemberProfile(apiKey: String? = nil) async throws -> MemberProfile {
        let adapter = try requireActiveAdapter()
        return try await adapter.fetchMemberProfile(apiKey: apiKey)
    }

    func searchTorrents(
        keyword: String? = nil,
        pageNumber: Int = 1,
        pageSize: Int = 30,
        onlyFav: Int? = nil,
        additionalParams: [String: Any]? = nil
    ) async throws -> TorrentSearchResult {
        let adapter = try requireActiveAdapter()
        return try await adapter.searchTorrents(
            keyword: keyword,
            pageNumber: pageNumber,
            pageSize: pageSize,
            onlyFav: onlyFav,
            additionalParams: additionalParams
        )
    }

    func searchTorrentsWithSite(
        siteConfig: SiteConfig,
        keyword: String? = nil,
        pageNumber: Int = 1,
        pageSize: Int = 30,
        onlyFav: Int? = nil,
        additionalParams: [String: Any]? = nil
    ) async throws -> TorrentSearchResult {
        let adapter = try await getAdapter(siteConfig)
        return try await adapter.searchTorrents(
            keyword: keyword,
            pageNumber: pageNumber,
            pageSize: pageSize,
            onlyFav: onlyFav,
            additionalParams: additionalParams
        )
    }

    func fetchTorrentDetail(
        _ id: String,
        siteConfig: SiteConfig? = nil,
        description: String? = nil,
        detailUrl: String? = nil
    ) async throws -> TorrentDetail {
        if let siteConfig {
            let adapter = try await getAdapter(siteConfig)
            return try await adapter.fetchTorrentDetail(
                id,
                description: description,
                detailUrl: detailUrl
            )
        }

        let adapter = try requireActiveAdapter()
        return try await adapter.fetchTorrentDetail(
            id,
            description: description,
            detailUrl: detailUrl
        )
    }

    func fetchComments(
        _ id: String,
        pageNumber: Int = 1,
        pageSize: Int = 20,
        siteConfig: SiteConfig? = nil
    ) async throws -> TorrentCommentList {
        if let siteConfig {
            let adapter = try await getAdapter(siteConfig)
            return try await adapter.fetchComments(
                id,
                pageNumber: pageNumber,
                pageSize: pageSize
            )
        }

        let adapter = try requireActiveAdapter()
        return try await adapter.fetchComments(
            id,
            pageNumber: pageNumber,
            pageSize: pageSize
        )
    }

    func genDlToken(
        id: String,
        url: String? = nil,
        siteConfig: SiteConfig? = nil
    ) async throws -> String {
        if let url, !url.isEmpty, !url.contains("{jwt}") {
            return url
        }

        if let siteConfig {
            let adapter = try await getAdapter(siteConfig)
            return try await TimeoutRetry.retryOnTimeout {
                try await adapter.genDlToken(id: id, url: url)
            }
        }

        let adapter = try requireActiveAdapter()
        return try await TimeoutRetry.retryOnTimeout {
            try await adapter.genDlToken(id: id, url: url)
        }
    }

    func queryHistory(tids: [String]) async throws -> [String: Any] {
        let adapter = try requireActiveAdapter()
        return try await adapter.queryHistory(tids: tids)
    }

    func toggleCollection(id: String, make: Bool) async throws {
        let adapter = try requireActiveAdapter()
        try await TimeoutRetry.retryOnTimeout {
            try await adapter.toggleCollection(torrentId: id, make: make)
        }
    }

    func testConnection() async throws -> Bool {
        guard let activeAdapter = activeAdapterValue else {
            return false
        }
        return try await activeAdapter.testConnection()
    }

    func testConnectionWithSite(_ siteConfig: SiteConfig) async throws -> Bool {
        do {
            let adapter = try await getAdapter(siteConfig)
            return try await adapter.testConnection()
        } catch {
            return false
        }
    }

    private func requireActiveAdapter() throws -> SiteAdapter {
        guard let activeAdapter = activeAdapterValue else {
            throw ModelsError.argumentException("No active site adapter available")
        }
        return activeAdapter
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}