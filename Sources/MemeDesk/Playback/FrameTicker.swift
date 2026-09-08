import AppKit
import Foundation
import QuartzCore

/// 全局唯一的帧驱动源。
///
/// 设计要点 —— 让 N 个实例只付出一次代价：
/// - **全局只有一个 Timer**：N 个表情包不会变成 N 路定时器互相错峰唤醒内核。
/// - **频率按需求自适应**：由当前 fps 最高的客户端决定时钟频率。
///   一个 10fps 的 GIF 只会让 Timer 跑在 15Hz 左右，而不是固定 60Hz。
/// - **空闲就停机**：没有客户端（或全局暂停）时 Timer 被彻底释放，占用是真正的 0。
/// - **用真实时钟算 dt**：即使某帧被系统调度推迟，动画进度也不会漂移。
@MainActor
final class FrameTicker {
    static let shared = FrameTicker()

    private struct Client {
        let fps: Double
        let handler: (CFTimeInterval) -> Void
    }

    private let pump = TickPump()
    private var timer: Timer?
    private var clients: [UUID: Client] = [:]
    private var lastTimestamp: CFTimeInterval = 0
    private var currentInterval: TimeInterval = 0
    private var suspended = false

    private init() {}

    /// - Parameters:
    ///   - fps: 这个客户端的期望刷新率，用于全局频率协商。
    ///   - handler: 入参为距上一帧的真实秒数（clamp 在 0.25s 内）。
    func add(id: UUID, fps: Double, handler: @escaping (CFTimeInterval) -> Void) {
        clients[id] = Client(fps: fps, handler: handler)
        reschedule()
    }

    func remove(_ id: UUID) {
        clients.removeValue(forKey: id)
        reschedule()
    }

    func contains(_ id: UUID) -> Bool { clients[id] != nil }

    /// 全局暂停（列如切到电池、合盖、锁屏）。
    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        reschedule()
    }

    var isRunning: Bool { timer != nil }

    // MARK: - 内部

    private func reschedule() {
        guard !suspended, !clients.isEmpty else {
            stopTimer()
            return
        }
        let fastest = clients.values.map { $0.fps }.max() ?? 30
        // 给一点余量，避免因为抖动丢帧；同时封顶 60Hz
        let target = min(max(fastest * 1.5, 12), 60)
        let interval = 1.0 / target
        if timer != nil, abs(interval - currentInterval) < 0.002 { return }
        stopTimer()
        currentInterval = interval
        // 手工 add 到 .common mode：拖拽窗口或打开菜单栏时也能继续走帧
        let timer = Timer(timeInterval: interval,
                          target: pump,
                          selector: #selector(TickPump.fire),
                          userInfo: nil,
                          repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        lastTimestamp = 0
        pump.onTick = { Task { @MainActor in FrameTicker.shared.tick() } }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        pump.onTick = nil
        currentInterval = 0
    }

    private func tick() {
        guard timer != nil else { return }
        let now = CACurrentMediaTime()
        let delta: CFTimeInterval
        if lastTimestamp <= 0 {
            delta = 0
        } else {
            delta = min(max(now - lastTimestamp, 0), 0.25)
        }
        lastTimestamp = now
        for client in Array(clients.values) { client.handler(delta) }
    }
}

/// NSObject 桥接：把 Timer 的 selector 回调从 @MainActor 隔离中摘出来。
private final class TickPump: NSObject {
    var onTick: (() -> Void)?

    @objc func fire() { onTick?() }
}
