import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // LSUIElement 已经是 accessory，这里再兜一次底（防止从终端直接跑时不生效）
            NSApp.setActivationPolicy(.accessory)
            StatusBarController.shared.install()
            Stage.shared.bootstrap()
            UpdateService.shared.start()
            installKeyboardShortcuts()
            if Stage.shared.count == 0 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                _ = WelcomeWindow.show()
            }
        }
    }

    /// LSUIElement 应用没有主菜单，⌘, 这类快捷键得自己接。
    private func installKeyboardShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "," else { return event }
            Task { @MainActor in SettingsWindow.show() }
            return nil
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in Self.handleCommand(url) }
        }
    }

    /// Finder / "打开方式" 直接丢文件过来。
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        Task { @MainActor in
            await Stage.shared.add(urls: [URL(fileURLWithPath: filename)])
        }
        return true
    }

    /// 先落盘再退出。用 terminateLater 保证存档真的写完 —— 直接 terminateNow
    /// 会让异步 Task 没机会跑，下次启动就丢了桌面布局。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            Stage.shared.saveNow()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - memedesk:// URL Scheme
    //
    //  memedesk://add?file=<绝对路径，需百分比编码>
    //  memedesk://hide  |  /show  |  /pause  |  /resume  |  /clear

    @MainActor
    static func handleCommand(_ url: URL) {
        guard url.scheme?.lowercased() == "memedesk" else { return }
        switch url.host?.lowercased() ?? "" {
        case "add":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let path = components?.queryItems?.first(where: { $0.name == "file" })?.value {
                Task { await Stage.shared.add(urls: [URL(fileURLWithPath: path)]) }
            }
        case "hide":
            Stage.shared.hideAllTemporary()
        case "show":
            Stage.shared.showAll()
        case "pause":
            if !Stage.shared.globallyPaused { Stage.shared.toggleGlobalPause() }
        case "resume":
            if Stage.shared.globallyPaused { Stage.shared.toggleGlobalPause() }
        case "clear":
            Stage.shared.removeAll()
        default:
            break
        }
    }
}
