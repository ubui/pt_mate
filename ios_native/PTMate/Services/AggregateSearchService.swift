import Foundation

final class AggregateSearchService: @unchecked Sendable {
    static let shared = AggregateSearchService()

    struct ResultItem {
        let torrent: TorrentItem
        let siteName: String
        let siteId: String

        init(torrent: TorrentItem, siteName: String, siteId: String) {
            self.torrent = torrent
            self.siteName = siteName
            self.siteId = siteId
        }
    }

    struct Result {
        let items: [ResultItem]
        let errors: [String: String]
        let totalSites: Int
        let successSites: Int

        init(
            items: [ResultItem],
            errors: [String: String],
            totalSites: Int,
            successSites: Int
        ) {
            self.items = items
            self.errors = errors
            self.totalSites = totalSites
            self.successSites = successSites
        }
    }

    struct Progress {
        let totalSites: Int
        let completedSites: Int
        let currentSite: String?
        let isCompleted: Bool

        init(
            totalSites: Int,
            completedSites: Int,
            currentSite: String? = nil,
            isCompleted: Bool = false
        ) {
            self.totalSites = totalSites
            self.completedSites = completedSites
            self.currentSite = currentSite
            self.isCompleted = isCompleted
        }

        var progress: Double {
            totalSites > 0 ? Double(completedSites) / Double(totalSites) : 0.0
        }
    }

    enum SearchResult<Value> {
        case success(Value)
        case error(String)
    }

