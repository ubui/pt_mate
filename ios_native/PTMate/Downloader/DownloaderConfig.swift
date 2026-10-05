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