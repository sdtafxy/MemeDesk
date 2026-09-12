import AppKit
import CoreGraphics

extension LayerMode {
    /// 映射到 AppKit 的窗口栈层级。
    ///
    /// macOS 26 实测的窗口层级（`CGWindowLevelForKey`）：
    ///   `desktopWindow(-2147483623) < desktopIconWindow(-2147483603) ≈ 图标 < normal(0) = 应用窗口
    ///    < floating(3) < statusWindow(25) = 菜单栏 < popUpMenu(101) = 弹出菜单 < screenSaver(1000)`
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

    /// 配置要求的层级。
    ///
    /// 菜单弹出期间真实 `level` 会被临时压低，所以它才是"应该在哪一层"的依据 ——
    /// 不能拿 `level` 自己当依据，否则菜单开着时任何一次 config 回写都会把窗口
    /// 弹回原层级，又把菜单盖住。
    private var configuredLevel: NSWindow.Level

    /// 是否有菜单正弹出在本窗口上。
    private var isPresentingMenu = false

    init(frame: NSRect, mode: LayerMode) {
        configuredLevel = mode.windowLevel
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
        configuredLevel = mode.windowLevel
        syncLevel()
    }

    /// 菜单弹出 / 收起。
    ///
    /// 弹出菜单住在一个 `popUpMenu`(101) 层的窗口里，而"悬浮于一切之上"用的是
    /// `screenSaver`(1000) 层 —— 不压下去的话，菜单会被素材自己盖住，根本点不到。
    /// 只压到 100（仍高于普通窗口和菜单栏），观感几乎无变化，只是暂时低于菜单。
    func setMenuPresentation(_ active: Bool) {
        guard isPresentingMenu != active else { return }
        isPresentingMenu = active
        syncLevel()
    }

    private func syncLevel() {
        let ceiling = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        level = (isPresentingMenu && configuredLevel.rawValue > ceiling.rawValue)
            ? ceiling
            : configuredLevel
    }
}
