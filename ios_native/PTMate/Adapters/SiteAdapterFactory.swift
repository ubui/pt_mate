import Foundation

enum SiteAdapterFactory {
    static func createAdapter(_ config: SiteConfig) throws -> SiteAdapter {
        switch config.siteType {
        case .mteam:
            return MTeamAdapter()
        case .nexusphp:
            return NexusPHPAdapter()
        case .nexusphpweb:
            throw ModelsError.argumentException(
                "NexusPHPWeb 适配器在 iOS 端尚未实现，站点 \(config.name)（\(config.siteType.id)）暂不支持"
            )
        case .web:
            return WebAdapter()
        case .rousi:
            return RousiAdapter()
        case .gazelle:
            return GazelleAdapter()
        case .unit3d:
            return Unit3dAdapter()
        }
    }
}