import Foundation

enum DownloaderType: String, CaseIterable {
    case qbittorrent
    case transmission
    case rutorrent

    var value: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .qbittorrent:
            return "qBittorrent"
        case .transmission:
            return "Transmission"
        case .rutorrent:
            return "ruTorrent"
        }
    }

    var supportsTags: Bool {
        switch self {
        case .qbittorrent, .transmission:
            return true
        case .rutorrent:
            return false
        }
    }

    static func fromString(_ value: String) throws -> DownloaderType {
        for type in DownloaderType.allCases {
            if type.value == value {
                return type
            }
        }
        throw ModelsError.argumentException("Unknown downloader type: \(value)")
    }
}

class DownloaderConfig: Encodable, Equatable, Hashable {
    let id: String
    let name: String
    let type: DownloaderType
    let host: String
    let port: Int
    let username: String
    let password: String
    let useLocalRelay: Bool
    let allowSelfSignedCert: Bool
    let version: String?

    fileprivate init(
        id: String,
        name: String,
        type: DownloaderType,
        host: String,
        port: Int,
        username: String,
        password: String,
        useLocalRelay: Bool = false,
        allowSelfSignedCert: Bool = false,
        version: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useLocalRelay = useLocalRelay
        self.allowSelfSignedCert = allowSelfSignedCert
        self.version = version
    }

    class func fromJson(_ json: [String: Any]) throws -> DownloaderConfig {
        let typeStr = try JSONCast.optionalString(json["type"])
            ?? "qbittorrent"
        let type = try DownloaderType.fromString(typeStr)

        switch type {
        case .qbittorrent:
            return try QbittorrentConfig.fromJson(json)
        case .transmission:
            return try TransmissionConfig.fromJson(json)
        case .rutorrent:
            return try RuTorrentConfig.fromJson(json)
        }
    }

    func toJson() -> [String: Any] {
        var config: [String: Any] = [
            "host": host,
            "port": port,
            "username": username,
            "password": password,
            "useLocalRelay": useLocalRelay,
            "allowSelfSignedCert": allowSelfSignedCert,
        ]
        if let version {
            config["version"] = version
        }
        return [
            "id": id,
            "name": name,
            "type": type.value,
            "config": config,
        ]
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        useLocalRelay: Bool? = nil,
        allowSelfSignedCert: Bool? = nil,
        version: String? = nil
    ) -> DownloaderConfig {
        fatalError("DownloaderConfig.copyWith must be overridden")
    }

    var defaultPort: Int {
        fatalError("DownloaderConfig.defaultPort must be overridden")
    }

    fileprivate static func configFields(
        from json: [String: Any],
        defaultPort: Int
    ) throws -> (
        id: String,
        name: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        useLocalRelay: Bool,
        allowSelfSignedCert: Bool,
        version: String?
    ) {
        let config: [String: Any]
        if let raw = json.firstValue("config") {
            config = try JSONCast.map(raw)
        } else {
            config = json
        }

        var id = ""
        if let raw = json.firstValue("id") {
            id = try JSONCast.string(raw)
        }

        var name = ""
        if let raw = json.firstValue("name") {
            name = try JSONCast.string(raw)
        }

        var host = ""
        if let raw = config.firstValue("host") {
            host = try JSONCast.string(raw)
        }

        var port = defaultPort
        if let raw = config.firstValue("port") {
            port = try JSONCast.int(raw)
        }

        var username = ""
        if let raw = config.firstValue("username") {
            username = try JSONCast.string(raw)
        }

        var password = ""
        if let raw = config.firstValue("password") {
            password = try JSONCast.string(raw)
        }

        let useLocalRelay = try config.coalesceBool(
            "useLocalRelay",
            default: false
        )
        let allowSelfSignedCert = try config.coalesceBool(
            "allowSelfSignedCert",
            default: false
        )

        var version: String?
        if let raw = config.firstValue("version") {
            version = try JSONCast.string(raw)
        }

        return (
            id: id,
            name: name,
            host: host,
            port: port,
            username: username,
            password: password,
            useLocalRelay: useLocalRelay,
            allowSelfSignedCert: allowSelfSignedCert,
            version: version
        )
    }

    static func == (lhs: DownloaderConfig, rhs: DownloaderConfig) -> Bool {
        ObjectIdentifier(Swift.type(of: lhs)) == ObjectIdentifier(Swift.type(of: rhs))
            && lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.host == rhs.host
            && lhs.port == rhs.port
            && lhs.username == rhs.username
            && lhs.password == rhs.password
            && lhs.useLocalRelay == rhs.useLocalRelay
            && lhs.allowSelfSignedCert == rhs.allowSelfSignedCert
            && lhs.version == rhs.version
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(Swift.type(of: self)))
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(host)
        hasher.combine(port)
        hasher.combine(username)
        hasher.combine(password)
        hasher.combine(useLocalRelay)
        hasher.combine(allowSelfSignedCert)
        hasher.combine(version)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

final class QbittorrentConfig: DownloaderConfig {
    init(
        id: String,
        name: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        useLocalRelay: Bool = false,
        allowSelfSignedCert: Bool = false,
        version: String? = nil
    ) {
        super.init(
            id: id,
            name: name,
            type: .qbittorrent,
            host: host,
            port: port,
            username: username,
            password: password,
            useLocalRelay: useLocalRelay,
            allowSelfSignedCert: allowSelfSignedCert,
            version: version
        )
    }

