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
    var frontmostAppIsFullscreen: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
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
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if screens.contains(where: { $0.equalTo(rect) }) { return true }
        }
        return false
    }

    private func notify() { onEnvironmentChange?() }
}
