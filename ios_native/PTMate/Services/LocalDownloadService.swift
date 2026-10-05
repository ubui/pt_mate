import Foundation
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

struct BatchLocalDownloadFailure {
    let itemId: String?
    let torrentName: String
    let error: String

    init(itemId: String? = nil, torrentName: String, error: String) {
        self.itemId = itemId
        self.torrentName = torrentName
        self.error = error
    }
}

struct BatchLocalDownloadResult {
    let displayPath: String?
    let savedCount: Int
    let failedItems: [BatchLocalDownloadFailure]
    let usedZipFallback: Bool

    init(
        displayPath: String?,
        savedCount: Int,
        failedItems: [BatchLocalDownloadFailure],
        usedZipFallback: Bool
    ) {
        self.displayPath = displayPath
        self.savedCount = savedCount
        self.failedItems = failedItems
        self.usedZipFallback = usedZipFallback
    }

    var failedCount: Int {
        failedItems.count
    }
}

struct TorrentDownloadItem {
    let id: String?
    let downloadUrl: String
    let torrentName: String
    let siteConfig: SiteConfig?

    init(
        id: String? = nil,
        downloadUrl: String,
        torrentName: String,
        siteConfig: SiteConfig? = nil
    ) {
        self.id = id
        self.downloadUrl = downloadUrl
        self.torrentName = torrentName
        self.siteConfig = siteConfig
    }
}

enum LocalDownloadError: Error {
    case noStoragePermission
    case emptyTorrentData
    case invalidTorrentData
    case nothingDownloaded
    case userCancelled
    case zipUnavailable
    case savePanelUnavailable
}

extension LocalDownloadError: CustomStringConvertible {
    var description: String {
        switch self {
        case .noStoragePermission:
            return "没有存储权限，无法保存文件"
        case .emptyTorrentData:
            return "下载的种子文件为空"
        case .invalidTorrentData:
            return "下载的文件不是有效的种子文件（可能是HTML登录页面）"
        case .nothingDownloaded:
            return "没有成功下载任何种子文件"
        case .userCancelled:
            return "用户取消保存"
        case .zipUnavailable:
            return "当前构建未包含 ZIPFoundation，无法打包批量种子文件"
        case .savePanelUnavailable:
            return "系统保存面板尚未初始化，无法保存种子文件"
        }
    }
}

private struct LocalDownloadZipEntry {
    let name: String
    let data: Data
}

final class LocalDownloadService: TorrentFileDownloading {
    typealias SaveHandler = (
        _ fileName: String,
        _ initialDirectory: String?,
        _ data: Data
    ) async throws -> URL?

    typealias BatchProgressHandler = (_ current: Int, _ total: Int, _ currentName: String?) -> Void

    static let shared = LocalDownloadService(
        saveHandler: LocalDownloadService.unavailableSaveHandler
    )

    static let downloadsDisplayPath = "Downloads/PT Mate"

    static let defaultSaveDialogTitle = "保存种子文件"

    static let allowedExtensions = ["zip", "torrent"]

    private let storage: StorageService
    private var saveHandler: SaveHandler

    init(
        saveHandler: @escaping SaveHandler,
        storage: StorageService = .shared
    ) {
        self.saveHandler = saveHandler
        self.storage = storage
    }

    func configureSaveHandler(_ handler: @escaping SaveHandler) {
        saveHandler = handler
    }

    private static func unavailableSaveHandler(
        _ fileName: String,
        _ initialDirectory: String?,
        _ data: Data
    ) async throws -> URL? {
        throw LocalDownloadError.savePanelUnavailable
    }

    func requestStoragePermission() async -> Bool {
        true
    }

    func getLocalDownloadDisplayPath() async -> String {
        "用户选择的位置"
    }

    func getLocalDownloadHint() async -> String {
        "将使用系统保存面板选择保存位置。"
    }

    func downloadAndSaveTorrent(
        downloadUrl: String,
        torrentName: String,
        siteConfig: SiteConfig? = nil
    ) async throws -> String? {
        let hasPermission = await requestStoragePermission()
        guard hasPermission else {
            throw LocalDownloadError.noStoragePermission
        }

        let torrentData = try await downloadTorrentData(downloadUrl, siteConfig: siteConfig)
        let fileName = buildTorrentFileName(torrentName)

        return try await saveWithPicker(fileName, torrentData)
    }

