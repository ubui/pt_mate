import Foundation

enum BatchOperationType: String {
    case favorite
    case download
}

enum BatchItemState: String {
    case idle
    case running
    case success
    case failed
}

protocol BatchRetryContext {}

struct BatchDownloadContext: BatchRetryContext {
    var downloadToLocal: Bool
    var clientConfig: DownloaderConfig?
    var password: String?
    var category: String?
    var tags: [String]
    var savePath: String?
    var autoTMM: Bool?
    var startPaused: Bool?
    var useToken: Bool?
    var localSaveDirectory: String?
    var sitesById: [String: SiteConfig]?

    init(
        downloadToLocal: Bool = false,
        clientConfig: DownloaderConfig? = nil,
        password: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        savePath: String? = nil,
        autoTMM: Bool? = nil,
        startPaused: Bool? = nil,
        useToken: Bool? = nil,
        localSaveDirectory: String? = nil,
        sitesById: [String: SiteConfig]? = nil
    ) {
        self.downloadToLocal = downloadToLocal
        self.clientConfig = clientConfig
        self.password = password
        self.category = category
        self.tags = tags
        self.savePath = savePath
        self.autoTMM = autoTMM
        self.startPaused = startPaused
        self.useToken = useToken
        self.localSaveDirectory = localSaveDirectory
        self.sitesById = sitesById
    }

    func copyWith(
        downloadToLocal: Bool? = nil,
        clientConfig: DownloaderConfig? = nil,
        password: String? = nil,
        category: String? = nil,
        tags: [String]? = nil,
        savePath: String? = nil,
        autoTMM: Bool? = nil,
        startPaused: Bool? = nil,
        useToken: Bool? = nil,
        localSaveDirectory: String? = nil,
        sitesById: [String: SiteConfig]? = nil
    ) -> BatchDownloadContext {
        BatchDownloadContext(
            downloadToLocal: downloadToLocal ?? self.downloadToLocal,
            clientConfig: clientConfig ?? self.clientConfig,
            password: password ?? self.password,
            category: category ?? self.category,
            tags: tags ?? self.tags,
            savePath: savePath ?? self.savePath,
            autoTMM: autoTMM ?? self.autoTMM,
            startPaused: startPaused ?? self.startPaused,
            useToken: useToken ?? self.useToken,
            localSaveDirectory: localSaveDirectory ?? self.localSaveDirectory,
            sitesById: sitesById ?? self.sitesById
        )
    }
}

struct BatchFailureRecord<T> {
    var item: T
    var itemId: String
    var itemName: String
    var errorMessage: String

    init(item: T, itemId: String, itemName: String, errorMessage: String) {
        self.item = item
        self.itemId = itemId
        self.itemName = itemName
        self.errorMessage = errorMessage
    }
}

struct BatchProgressState<T> {
    var actionType: BatchOperationType
    var isRunning: Bool
    var trackedTotalCount: Int
    var runTotalCount: Int
    var runCompletedCount: Int
    var successCount: Int
    var failureCount: Int
    var currentItemName: String?
    var failedItems: [BatchFailureRecord<T>]
    var retryableContext: (any BatchRetryContext)?

    init(
        actionType: BatchOperationType,
        isRunning: Bool,
        trackedTotalCount: Int,
        runTotalCount: Int,
        runCompletedCount: Int,
        successCount: Int,
        failureCount: Int,
        currentItemName: String?,
        failedItems: [BatchFailureRecord<T>],
        retryableContext: (any BatchRetryContext)? = nil
    ) {
        self.actionType = actionType
        self.isRunning = isRunning
        self.trackedTotalCount = trackedTotalCount
        self.runTotalCount = runTotalCount
        self.runCompletedCount = runCompletedCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.currentItemName = currentItemName
        self.failedItems = failedItems
        self.retryableContext = retryableContext
    }

