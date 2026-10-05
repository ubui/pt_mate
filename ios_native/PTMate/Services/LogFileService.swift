import Foundation

enum LogFileServiceError: Error {
    case documentsDirectoryUnavailable
}

actor LogFileService {
    static let shared = LogFileService()

    private static let calendar = Calendar.current

    private var enabledValue = false
    private var sink: FileHandle?
    private var currentDate: Date?
    private var currentPath: String?
    private var pendingSinkOperation: Task<Void, Never>?

    private init() {}

    var enabled: Bool {
        enabledValue
    }

    func initialize(enabled: Bool? = nil) async {
        enabledValue = enabled ?? false
        if enabledValue {
            await ensureSinkForToday()
        }
    }

    func setEnabled(_ value: Bool) async {
        enabledValue = value
        if enabledValue {
            await ensureSinkForToday()
        } else {
            await closeSink()
        }
    }

    func append(_ line: String) {
        guard enabledValue else {
            return
        }
        let now = Date()

        let needsRotation: Bool
        if let currentDate {
            needsRotation = !Self.isSameDay(currentDate, now)
        } else {
            needsRotation = true
        }
        if needsRotation {
            rotateTo(now)
        }

        if let sink {
            let text = "[\(Self.timestamp(now))] \(line)\n"
            if let data = text.data(using: .utf8) {
                try? sink.write(contentsOf: data)
            }
        }
    }

    func currentLogFilePath() async -> String? {
        if let currentPath {
            return currentPath
        }
        await ensureSinkForToday()
        return currentPath
    }

    func createShareSnapshot() async -> URL? {
        guard enabledValue else {
            return nil
        }

        await ensureSinkForToday()
        flushSink()

        guard let sourcePath = currentPath else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: sourcePath)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        if size == 0 {
            return nil
        }

        let exportDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("log_exports", isDirectory: true)
        if FileManager.default.fileExists(atPath: exportDir.path) {
            let entities =
                (try? FileManager.default.contentsOfDirectory(
                    at: exportDir,
                    includingPropertiesForKeys: nil
                )) ?? []
            for entity in entities {
                var entityIsDirectory: ObjCBool = false
                if FileManager.default.fileExists(
                    atPath: entity.path,
                    isDirectory: &entityIsDirectory
                ), !entityIsDirectory.boolValue {
                    try? FileManager.default.removeItem(at: entity)
                }
            }
        } else {
            try? FileManager.default.createDirectory(
                at: exportDir,
                withIntermediateDirectories: true
            )
        }

        let snapshot = exportDir.appendingPathComponent(
            "pt-mate-\(Self.fileName(for: Date()))",
            isDirectory: false
        )
        do {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: sourcePath),
                to: snapshot
            )
            return snapshot
        } catch {
            return nil
        }
    }

    func logsDirectoryPath() throws -> String {
        let base = try Self.resolveBaseDir()
        let logs = base.appendingPathComponent("logs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: logs.path) {
            try FileManager.default.createDirectory(
                at: logs,
                withIntermediateDirectories: true
            )
        }
        return logs.path
    }

    func clearLogs() async throws -> Int {
        await closeSink()
        let dirPath = try logsDirectoryPath()
        let dir = URL(fileURLWithPath: dirPath)
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDirectory)
        else {
            return 0
        }

        var count = 0
        let entities =
            (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )) ?? []
        for entity in entities {
            do {
                try FileManager.default.removeItem(at: entity)
                count += 1
            } catch {
                continue
            }
        }
        currentPath = nil
        currentDate = nil
        if enabledValue {
            await ensureSinkForToday()
        }
        return count
    }

    private func rotateTo(_ date: Date) {
        currentDate = date
        Task { [weak self] in
            await self?.ensureSinkForToday()
        }
    }

    private func ensureSinkForToday() async {
        if let pending = pendingSinkOperation {
            await pending.value
            return
        }
        let operation = Task { [weak self] in
            await self?.ensureSinkForTodayLocked()
        }
        let typedOperation: Task<Void, Never> = Task { await operation.value }
        pendingSinkOperation = typedOperation
        await typedOperation.value
        pendingSinkOperation = nil
    }

    private func ensureSinkForTodayLocked() async {
        do {
            let base = try Self.resolveBaseDir()
            let logsDir = base.appendingPathComponent("logs", isDirectory: true)
            if !FileManager.default.fileExists(atPath: logsDir.path) {
                try FileManager.default.createDirectory(
                    at: logsDir,
                    withIntermediateDirectories: true
                )
            }
            let file = logsDir.appendingPathComponent(
                Self.fileName(for: Date()),
                isDirectory: false
            )
            currentPath = file.path
            await closeSink()
            if !FileManager.default.fileExists(atPath: file.path) {
                _ = FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: file)
            _ = try handle.seekToEnd()
            sink = handle
        } catch {
            sink = nil
        }
    }

    private func flushSink() {
        guard let sink else {
            return
        }
        try? sink.synchronize()
    }

    private func closeSink() async {
        flushSink()
        if let sink {
            try? sink.close()
        }
        sink = nil
    }

    private static func resolveBaseDir() throws -> URL {
        guard
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        else {
            throw LogFileServiceError.documentsDirectoryUnavailable
        }
        return documents
    }

    private static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        let left = calendar.dateComponents([.year, .month, .day], from: a)
        let right = calendar.dateComponents([.year, .month, .day], from: b)
        return left.year == right.year && left.month == right.month
            && left.day == right.day
    }

    private static func fileName(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "app-%04d%02d%02d.log",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    private static func timestamp(_ date: Date) -> String {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }
}
