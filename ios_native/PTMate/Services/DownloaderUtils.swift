import Foundation

enum DownloaderUtilsError: Error {
    case unimplementedType(String)
}

extension DownloaderUtilsError: CustomStringConvertible {
    var description: String {
        switch self {
        case .unimplementedType(let typeName):
            return "UnimplementedError: 未实现的下载器类型: \(typeName)"
        }
    }
}

struct DownloaderIconDescriptor {
    let assetName: String
    let isVectorSvg: Bool
    let size: Double

    init(assetName: String, isVectorSvg: Bool, size: Double) {
        self.assetName = assetName
        self.isVectorSvg = isVectorSvg
        self.size = size
    }
}

enum DownloaderUtils {
    static func getDownloaderIcon(
        _ type: DownloaderType,
        size: Double? = nil
    ) throws -> DownloaderIconDescriptor {
        let iconSize = size ?? 24.0

        switch type {
        case .qbittorrent:
            return DownloaderIconDescriptor(
                assetName: "assets/logo/qBittorrent.svg",
                isVectorSvg: true,
                size: iconSize
            )
        case .transmission:
            return DownloaderIconDescriptor(
                assetName: "assets/logo/Transmission.svg",
                isVectorSvg: true,
                size: iconSize
            )
        case .rutorrent:
            return DownloaderIconDescriptor(
                assetName: "assets/logo/ruTorrent.png",
                isVectorSvg: false,
                size: iconSize
            )
        default:
            throw DownloaderUtilsError.unimplementedType(type.value)
        }
    }

    static func getDownloaderIconByType(
        _ type: DownloaderType,
        size: Double? = nil
    ) throws -> DownloaderIconDescriptor {
        try getDownloaderIcon(type, size: size)
    }

    static func getDefaultPort(_ type: DownloaderType) throws -> Int {
        switch type {
        case .qbittorrent:
            return 8080
        case .transmission:
            return 9091
        case .rutorrent:
            return 80
        default:
            throw DownloaderUtilsError.unimplementedType(type.value)
        }
    }

    static func requiresLocalRelay(_ type: DownloaderType) -> Bool {
        switch type {
        case .transmission:
            return true
        case .qbittorrent:
            return false
        case .rutorrent:
            return true
        }
    }

    static func getLocalRelayDescription(_ type: DownloaderType) -> String {
        if requiresLocalRelay(type) {
            return "\(type.displayName) 必须启用本地中转（种子文件需要先下载到本地）"
        }
        return "启用后，种子文件会先下载到本地，然后再发送给下载器"
    }

    static func formatConnectionInfo(host: String, port: Int, username: String) -> String {
        "\(host):\(port)  ·  \(username)"
    }
}