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

    /// 打开 URL。两种来源：`memedesk://` 自定义协议，以及**往图标上丢文件**
    /// （Finder 的"打开方式"、拖到 Dock 图标）。
    ///
    /// ⚠️ 只要实现了这个 `open urls:` 版本，AppKit 就**不再调用** `application(_:openFile:)`。
    /// 以前这里把非 `memedesk://` 的 URL 直接交给 `handleCommand`，而后者开头就
    /// `guard url.scheme == "memedesk"` 把文件 URL return 掉了 —— 结果是拖进来的文件
    /// **既没加进桌面，也没有任何提示**。文件 URL 必须在这里自己分流。
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty {
            Task { @MainActor in await Stage.shared.add(urls: files) }
        }
        for url in urls where !url.isFileURL {
            Task { @MainActor in Self.handleCommand(url) }
        }
    }

    /// 先落盘再退出。
    ///
    /// 落盘本身是**同步**的，所以存完直接放行即可。
    /// **不要**改成 `.terminateLater` + 异步 reply：那会让 `NSApp.terminate` 跑一个
    /// 嵌套 runloop 等 reply，而 reply 必须回到主 actor —— 一旦调用方正占着主 actor
    /// （更新器就是在主 actor 的闭包里调 terminate 的），reply 永远排不上，App 就退不掉了。
    /// 表现是：更新时 App 卡住不退，等在门外的 helper 换不了包。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { Stage.shared.saveNow() }
        return .terminateNow
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