    func copyWith(
        actionType: BatchOperationType? = nil,
        isRunning: Bool? = nil,
        trackedTotalCount: Int? = nil,
        runTotalCount: Int? = nil,
        runCompletedCount: Int? = nil,
        successCount: Int? = nil,
        failureCount: Int? = nil,
        currentItemName: String? = nil,
        clearCurrentItemName: Bool = false,
        failedItems: [BatchFailureRecord<T>]? = nil,
        retryableContext: (any BatchRetryContext)? = nil,
        keepRetryableContext: Bool = true
    ) -> BatchProgressState<T> {
        BatchProgressState<T>(
            actionType: actionType ?? self.actionType,
            isRunning: isRunning ?? self.isRunning,
            trackedTotalCount: trackedTotalCount ?? self.trackedTotalCount,
            runTotalCount: runTotalCount ?? self.runTotalCount,
            runCompletedCount: runCompletedCount ?? self.runCompletedCount,
            successCount: successCount ?? self.successCount,
            failureCount: failureCount ?? self.failureCount,
            currentItemName: clearCurrentItemName
                ? nil
                : currentItemName ?? self.currentItemName,
            failedItems: failedItems ?? self.failedItems,
            retryableContext: keepRetryableContext
                ? (retryableContext ?? self.retryableContext)
                : retryableContext
        )
    }

    var progress: Double {
        if runTotalCount == 0 {
            return 0
        }
        return Double(runCompletedCount) / Double(runTotalCount)
    }

    var actionLabel: String {
        switch actionType {
        case .favorite:
            return "批量收藏"
        case .download:
            return "批量下载"
        }
    }

    var titleLabel: String {
        let isRetryRun = trackedTotalCount > runTotalCount
        let prefix = isRetryRun ? actionLabel + "重试" : actionLabel
        return "\(prefix) \(runCompletedCount)/\(runTotalCount)"
    }
}

func formatBatchError(_ error: Any) -> String {
    let text = String(describing: error)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("Exception: ") {
        return String(text.dropFirst(11))
    }
    return text
}

func buildBatchFailureRecords<T>(
    itemStates: [String: BatchItemState],
    itemErrors: [String: String],
    trackedItems: [String: T],
    itemNameOf: (T) -> String
) -> [BatchFailureRecord<T>] {
    var failures: [BatchFailureRecord<T>] = []
    for (itemId, item) in trackedItems {
        if itemStates[itemId] != BatchItemState.failed {
            continue
        }
        failures.append(
            BatchFailureRecord(
                item: item,
                itemId: itemId,
                itemName: itemNameOf(item),
                errorMessage: itemErrors[itemId] ?? "操作失败"
            )
        )
    }
    return failures
}

func buildBatchProgressState<T>(
    actionType: BatchOperationType,
    isRunning: Bool,
    runTotalCount: Int,
    runCompletedCount: Int,
    itemStates: [String: BatchItemState],
    itemErrors: [String: String],
    trackedItems: [String: T],
    itemNameOf: (T) -> String,
    currentItemName: String? = nil,
    retryableContext: (any BatchRetryContext)? = nil
) -> BatchProgressState<T> {
    var successCount = 0
    var failureCount = 0
    for (_, state) in itemStates {
        switch state {
        case .idle, .running:
            break
        case .success:
            successCount += 1
        case .failed:
            failureCount += 1
        }
    }

    return BatchProgressState<T>(
        actionType: actionType,
        isRunning: isRunning,
        trackedTotalCount: trackedItems.count,
        runTotalCount: runTotalCount,
        runCompletedCount: runCompletedCount,
        successCount: successCount,
        failureCount: failureCount,
        currentItemName: currentItemName,
        failedItems: buildBatchFailureRecords(
            itemStates: itemStates,
            itemErrors: itemErrors,
            trackedItems: trackedItems,
            itemNameOf: itemNameOf
        ),
        retryableContext: retryableContext
    )
}
