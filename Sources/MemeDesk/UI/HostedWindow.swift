import AppKit
import SwiftUI

/// 把任意 SwiftUI 视图塞进一个普通 NSWindow。
///
/// 素材库 / 欢迎页刻意不用 WindowGroup：LSUIElement 应用里 AppKit 托管窗口的行为可预测得多，
/// 也不用跟 MenuBarExtra 抢 window scene。
@MainActor
final class HostedWindowController<Content: View>: NSWindowController {

    /// - Parameter id: 窗口位置的记忆键，**必须与语言无关**（用固定的英文标识）。
    ///   以前这里用的是窗口标题，而标题是本地化的 —— 一换语言，`setFrameAutosaveName`
    ///   的键就变了，窗口位置被当成"第一次打开"而重新居中。
    convenience init(id: String, title: String, size: NSSize, content: Content) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.setFrameAutosaveName("MemeDesk.\(id)")
        self.init(window: window)
    }

    func show() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum WelcomeWindow {
    @MainActor static func show() -> NSWindowController {
        let controller = HostedWindowController(id: "welcome", title: L(.welcomeTitle),
                                                size: NSSize(width: 460, height: 400),
                                                content: WelcomeView())
        controller.show()
        return controller
    }
}

enum LibraryWindow {
    @MainActor static var current: HostedWindowController<LibraryView>?

    @MainActor static func show() {
        if let current {
            current.show()
            return
        }
        let controller = HostedWindowController(id: "library", title: L(.library),
                                                size: NSSize(width: 680, height: 520),
                                                content: LibraryView())
        controller.window?.delegate = WindowLifecycle.shared
        LibraryWindow.current = controller
        controller.show()
    }
}

enum SettingsWindow {
    @MainActor static var current: HostedWindowController<SettingsView>?

    @MainActor static func show() {
        if let current {
            current.show()
            return
        }
        let controller = HostedWindowController(id: "settings", title: L(.settingsTitle),
                                                size: NSSize(width: 520, height: 620),
                                                content: SettingsView())
        controller.window?.delegate = WindowLifecycle.shared
        SettingsWindow.current = controller
        controller.show()
    }
}

/// 窗口关闭时释放引用，保证下次仍能重新打开。
final class WindowLifecycle: NSObject, NSWindowDelegate {
    static let shared = WindowLifecycle()

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow else { return }
        Task { @MainActor in
            if LibraryWindow.current?.window === closed {
                LibraryWindow.current = nil
            }
            if SettingsWindow.current?.window === closed {
                SettingsWindow.current = nil
            }
        }
    }
}
