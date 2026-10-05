import Foundation
import CoreFoundation

struct TransferInfo {
    let upSpeed: Int
    let dlSpeed: Int
    let upTotal: Int
    let dlTotal: Int

    init(upSpeed: Int, dlSpeed: Int, upTotal: Int, dlTotal: Int) {
        self.upSpeed = upSpeed
        self.dlSpeed = dlSpeed
        self.upTotal = upTotal
        self.dlTotal = dlTotal
    }

    static func fromJson(_ json: [String: Any]) throws -> TransferInfo {
        var upSpeed = 0
        if let raw = json.firstValue("upSpeed") {
            upSpeed = try JSONCast.int(raw)
        }
        var dlSpeed = 0
        if let raw = json.firstValue("dlSpeed") {
            dlSpeed = try JSONCast.int(raw)
        }
        var upTotal = 0
        if let raw = json.firstValue("upTotal") {
            upTotal = try JSONCast.int(raw)
        }
        var dlTotal = 0
        if let raw = json.firstValue("dlTotal") {
            dlTotal = try JSONCast.int(raw)
        }
        return TransferInfo(
            upSpeed: upSpeed,
            dlSpeed: dlSpeed,
            upTotal: upTotal,
            dlTotal: dlTotal
        )
    }

    func toJson() -> [String: Any] {
        [
            "upSpeed": upSpeed,
            "dlSpeed": dlSpeed,
            "upTotal": upTotal,
            "dlTotal": dlTotal,
        ]
    }
}

struct ServerState {
    let freeSpaceOnDisk: Int

    init(freeSpaceOnDisk: Int) {
        self.freeSpaceOnDisk = freeSpaceOnDisk
    }

    static func fromJson(_ json: [String: Any]) throws -> ServerState {
        var freeSpaceOnDisk = 0
        if let raw = json.firstValue("freeSpaceOnDisk") {
            freeSpaceOnDisk = try JSONCast.int(raw)
        }
        return ServerState(freeSpaceOnDisk: freeSpaceOnDisk)
    }

    func toJson() -> [String: Any] {
        ["freeSpaceOnDisk": freeSpaceOnDisk]
    }
}

enum DownloadTaskState {
    static let error = "error"
    static let missingFiles = "missingFiles"
    static let uploading = "uploading"
    static let pausedUP = "pausedUP"
    static let queuedUP = "queuedUP"
    static let stalledUP = "stalledUP"
    static let checkingUP = "checkingUP"
    static let forcedUP = "forcedUP"
    static let allocating = "allocating"
    static let downloading = "downloading"
    static let metaDL = "metaDL"
    static let pausedDL = "pausedDL"
    static let queuedDL = "queuedDL"
    static let stalledDL = "stalledDL"
    static let checkingDL = "checkingDL"
    static let forcedDL = "forcedDL"
    static let stoppedDL = "stoppedDL"
    static let checkingResumeData = "checkingResumeData"
    static let moving = "moving"
    static let unknown = "unknown"

    static func isDownloading(_ state: String) -> Bool {
        return state == downloading ||
            state == forcedDL ||
            state == metaDL ||
            state == stalledDL
    }

    static func isPaused(_ state: String) -> Bool {
        return state == pausedDL || state == pausedUP
    }
}

struct DownloadTask {
    let hash: String
    let name: String
    let state: String
    let size: Int
    let progress: Double
    let dlspeed: Int
    let upspeed: Int
    let eta: Int
    let category: String
    let tags: [String]
    let completionOn: Int
    let contentPath: String
    let addedOn: Int
    let amountLeft: Int
    let ratio: Double
    let timeActive: Int
    let uploaded: Int

    init(
        hash: String,
        name: String,
        state: String,
        size: Int,
        progress: Double,
        dlspeed: Int,
        upspeed: Int,
        eta: Int,
        category: String,
        tags: [String],
        completionOn: Int,
        contentPath: String,
        addedOn: Int,
        amountLeft: Int,
        ratio: Double,
        timeActive: Int,
        uploaded: Int
    ) {
        self.hash = hash
        self.name = name
        self.state = state
        self.size = size
        self.progress = progress
        self.dlspeed = dlspeed
        self.upspeed = upspeed
        self.eta = eta
        self.category = category
        self.tags = tags
        self.completionOn = completionOn
        self.contentPath = contentPath
        self.addedOn = addedOn
        self.amountLeft = amountLeft
        self.ratio = ratio
        self.timeActive = timeActive
        self.uploaded = uploaded
    }

    var isDownloading: Bool {
        DownloadTaskState.isDownloading(state)
    }

    var isPaused: Bool {
        DownloadTaskState.isPaused(state)
    }

    static func fromJson(_ json: [String: Any]) throws -> DownloadTask {
        var hash = ""
        if let raw = json.firstValue("hash") {
            hash = try JSONCast.string(raw)
        }
        var name = ""
        if let raw = json.firstValue("name") {
            name = try JSONCast.string(raw)
        }
        var state = DownloadTaskState.unknown
        if let raw = json.firstValue("state") {
            state = try JSONCast.string(raw)
        }
        var category = ""
        if let raw = json.firstValue("category") {
            category = try JSONCast.string(raw)
        }
        var contentPath = ""
        if let raw = json.firstValue("contentPath") {
            contentPath = try JSONCast.string(raw)
        }

        return DownloadTask(
            hash: hash,
            name: name,
            state: state,
            size: downloaderIntOrParseInt(json.firstValue("size")),
            progress: downloaderDoubleOrParseDouble(json.firstValue("progress")),
            dlspeed: downloaderIntOrParseInt(json.firstValue("dlspeed")),
            upspeed: downloaderIntOrParseInt(json.firstValue("upspeed")),
            eta: downloaderIntOrParseInt(json.firstValue("eta")),
            category: category,
            tags: downloaderTags(json["tags"]),
            completionOn: downloaderIntOrParseInt(json.firstValue("completionOn")),
            contentPath: contentPath,
            addedOn: downloaderIntOrParseInt(json.firstValue("addedOn")),
            amountLeft: downloaderIntOrParseInt(json.firstValue("amountLeft")),
            ratio: downloaderDoubleOrParseDouble(json.firstValue("ratio")),
            timeActive: downloaderIntOrParseInt(json.firstValue("timeActive")),
            uploaded: downloaderIntOrParseInt(json.firstValue("uploaded"))
        )
    }