    final class CancelToken: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelledValue = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelledValue
        }

        func cancel() {
            lock.lock()
            cancelledValue = true
            lock.unlock()
        }
    }

    typealias ProgressCallback = (Progress) -> Void
    typealias SiteResultsCallback = ([ResultItem]) -> Void

    private struct SearchCategoryLookupFailure: Error, CustomStringConvertible {
        let message: String

        var description: String {
            "Exception: \(message)"
        }
    }

    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private let totalSites: Int
        private let onProgress: ProgressCallback
        private let onSiteResults: SiteResultsCallback?

        private var resultsValue: [ResultItem] = []
        private var errorsValue: [String: String] = [:]
        private var completedSitesValue = 0
        private var activeTasksValue = 0
        private var completedValue = false

        init(
            totalSites: Int,
            onProgress: @escaping ProgressCallback,
            onSiteResults: SiteResultsCallback?
        ) {
            self.totalSites = totalSites
            self.onProgress = onProgress
            self.onSiteResults = onSiteResults
        }

        var completed: Bool {
            lock.lock()
            defer { lock.unlock() }
            return completedValue
        }

        var activeTasks: Int {
            lock.lock()
            defer { lock.unlock() }
            return activeTasksValue
        }

        func beginTask() {
            lock.lock()
            activeTasksValue += 1
            lock.unlock()
        }

        func handleSiteComplete(
            site: SiteConfig,
            result: SearchResult<[TorrentItem]>
        ) {
            lock.lock()
            if completedValue {
                lock.unlock()
                return
            }
            completedSitesValue += 1
            activeTasksValue -= 1

            var siteResults: [ResultItem] = []
            var deliverSiteResults = false
            switch result {
            case .success(let torrents):
                siteResults = torrents.map {
                    ResultItem(torrent: $0, siteName: site.name, siteId: site.id)
                }
                resultsValue.append(contentsOf: siteResults)
                deliverSiteResults = !siteResults.isEmpty && onSiteResults != nil
            case .error(let message):
                errorsValue[site.id] = message
            }

            let completedSites = completedSitesValue
            let siteName = site.name
            let callback = onSiteResults
            lock.unlock()

            if deliverSiteResults {
                callback?(siteResults)
            }

            onProgress(
                Progress(
                    totalSites: totalSites,
                    completedSites: completedSites,
                    currentSite: siteName
                )
            )

            if completedSites >= totalSites {
                completeNow()
            }
        }

        func completeNow() {
            lock.lock()
            if completedValue {
                lock.unlock()
                return
            }
            completedValue = true
            let completedSites = completedSitesValue
            lock.unlock()

            onProgress(
                Progress(
                    totalSites: totalSites,
                    completedSites: completedSites,
                    isCompleted: true
                )
            )
        }

        func buildResult() -> Result {
            lock.lock()
            defer { lock.unlock() }
            return Result(
                items: resultsValue,
                errors: errorsValue,
                totalSites: totalSites,
                successSites: completedSitesValue - errorsValue.count
            )
        }
    }

    private let storage = StorageService.shared

    private init() {}

    func performAggregateSearch(
        keyword: String,
        configId: String,
        onProgress: @escaping ProgressCallback,
        maxResultsPerSite: Int = 30,
        cancelToken: CancelToken? = nil,
        targetSiteIds: Set<String>? = nil,
        onSiteResults: SiteResultsCallback? = nil
    ) async throws -> Result {
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
        guard let config = settings.searchConfigs.first(where: { $0.id == configId })
        else {
            throw ModelsError.argumentException("搜索配置不存在: \(configId)")
        }

        let allSites: [SiteConfig] = try await storage.loadSiteConfigs(
            includeApiKeys: true
        )
        let activeSites = allSites.filter { $0.isActive }
        let allSiteIds = activeSites.map { $0.id }

        let enabledSiteItems = config.getEnabledSites(allSiteIds).filter { item in
            targetSiteIds == nil || targetSiteIds!.contains(item.id)
        }

        var targetSites: [SiteConfig] = []
        var siteAdditionalParams: [String: [String: Any]?] = [:]

        for siteItem in enabledSiteItems {
            guard let siteConfig = activeSites.first(where: { $0.id == siteItem.id })
            else {
                continue
            }
            targetSites.append(siteConfig)
            siteAdditionalParams[siteItem.id] = siteItem.additionalParams
        }

        if targetSites.isEmpty {
            return Result(items: [], errors: [:], totalSites: 0, successSites: 0)
        }

        onProgress(
            Progress(
                totalSites: targetSites.count,
                completedSites: 0
            )
        )

        let maxConcurrency = settings.searchThreads <= 0 ? 1 : settings.searchThreads
        let runState = RunState(
            totalSites: targetSites.count,
            onProgress: onProgress,
            onSiteResults: onSiteResults
        )

        await withTaskGroup(of: Void.self) { group in
            var index = 0

            while true {
                if runState.completed {
                    break
                }
                if cancelToken?.isCancelled == true {
                    runState.completeNow()
                    break
                }

                var launched = false
                while runState.activeTasks < maxConcurrency && index < targetSites.count {
                    if cancelToken?.isCancelled == true {
                        break
                    }
                    let site = targetSites[index]
                    let additionalParams: [String: Any]? =
                        siteAdditionalParams[site.id] ?? nil
                    index += 1
                    runState.beginTask()
                    launched = true

                    group.addTask { [self] in
                        let result = await searchSingleSite(
                            site: site,
                            keyword: keyword,
                            maxResults: maxResultsPerSite,
                            additionalParams: additionalParams
                        )
                        runState.handleSiteComplete(site: site, result: result)
                    }
                }

                if !launched {
                    break
                }
                _ = await group.next()
            }
            group.cancelAll()
        }

        runState.completeNow()
        return runState.buildResult()
    }

    private func searchSingleSite(
        site: SiteConfig,
        keyword: String,
        maxResults: Int,
        additionalParams: [String: Any]?
    ) async -> SearchResult<[TorrentItem]> {
        do {
            if !site.features.supportTorrentSearch {
                return .error("站点不支持搜索功能")
            }

            var processedParams: [String: Any]?
            if let additionalParams {
                processedParams = additionalParams

                if processedParams?.keys.contains("selectedCategories") == true {
                    let selectedCategoryIds = processedParams?["selectedCategories"] as? [Any]
                    if let selectedCategoryIds, !selectedCategoryIds.isEmpty {
                        processedParams?.removeValue(forKey: "selectedCategories")

                        let categories = site.searchCategories

                        for categoryId in selectedCategoryIds {
                            guard
                                let rawCategoryId = categoryId as? String,
                                let category = categories.first(where: {
                                    $0.id == rawCategoryId
                                })
                            else {
                                throw SearchCategoryLookupFailure(
                                    message: "找不到分类配置: \(dartToString(categoryId))"
                                )
                            }

                            let categoryParams = category.parseParameters()
                            for (key, value) in categoryParams {
                                processedParams?[key] = value
                            }
                        }
                    }
                }
            }

            let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await ApiService.shared.searchTorrentsWithSite(
                siteConfig: site,
                keyword: trimmedKeyword.isEmpty ? nil : trimmedKeyword,
                pageNumber: 1,
                pageSize: maxResults,
                additionalParams: processedParams
            )

            return .success(result.items)
        } catch {
            return .error(errorText(error))
        }
    }

    private func errorText(_ error: Error) -> String {
        if let siteError = error as? SiteException {
            return siteError.descriptionText
        }
        return String(describing: error)
    }
}