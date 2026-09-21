import AppKit
import CoreGraphics
import Foundation

/// 环境感知：省电策略的事实来源。
///
/// 三件事必须被感知到：合盖/睡眠、切到电池、前台全屏应用。
/// 任一成立时停止解码，避免后台空转耗电。
final class EnvironmentMonitor {
    var onEnvironmentChange: (() -> Void)?

    private(set) var sleeping = false
    private var batteryCache = false
    private var batteryCheckedAt: Date = .distantPast

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true
            self?.notify()
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false
            self?.notify()
        }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true
            self?.notify()
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false
            self?.notify()
        }
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.notify()
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.notify()
        }

        // 锁屏：DistributedNotificationCenter 是唯一能拿到的公开信号
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true
            self?.notify()
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false
            self?.notify()
        }
    }

    /// 是否在用电池供电（结果缓存 30 秒 —— pmset 是一次进程调用，别每帧问）。
    var isOnBattery: Bool {
        if Date().timeIntervalSince(batteryCheckedAt) > 30 {
            batteryCache = Self.queryPowerSource()
            batteryCheckedAt = Date()
        }
        return batteryCache
    }

    private static func queryPowerSource() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g", "ps"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        // 输出形如： Now drawing from 'Battery Power'
        return text.contains("Battery Power")
    }

    /// 前台应用是否正占满某块屏幕（全屏看片 / PPT 演讲）。
    ///
    /// ⚠️ `CGWindowListCopyWindowInfo` 给的 bounds 是 **Quartz 坐标**（原点在主屏左上、y 向下），
    /// 而 `NSScreen.frame` 是 **Cocoa 坐标**（原点在主屏左下、y 向上）。
    /// 两者只在单屏时恰好相等 —— 显示器上下堆叠时 y 是镜像的，
    /// 原来的"精确相等"判断就永远不成立，`hideOnFullscreen` 等于失效。必须先换算。
    var frontmostAppIsFullscreen: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        let pid = app.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let screens = NSScreen.screens.map { $0.frame }

        for window in list where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let w = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let h = (bounds["Height"] as? NSNumber)?.doubleValue
            else { continue }
            let quartz = CGRect(x: x, y: y, width: w, height: h)
            let rect = Self.cocoaRect(fromQuartz: quartz, primaryHeight: primaryHeight)
            if screens.contains(where: { Self.covers($0, rect) }) { return true }
        }
        return false
    }

    /// Quartz 全局坐标 → Cocoa 全局坐标。
    ///
    /// 不是 `private`：这两个纯函数是这个文件里唯一有逻辑的部分，
    /// 放开才能在外部 harness 里对着真实数值断言（见 `PROJECT_CONTEXT.md` 15.3）。
    static func cocoaRect(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// 窗口是否**盖住**了整块屏幕。用容差而不是精确相等：
    /// 全屏窗口的实际 bounds 有时会差一两个点（阴影、圆角、四舍五入）。
    static func covers(_ screen: CGRect, _ window: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(window.minX - screen.minX) <= tolerance
            && abs(window.minY - screen.minY) <= tolerance
            && abs(window.width - screen.width) <= tolerance
            && abs(window.height - screen.height) <= tolerance
    }

    private func notify() { onEnvironmentChange?() }
}
