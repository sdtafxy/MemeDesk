import AppKit
import CoreGraphics

extension LayerMode {
    /// 映射到 AppKit 的窗口栈层级。
    ///
    /// macOS 桌面从底到顶大致是：
    ///   `desktopWindow(-2147483629) < desktopIconWindow(-2147483603) ≈ 图标 < normal(0) = 应用窗口
    ///    < floating(3) < statusWindow(25) = 菜单栏 < screenSaver(1000)`
    var windowLevel: NSWindow.Level {
        switch self {
        case .behindIcons:
            // 贴在壁纸之上、Finder 图标之下，观感最接近原生桌面组件。
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        case .onDesktop:
            // 比图标略高一层，Alt-Tab 切到桌面时会露出来。
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating:
            // 连全屏 App / 屏保都盖得住。
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        }
    }
}

/// 一枚 Windows Transparent: 无边框、无标题、无阴影、无背景 —— 只有内容。
final class StickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect, mode: LayerMode) {
        super.init(contentRect: frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true
        level = mode.windowLevel
        isMovableByWindowBackground = false
        animationBehavior = .none // 关掉 AppKit 默认的缩放/淡入动画
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StickerWindow is code-only; Storyboard and NIB are not supported")
    }

    /// 层级切换。低于 normal 的窗口在 Mission Control 里会被系统当壁纸处理。
    func applyLayerMode(_ mode: LayerMode) {
        level = mode.windowLevel
    }
}
