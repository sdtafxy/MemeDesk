import AppKit
import Foundation
import ServiceManagement

/// 开机自启。SMAppService 是 macOS 13 起唯一的现代做法（取代 LSSharedFileList）。
enum LoginItem {
    /// - Returns: 是否真的设置成功。
    ///   失败时调用方**不要**把它记进偏好，否则偏好和系统状态就此分家。
    ///   `SMAppService` 注册可能需要用户在「系统设置 → 通用 → 登录项」里批准，
    ///   完全可能失败 —— 以前这里只 NSLog 一句就把返回值丢掉了。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[MemeDesk] 开机自启设置失败: %@", error.localizedDescription)
            return false
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
