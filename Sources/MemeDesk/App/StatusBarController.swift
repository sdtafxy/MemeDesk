import AppKit
import Combine
import SwiftUI

/// 菜单栏常驻按钮 + 弹出面板（NSStatusItem + NSPopover）。
///
/// 面板尺寸来自 `PanelMetrics` 的算术常量，并在素材增删时主动同步，
/// 彻底避免 MenuBarExtra 那种“内容一变顶部就缩一块”的布局协商。
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var summariesSink: AnyCancellable?

    /// 弹出素材右键 NSMenu 期间，抑制“点到面板外就收起”。
    private var menuSuppression = 0

    private var isOpen: Bool { popover?.isShown == true }

    // MARK: 安装

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = AppBrand.menuBarImage()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusButtonClicked(_:))
            button.toolTip = "MemeDesk"
            button.setAccessibilityLabel("MemeDesk")
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .applicationDefined   // 收起时机自己管，NSMenu 弹出时不会被误关
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: MenuBarRootView())
        self.popover = popover

        summariesSink = Stage.shared.$summaries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.syncPanelSize() }
            }

        installMonitors()
    }

    /// 素材增删时把面板尺寸对齐到新的算术高度（面板开着也即时生效）。
    private func syncPanelSize() {
        guard let popover,
              let host = popover.contentViewController as? NSHostingController<MenuBarRootView>
        else { return }
        let size = PanelMetrics.contentSize(summaryCount: Stage.shared.summaries.count)
        host.preferredContentSize = size
        host.view.setFrameSize(size)
        popover.contentSize = size
    }

    // MARK: 开关面板

    @objc private func statusButtonClicked(_ sender: Any?) {
        togglePanel()
    }

    func togglePanel() {
        isOpen ? close() : open()
    }

    private func open() {
        guard let popover, let button = statusItem?.button else { return }
        syncPanelSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover?.performClose(nil)
    }

    // MARK: 点击外部收起 / Esc 收起

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismissIfAllowed() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            // 本地事件监听保证在主线程回调，这里显式声明给编译器看
            let result: NSEvent? = MainActor.assumeIsolated { () -> NSEvent? in
                guard let self, self.isOpen, self.menuSuppression == 0 else { return event }

                if event.type == .keyDown {
                    if event.keyCode == 53 {           // Esc
                        self.close()
                        return nil
                    }
                    return event
                }
                // 面板自己的窗口、状态栏按钮：正常分发
                let panel = self.popover?.contentViewController?.view.window
                let statusButtonWindow = self.statusItem?.button?.window
                if (panel.map({ event.window === $0 }) ?? false)
                    || (statusButtonWindow.map({ event.window === $0 }) ?? false) {
                    return event
                }
                // 点到其他任何窗口（包括桌面表情包）：收起面板
                self.close()
                return event
            }
            return result
        }
    }

    private func dismissIfAllowed() {
        guard isOpen, menuSuppression == 0 else { return }
        close()
    }

    // MARK: 右键菜单期间的保护

    func beginMenuSuppression() { menuSuppression += 1 }
    func endMenuSuppression() { menuSuppression = max(0, menuSuppression - 1) }
}