    func batchDownloadAndSave(
        items: [TorrentDownloadItem],
        onProgress: BatchProgressHandler? = nil
    ) async throws -> BatchLocalDownloadResult {
        let hasPermission = await requestStoragePermission()
        guard hasPermission else {
            throw LocalDownloadError.noStoragePermission
        }

        let savePath = try await batchDownloadAndSaveAsZipWithPicker(
            items: items,
            onProgress: onProgress
        )

        return BatchLocalDownloadResult(
            displayPath: savePath,
            savedCount: savePath == nil ? 0 : items.count,
            failedItems: [],
            usedZipFallback: true
        )
    }

    private func batchDownloadAndSaveAsZipWithPicker(
        items: [TorrentDownloadItem],
        onProgress: BatchProgressHandler?
    ) async throws -> String? {
        var entries: [LocalDownloadZipEntry] = []
        var usedFileNames: Set<String> = []

        for (index, item) in items.enumerated() {
            onProgress?(index + 1, items.count, item.torrentName)

            do {
                let torrentData = try await downloadTorrentData(
                    item.downloadUrl,
                    siteConfig: item.siteConfig
                )
                let fileName = buildTorrentFileName(item.torrentName)

                var uniqueFileName = fileName
                var counter = 1
                while usedFileNames.contains(uniqueFileName) {
                    let nameWithoutExt = fileName.replacingOccurrences(of: ".torrent", with: "")
                    uniqueFileName = "\(nameWithoutExt) (\(counter)).torrent"
                    counter += 1
                }

                usedFileNames.insert(uniqueFileName)
                entries.append(LocalDownloadZipEntry(name: uniqueFileName, data: torrentData))
            } catch {
            }
        }

        if entries.isEmpty {
            throw LocalDownloadError.nothingDownloaded
        }

        let zipData = try Self.encodeZipArchive(entries)
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return try await saveWithPicker("torrents_\(timestamp).zip", zipData)
    }

    private func downloadTorrentData(
        _ downloadUrl: String,
        siteConfig: SiteConfig?
    ) async throws -> Data {
        let torrentData = try await downloadTorrentFileCommon(downloadUrl, siteConfig: siteConfig)

        if torrentData.isEmpty {
            throw LocalDownloadError.emptyTorrentData
        }

        guard isValidTorrentData(torrentData) else {
            throw LocalDownloadError.invalidTorrentData
        }

        return torrentData
    }

    private func saveWithPicker(_ fileName: String, _ data: Data) async throws -> String? {
        let initialDirectory = await resolveInitialDirectory()

        let result = try await saveHandler(fileName, initialDirectory, data)

        guard let result else {
            return nil
        }

        let path = Self.filePickerLocation(result)
        await rememberSaveDirectory(path)

        return path
    }

    private func resolveInitialDirectory() async -> String? {
        let lastDirectory = await storage.loadLocalDownloadLastDirectory()

        if let lastDirectory {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: lastDirectory,
                isDirectory: &isDirectory
            )
            if exists && isDirectory.boolValue {
                return lastDirectory
            }
        }

        return nil
    }

    private func rememberSaveDirectory(_ filePath: String) async {
        let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        await storage.saveLocalDownloadLastDirectory(directory)
    }

    private func isValidTorrentData(_ data: Data) -> Bool {
        if data.isEmpty {
            return false
        }
        return data.first == 100
    }

    private func buildTorrentFileName(_ torrentName: String) -> String {
        var fileName = torrentName
        if !fileName.lowercased().hasSuffix(".torrent") {
            fileName = "\(fileName).torrent"
        }
        return Self.sanitizeFileName(fileName)
    }

    private static func sanitizeFileName(_ fileName: String) -> String {
        fileName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
    }

    private static func filePickerLocation(_ url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    private static func encodeZipArchive(_ entries: [LocalDownloadZipEntry]) throws -> Data {
        #if canImport(ZIPFoundation)
        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("pt_mate_local_download", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = workingDirectory.appendingPathComponent("source", isDirectory: true)
        let zipUrl = workingDirectory.appendingPathComponent("torrents.zip")

        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        for entry in entries {
            let entryUrl = sourceDirectory.appendingPathComponent(entry.name)
            try entry.data.write(to: entryUrl)
        }

        try fileManager.zipItem(at: sourceDirectory, to: zipUrl, shouldKeepParent: false)

        return try Data(contentsOf: zipUrl)
        #else
        throw LocalDownloadError.zipUnavailable
        #endif
    }
}