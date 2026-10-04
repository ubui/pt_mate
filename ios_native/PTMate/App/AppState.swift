import Foundation
import Observation

/// 全局应用状态（对应 Flutter 版 `AppState` / `lib/app.dart`）。
/// 初始加载、活动站点、同步队列等逻辑在后续步骤中完善。
@Observable
final class AppState {
    var isInitialized: Bool = false
    var activeSite: SiteConfig?
}