    override var defaultPort: Int {
        8080
    }

    override class func fromJson(_ json: [String: Any]) throws -> QbittorrentConfig {
        let fields = try configFields(from: json, defaultPort: 8080)
        return QbittorrentConfig(
            id: fields.id,
            name: fields.name,
            host: fields.host,
            port: fields.port,
            username: fields.username,
            password: fields.password,
            useLocalRelay: fields.useLocalRelay,
            allowSelfSignedCert: fields.allowSelfSignedCert,
            version: fields.version
        )
    }

    override func copyWith(
        id: String? = nil,
        name: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        useLocalRelay: Bool? = nil,
        allowSelfSignedCert: Bool? = nil,
        version: String? = nil
    ) -> QbittorrentConfig {
        QbittorrentConfig(
            id: id ?? self.id,
            name: name ?? self.name,
            host: host ?? self.host,
            port: port ?? self.port,
            username: username ?? self.username,
            password: password ?? self.password,
            useLocalRelay: useLocalRelay ?? self.useLocalRelay,
            allowSelfSignedCert: allowSelfSignedCert ?? self.allowSelfSignedCert,
            version: version ?? self.version
        )
    }
}

final class TransmissionConfig: DownloaderConfig {
    init(
        id: String,
        name: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        useLocalRelay: Bool = false,
        allowSelfSignedCert: Bool = false,
        version: String? = nil
    ) {
        super.init(
            id: id,
            name: name,
            type: .transmission,
            host: host,
            port: port,
            username: username,
            password: password,
            useLocalRelay: useLocalRelay,
            allowSelfSignedCert: allowSelfSignedCert,
            version: version
        )
    }

    override var defaultPort: Int {
        9091
    }

    override class func fromJson(_ json: [String: Any]) throws -> TransmissionConfig {
        let fields = try configFields(from: json, defaultPort: 9091)
        return TransmissionConfig(
            id: fields.id,
            name: fields.name,
            host: fields.host,
            port: fields.port,
            username: fields.username,
            password: fields.password,
            useLocalRelay: fields.useLocalRelay,
            allowSelfSignedCert: fields.allowSelfSignedCert,
            version: fields.version
        )
    }

    override func copyWith(
        id: String? = nil,
        name: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        useLocalRelay: Bool? = nil,
        allowSelfSignedCert: Bool? = nil,
        version: String? = nil
    ) -> TransmissionConfig {
        TransmissionConfig(
            id: id ?? self.id,
            name: name ?? self.name,
            host: host ?? self.host,
            port: port ?? self.port,
            username: username ?? self.username,
            password: password ?? self.password,
            useLocalRelay: useLocalRelay ?? self.useLocalRelay,
            allowSelfSignedCert: allowSelfSignedCert ?? self.allowSelfSignedCert,
            version: version ?? self.version
        )
    }
}

final class RuTorrentConfig: DownloaderConfig {
    init(
        id: String,
        name: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        useLocalRelay: Bool = true,
        allowSelfSignedCert: Bool = false,
        version: String? = nil
    ) {
        super.init(
            id: id,
            name: name,
            type: .rutorrent,
            host: host,
            port: port,
            username: username,
            password: password,
            useLocalRelay: useLocalRelay,
            allowSelfSignedCert: allowSelfSignedCert,
            version: version
        )
    }

    override var defaultPort: Int {
        80
    }

    override class func fromJson(_ json: [String: Any]) throws -> RuTorrentConfig {
        let fields = try configFields(from: json, defaultPort: 80)
        return RuTorrentConfig(
            id: fields.id,
            name: fields.name,
            host: fields.host,
            port: fields.port,
            username: fields.username,
            password: fields.password,
            useLocalRelay: fields.useLocalRelay,
            allowSelfSignedCert: fields.allowSelfSignedCert,
            version: fields.version
        )
    }

    override func copyWith(
        id: String? = nil,
        name: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        useLocalRelay: Bool? = nil,
        allowSelfSignedCert: Bool? = nil,
        version: String? = nil
    ) -> RuTorrentConfig {
        RuTorrentConfig(
            id: id ?? self.id,
            name: name ?? self.name,
            host: host ?? self.host,
            port: port ?? self.port,
            username: username ?? self.username,
            password: password ?? self.password,
            useLocalRelay: useLocalRelay ?? self.useLocalRelay,
            allowSelfSignedCert: allowSelfSignedCert ?? self.allowSelfSignedCert,
            version: version ?? self.version
        )
    }
}

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
