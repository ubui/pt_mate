import Foundation

struct MemberProfile {
    var username: String
    var bonus: Double
    var shareRate: Double
    var uploadedBytes: Int
    var downloadedBytes: Int
    var uploadedBytesString: String
    var downloadedBytesString: String
    var userId: String?
    var passKey: String?
    var authKey: String?
    var lastAccess: Date?
    var bonusPerHour: Double?
    var seedingSizeBytes: Int?

    init(
        username: String,
        bonus: Double,
        shareRate: Double,
        uploadedBytes: Int,
        downloadedBytes: Int,
        uploadedBytesString: String,
        downloadedBytesString: String,
        userId: String? = nil,
        passKey: String? = nil,
        authKey: String? = nil,
        lastAccess: Date? = nil,
        bonusPerHour: Double? = nil,
        seedingSizeBytes: Int? = nil
    ) {
        self.username = username
        self.bonus = bonus
        self.shareRate = shareRate
        self.uploadedBytes = uploadedBytes
        self.downloadedBytes = downloadedBytes
        self.uploadedBytesString = uploadedBytesString
        self.downloadedBytesString = downloadedBytesString
        self.userId = userId
        self.passKey = passKey
        self.authKey = authKey
        self.lastAccess = lastAccess
        self.bonusPerHour = bonusPerHour
        self.seedingSizeBytes = seedingSizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case username
        case name
        case bonus
        case shareRate
        case share_rate
        case uploadedBytes
        case uploaded_bytes
        case downloadedBytes
        case downloaded_bytes
        case uploadedBytesString
        case uploaded_str
        case downloadedBytesString
        case downloaded_str
        case userId
        case passKey
        case authKey
        case auth_key
        case authkey
        case lastAccess
        case last_access
        case bonusPerHour
        case bonus_per_hour
        case seedingSizeBytes
        case seedingSize
        case seederSize
    }

    static func fromJson(_ json: [String: Any]) throws -> MemberProfile {
        let usernameValue = json.firstValue("username", "name")
        let username = usernameValue.map(dartToString) ?? ""

        var bonusPerHourValue: Double?
        if let raw = json.firstValue("bonusPerHour", "bonus_per_hour") {
            bonusPerHourValue = dartLenientDouble(raw)
        }

        var seedingSizeValue: Int?
        if let raw = json.firstValue("seedingSizeBytes", "seedingSize", "seederSize") {
            seedingSizeValue = try dartLenientInt(raw)
        }

        var lastAccess: Date?
        if let raw = json.firstValue("lastAccess") {
            lastAccess = try? dartParseDateTime(dartToString(raw))
        } else if let raw = json.firstValue("last_access") {
            lastAccess = try parseDateTimeCustom(dartToString(raw), fieldName: "lastAccess")
        }

        var authKey: String?
        if let raw = json.firstValue("authKey", "auth_key", "authkey") {
            authKey = dartToString(raw)
        }

        return MemberProfile(
            username: username,
            bonus: dartLenientDouble(json.firstValue("bonus")),
            shareRate: dartLenientDouble(json.firstValue("shareRate", "share_rate")),
            uploadedBytes: try dartLenientInt(json.firstValue("uploadedBytes", "uploaded_bytes")),
            downloadedBytes: try dartLenientInt(json.firstValue("downloadedBytes", "downloaded_bytes")),
            uploadedBytesString: json.firstValue("uploadedBytesString", "uploaded_str").map(dartToString) ?? "",
            downloadedBytesString: json.firstValue("downloadedBytesString", "downloaded_str").map(dartToString) ?? "",
            userId: json.firstValue("userId").map(dartToString),
            passKey: json.firstValue("passKey").map(dartToString),
            authKey: authKey,
            lastAccess: lastAccess,
            bonusPerHour: bonusPerHourValue,
            seedingSizeBytes: seedingSizeValue
        )
    }

    func toJson() -> [String: Any] {
        var result: [String: Any] = [
            "username": username,
            "bonus": bonus,
            "shareRate": shareRate,
            "uploadedBytes": uploadedBytes,
            "downloadedBytes": downloadedBytes,
            "uploadedBytesString": uploadedBytesString,
            "downloadedBytesString": downloadedBytesString,
            "userId": anyOrNil(userId),
            "passKey": anyOrNil(passKey),
            "lastAccess": anyOrNil(lastAccess.map(dartToIso8601String)),
        ]
        if let authKey {
            result["authKey"] = authKey
        }
        if let bonusPerHour {
            result["bonusPerHour"] = bonusPerHour
        }
        if let seedingSizeBytes {
            result["seedingSizeBytes"] = seedingSizeBytes
        }
        return result
    }
}

