import AppKit
import Foundation
import ServiceManagement

/// 开机自启。SMAppService 是 macOS 13 起唯一的现代做法（取代 LSSharedFileList）。
enum LoginItem {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[MemeDesk] 开机自启设置失败: %@", error.localizedDescription)
        }
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// 可直接显示在 UI 上的状态说明。
    static func statusDescription() -> String {
        switch SMAppService.mainApp.status {
        case .enabled: return L(.loginEnabled)
        case .requiresApproval: return L(.loginNeedsApproval)
        case .notRegistered: return L(.loginNotFound)
        case .notFound: return L(.loginNotFound)
        @unknown default: return L(.loginUnknown)
        }
    }
}
