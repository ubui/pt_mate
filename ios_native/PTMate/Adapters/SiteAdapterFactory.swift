import Foundation

enum SiteAdapterFactory {
    static func createAdapter(_ config: SiteConfig) throws -> SiteAdapter {
        switch config.siteType {
        case .mteam:
            return MTeamAdapter()
        case .nexusphp:
            return NexusPHPAdapter()
        case .nexusphpweb:
            return NexusPHPWebAdapter()
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