extension MemberProfile: Codable {
    init(from decoder: Decoder) throws {
        self = try MemberProfile.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(JSONValue(toJson()))
    }
}

struct TorrentDetail {
    var descr: String
    var descrHtml: String?
    var webviewUrl: String?

    init(descr: String, descrHtml: String? = nil, webviewUrl: String? = nil) {
        self.descr = descr
        self.descrHtml = descrHtml
        self.webviewUrl = webviewUrl
    }
}

enum DownloadStatus: String {
    case none
    case downloading
    case completed
}

struct TorrentItem {
    var id: String
    var name: String
    var smallDescr: String
    var discount: DiscountType
    var discountEndTime: Date?
    var downloadUrl: String?
    var detailUrl: String?
    var description: String?
    var seeders: Int
    var leechers: Int
    var sizeBytes: Int
    var imageList: [String]
    var cover: String
    var downloadStatus: DownloadStatus
    var collection: Bool
    var createdDate: Date
    var doubanRating: String?
    var imdbRating: String?
    var isTop: Bool
    var tags: [TagType]
    var comments: Int

    init(
        id: String,
        name: String,
        smallDescr: String,
        discount: DiscountType = .normal,
        discountEndTime: Date?,
        downloadUrl: String?,
        detailUrl: String? = nil,
        description: String? = nil,
        seeders: Int,
        leechers: Int,
        sizeBytes: Int,
        createdDate: Date,
        imageList: [String],
        cover: String,
        downloadStatus: DownloadStatus = .none,
        collection: Bool = false,
        doubanRating: String? = "N/A",
        imdbRating: String? = "N/A",
        isTop: Bool = false,
        tags: [TagType] = [],
        comments: Int = 0
    ) {
        self.id = id
        self.name = name
        self.smallDescr = smallDescr
        self.discount = discount
        self.discountEndTime = discountEndTime
        self.downloadUrl = downloadUrl
        self.detailUrl = detailUrl
        self.description = description
        self.seeders = seeders
        self.leechers = leechers
        self.sizeBytes = sizeBytes
        self.createdDate = createdDate
        self.imageList = imageList
        self.cover = cover
        self.downloadStatus = downloadStatus
        self.collection = collection
        self.doubanRating = doubanRating
        self.imdbRating = imdbRating
        self.isTop = isTop
        self.tags = tags
        self.comments = comments
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        smallDescr: String? = nil,
        discount: DiscountType? = nil,
        discountEndTime: Date? = nil,
        downloadUrl: String? = nil,
        detailUrl: String? = nil,
        description: String? = nil,
        seeders: Int? = nil,
        leechers: Int? = nil,
        sizeBytes: Int? = nil,
        imageList: [String]? = nil,
        cover: String? = nil,
        downloadStatus: DownloadStatus? = nil,
        collection: Bool? = nil,
        createdDate: Date? = nil,
        isTop: Bool? = nil,
        tags: [TagType]? = nil,
        comments: Int? = nil
    ) -> TorrentItem {
        TorrentItem(
            id: id ?? self.id,
            name: name ?? self.name,
            smallDescr: smallDescr ?? self.smallDescr,
            discount: discount ?? self.discount,
            discountEndTime: discountEndTime ?? self.discountEndTime,
            downloadUrl: downloadUrl ?? self.downloadUrl,
            detailUrl: detailUrl ?? self.detailUrl,
            description: description ?? self.description,
            seeders: seeders ?? self.seeders,
            leechers: leechers ?? self.leechers,
            sizeBytes: sizeBytes ?? self.sizeBytes,
            createdDate: createdDate ?? self.createdDate,
            imageList: imageList ?? self.imageList,
            cover: cover ?? self.cover,
            downloadStatus: downloadStatus ?? self.downloadStatus,
            collection: collection ?? self.collection,
            isTop: isTop ?? self.isTop,
            tags: tags ?? self.tags,
            comments: comments ?? self.comments
        )
    }
}

struct TorrentSearchResult {
    var pageNumber: Int
    var pageSize: Int
    var total: Int
    var totalPages: Int
    var items: [TorrentItem]

    init(
        pageNumber: Int,
        pageSize: Int,
        total: Int,
        totalPages: Int,
        items: [TorrentItem]
    ) {
        self.pageNumber = pageNumber
        self.pageSize = pageSize
        self.total = total
        self.totalPages = totalPages
        self.items = items
    }
}