    func toJson() -> [String: Any] {
        [
            "hash": hash,
            "name": name,
            "state": state,
            "size": size,
            "progress": progress,
            "dlspeed": dlspeed,
            "upspeed": upspeed,
            "eta": eta,
            "category": category,
            "tags": tags,
            "completionOn": completionOn,
            "contentPath": contentPath,
            "addedOn": addedOn,
            "amountLeft": amountLeft,
            "ratio": ratio,
            "timeActive": timeActive,
            "uploaded": uploaded,
        ]
    }
}

struct AddTaskParams {
    let url: String
    let category: String?
    let tags: [String]?
    let savePath: String?
    let autoTMM: Bool?
    let startPaused: Bool?

    init(
        url: String,
        category: String? = nil,
        tags: [String]? = nil,
        savePath: String? = nil,
        autoTMM: Bool? = nil,
        startPaused: Bool? = nil
    ) {
        self.url = url
        self.category = category
        self.tags = tags
        self.savePath = savePath
        self.autoTMM = autoTMM
        self.startPaused = startPaused
    }

    func copyWith(
        url: String? = nil,
        category: String? = nil,
        tags: [String]? = nil,
        savePath: String? = nil,
        autoTMM: Bool? = nil,
        startPaused: Bool? = nil
    ) -> AddTaskParams {
        AddTaskParams(
            url: url ?? self.url,
            category: category ?? self.category,
            tags: tags ?? self.tags,
            savePath: savePath ?? self.savePath,
            autoTMM: autoTMM ?? self.autoTMM,
            startPaused: startPaused ?? self.startPaused
        )
    }

    static func fromJson(_ json: [String: Any]) throws -> AddTaskParams {
        var url = ""
        if let raw = json.firstValue("url") {
            url = try JSONCast.string(raw)
        }

        var tags: [String]?
        if let list = json["tags"] as? [Any] {
            tags = list.map { dartToString($0) }
        }

        let startPaused: Bool?
        if let raw = json.firstValue("startPaused") {
            if let bool = strictBool(raw) {
                startPaused = bool
            } else {
                startPaused = dartToString(raw) == "true" ? true : nil
            }
        } else {
            startPaused = nil
        }

        return AddTaskParams(
            url: url,
            category: try JSONCast.optionalString(json.firstValue("category")),
            tags: tags,
            savePath: try JSONCast.optionalString(json.firstValue("savePath")),
            autoTMM: try JSONCast.optionalBool(json.firstValue("autoTMM")),
            startPaused: startPaused
        )
    }

    func toJson() -> [String: Any] {
        var result: [String: Any] = ["url": url]
        if let category {
            result["category"] = category
        }
        if let tags {
            result["tags"] = tags
        }
        if let savePath {
            result["savePath"] = savePath
        }
        if let autoTMM {
            result["autoTMM"] = autoTMM
        }
        if let startPaused {
            result["startPaused"] = startPaused
        }
        return result
    }
}

struct GetTasksParams {
    let filter: String?
    let category: String?
    let tag: String?
    let sort: String?
    let reverse: Bool?
    let limit: Int?
    let offset: Int?

    init(
        filter: String? = nil,
        category: String? = nil,
        tag: String? = nil,
        sort: String? = nil,
        reverse: Bool? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.filter = filter
        self.category = category
        self.tag = tag
        self.sort = sort
        self.reverse = reverse
        self.limit = limit
        self.offset = offset
    }

    static func fromJson(_ json: [String: Any]) throws -> GetTasksParams {
        GetTasksParams(
            filter: try JSONCast.optionalString(json.firstValue("filter")),
            category: try JSONCast.optionalString(json.firstValue("category")),
            tag: try JSONCast.optionalString(json.firstValue("tag")),
            sort: try JSONCast.optionalString(json.firstValue("sort")),
            reverse: try JSONCast.optionalBool(json.firstValue("reverse")),
            limit: try JSONCast.optionalInt(json.firstValue("limit")),
            offset: try JSONCast.optionalInt(json.firstValue("offset"))
        )
    }

    func toJson() -> [String: Any] {
        var result: [String: Any] = [:]
        if let filter {
            result["filter"] = filter
        }
        if let category {
            result["category"] = category
        }
        if let tag {
            result["tag"] = tag
        }
        if let sort {
            result["sort"] = sort
        }
        if let reverse {
            result["reverse"] = reverse
        }
        if let limit {
            result["limit"] = limit
        }
        if let offset {
            result["offset"] = offset
        }
        return result
    }
}

private func downloaderIntOrParseInt(_ value: Any?) -> Int {
    if let int = strictIntValue(value) {
        return int
    }
    return dartParseInt(value) ?? 0
}

private func downloaderDoubleOrParseDouble(_ value: Any?) -> Double {
    if let number = value as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(),
        dartIsFloatNumber(number)
    {
        return number.doubleValue
    }
    return dartDoubleFromString(dartToString(value ?? 0)) ?? 0
}

private func downloaderTags(_ value: Any?) -> [String] {
    if let tagsString = value as? String {
        return tagsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    if let list = value as? [Any] {
        return list.map { dartToString($0) }
    }
    return []
}