enum DiscountType: String {
    case normal = "NORMAL"
    case free = "FREE"
    case twoXUpload = "2xUP"
    case twoXFree = "2xFREE"
    case twoX50Percent = "2x50%"
    case zero = "ZERO"
    case percent10 = "PERCENT_10"
    case percent20 = "PERCENT_20"
    case percent30 = "PERCENT_30"
    case percent40 = "PERCENT_40"
    case percent50 = "PERCENT_50"
    case percent60 = "PERCENT_60"
    case percent70 = "PERCENT_70"
    case percent80 = "PERCENT_80"
    case percent90 = "PERCENT_90"

    var value: String {
        rawValue
    }

    var displayText: String {
        switch self {
        case .normal:
            return ""
        case .free:
            return "FREE"
        case .twoXUpload:
            return "2xUP"
        case .twoXFree:
            return "2xFREE"
        case .twoX50Percent:
            return "2x50%"
        case .zero:
            return "0"
        case .percent10:
            return "10%"
        case .percent20:
            return "20%"
        case .percent30:
            return "30%"
        case .percent40:
            return "40%"
        case .percent50:
            return "50%"
        case .percent60:
            return "60%"
        case .percent70:
            return "70%"
        case .percent80:
            return "80%"
        case .percent90:
            return "90%"
        }
    }

    var colorType: DiscountColorType {
        switch self {
        case .normal:
            return .none
        case .free, .twoXUpload, .twoXFree:
            return .green
        case .twoX50Percent:
            return .yellow
        case .zero:
            return .blue
        case .percent10, .percent20, .percent30, .percent40, .percent50,
            .percent60, .percent70, .percent80, .percent90:
            return .yellow
        }
    }
}

enum DiscountColorType: String {
    case none
    case green
    case yellow
    case blue
}

enum TagType: String, CaseIterable {
    case hot
    case official
    case chinese
    case chineseTraditional
    case mandarin
    case diy
    case complete
    case zero
    case ep
    case fourK
    case eightK
    case resolution1080
    case hdr
    case vr
    case h265
    case webDl
    case dovi
    case blueRay

    var content: String {
        switch self {
        case .hot:
            return "HOT"
        case .official:
            return "官方"
        case .chinese:
            return "中字"
        case .chineseTraditional:
            return "繁体"
        case .mandarin:
            return "国语"
        case .diy:
            return "DIY"
        case .complete:
            return "完结"
        case .zero:
            return "零魔"
        case .ep:
            return "分集"
        case .fourK:
            return "4K"
        case .eightK:
            return "8K"
        case .resolution1080:
            return "1080p"
        case .hdr:
            return "HDR"
        case .vr:
            return "VR"
        case .h265:
            return "H265"
        case .webDl:
            return "WEB-DL"
        case .dovi:
            return "DOVI"
        case .blueRay:
            return "Blu-ray"
        }
    }

    var color: UInt32 {
        switch self {
        case .hot:
            return 0xFFFF803B
        case .official:
            return 0xFF4C82AF
        case .chinese, .chineseTraditional:
            return 0xFF4CAF50
        case .mandarin:
            return 0xFF2196F3
        case .diy:
            return 0xFF795548
        case .complete, .ep:
            return 0xFF6E08CE
        case .zero:
            return 0x9F04A4EF
        case .fourK:
            return 0xFFFF9800
        case .eightK:
            return 0xFF00BCD4
        case .resolution1080:
            return 0xFF2196F3
        case .hdr:
            return 0xFF9C27B0
        case .vr:
            return 0xFF3F51B5
        case .h265:
            return 0xFF33A2D9
        case .webDl:
            return 0xFFA229B2
        case .dovi:
            return 0xFFE91E63
        case .blueRay:
            return 0xFFF44336
        }
    }

    var regex: String {
        switch self {
        case .chinese:
            return "chinese_simplified"
        case .chineseTraditional:
            return "chinese_traditional"
        case .complete:
            return #"\b完结\b|全[^\s]+集"#
        case .ep:
            return #"\bEP\d*\b|S\d+E\d+|E\d+\-E\d+|第[^\s]+集"#
        case .fourK:
            return #"\b4K\b|\b2160p\b"#
        case .eightK:
            return #"\b8K\b"#
        case .resolution1080:
            return #"\b1080p\b|x1080"#
        case .hdr:
            return #"\bHDR\b|\bHDR10\b"#
        case .vr:
            return #"［vr］|\[vr\]"#
        case .h265:
            return #"\bH\.?265\b|\bHEVC\b|\bx265\b"#
        case .webDl:
            return #"\bWEB-DL\b|\bWEBDL\b|\bWEB\.DL\b"#
        case .dovi:
            return #"\bDOVI\b|Dolby Vision|\bDV\b|杜比(视界)*"#
        case .blueRay:
            return #"\bblu-ray\b|\bbluray\b"#
        default:
            return ""
        }
    }

    private static var regexCache: [TagType: NSRegularExpression] = [:]
    private static let regexLock = NSLock()

    static func matchTags(_ text: String) -> [TagType] {
        var matchedTags: [TagType] = []
        for tag in TagType.allCases {
            if tag.regex.isEmpty {
                continue
            }
            let regExp = regex(for: tag)
            let range = NSRange(text.startIndex..., in: text)
            if regExp.firstMatch(in: text, options: [], range: range) != nil {
                matchedTags.append(tag)
            }
        }
        return matchedTags
    }

    private static func regex(for tag: TagType) -> NSRegularExpression {
        regexLock.lock()
        defer { regexLock.unlock() }
        if let cached = regexCache[tag] {
            return cached
        }
        let compiled = try! NSRegularExpression(
            pattern: tag.regex,
            options: [.caseInsensitive]
        )
        regexCache[tag] = compiled
        return compiled
    }

    func toJson() -> [String: Any] {
        [
            "name": rawValue,
            "content": content,
        ]
    }
}

struct TorrentComment {
    var id: String
    var createdDate: Date
    var lastModifiedDate: Date
    var torrentId: String
    var author: String
    var text: String
    var editedBy: String
    var subject: String

    init(
        id: String,
        createdDate: Date,
        lastModifiedDate: Date,
        torrentId: String,
        author: String,
        text: String,
        editedBy: String,
        subject: String
    ) {
        self.id = id
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
        self.torrentId = torrentId
        self.author = author
        self.text = text
        self.editedBy = editedBy
        self.subject = subject
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdDate
        case lastModifiedDate
        case torrent
        case author
        case text
        case editedBy
        case subject
    }

    static func fromJson(_ json: [String: Any]) throws -> TorrentComment {
        TorrentComment(
            id: json.firstValue("id").map(dartToString) ?? "",
            createdDate: try parseDateTimeCustom(
                json.firstValue("createdDate").map(dartToString),
                fieldName: "createdDate"
            ),
            lastModifiedDate: try parseDateTimeCustom(
                json.firstValue("lastModifiedDate").map(dartToString),
                fieldName: "lastModifiedDate"
            ),
            torrentId: json.firstValue("torrent").map(dartToString) ?? "",
            author: json.firstValue("author").map(dartToString) ?? "",
            text: json.firstValue("text").map(dartToString) ?? "",
            editedBy: json.firstValue("editedBy").map(dartToString) ?? "",
            subject: json.firstValue("subject").map(dartToString) ?? ""
        )
    }
}

extension TorrentComment: Decodable {
    init(from decoder: Decoder) throws {
        self = try TorrentComment.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }
}

struct TorrentCommentList {
    var pageNumber: Int
    var pageSize: Int
    var total: Int
    var totalPages: Int
    var comments: [TorrentComment]

    init(
        pageNumber: Int,
        pageSize: Int,
        total: Int,
        totalPages: Int,
        comments: [TorrentComment]
    ) {
        self.pageNumber = pageNumber
        self.pageSize = pageSize
        self.total = total
        self.totalPages = totalPages
        self.comments = comments
    }

    private enum CodingKeys: String, CodingKey {
        case pageNumber
        case pageSize
        case total
        case totalPages
        case data
    }

    static func fromJson(_ json: [String: Any]) throws -> TorrentCommentList {
        var list: [Any] = []
        if let raw = json.firstValue("data") {
            list = try JSONCast.list(raw)
        }

        var comments: [TorrentComment] = []
        for element in list {
            comments.append(try TorrentComment.fromJson(try JSONCast.map(element)))
        }

        return TorrentCommentList(
            pageNumber: dartParseInt(json.firstValue("pageNumber")) ?? 0,
            pageSize: dartParseInt(json.firstValue("pageSize")) ?? 0,
            total: dartParseInt(json.firstValue("total")) ?? 0,
            totalPages: dartParseInt(json.firstValue("totalPages")) ?? 0,
            comments: comments
        )
    }
}

extension TorrentCommentList: Decodable {
    init(from decoder: Decoder) throws {
        self = try TorrentCommentList.fromJson(
            try decoder.container(keyedBy: CodingKeys.self).jsonMap()
        )
    }
}
