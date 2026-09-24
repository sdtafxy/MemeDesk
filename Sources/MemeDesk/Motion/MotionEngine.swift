import CoreGraphics
import Foundation

/// 提供六种运动行为的纯几何计算，不持有任何 AppKit 对象。
///
/// 所有模式共用一条原则：**外部改了位置就以外部为准**（拖过之后接着运动，不会弹回去）。
/// 任何模式在完全静止后都会进入睡眠状态，不再产生计算。
///
/// ⚠️ **拖拽期间必须 `hold(_:)`** —— 手正按着的时候绝不能让引擎参与，
/// 否则它会和鼠标抢窗口位置（抽搐）、并在被拖着的时候攒下速度（松手瞬间砸下去）。
/// 拖拽由 `Stage.setDragging(_:_:)` 转发过来。
final class MotionEngine {

    private struct State {
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var time: TimeInterval = 0
        var anchor: CGPoint = .zero
        var lastCenter: CGPoint = .zero
        var wanderTarget: CGPoint = .zero
        var nextDecision: TimeInterval = 0
        var sleeping = false
        /// 用户正拖着它。见 `hold(_:)`。
        var held = false
    }

    private var states: [UUID: State] = [:]

    func reset(_ id: UUID) { states.removeValue(forKey: id) }

    func wake(_ id: UUID) { states[id]?.sleeping = false }

    /// 用户开始拖拽这个实例：**暂停它的物理积分**，速度归零。
    ///
    /// ⚠️ 必须有这个，否则拖拽期间运动引擎和鼠标会**同时**改窗口位置：
    /// 引擎按 30Hz 把窗口往下拽、鼠标事件下一帧又把它拉回指针处，
    /// 两者互相覆盖 —— 用户看到的就是"贴纸在鼠标底下不受控制地抽搐"。
    /// 更糟的是 `vy` 会在被拖着的过程中继续累积重力，松手瞬间以极大速度砸下去。
    ///
    /// 注意这**不是**"唤醒"。以前这里只做了 `sleeping = false`（让拖拽能把落定的
    /// 重力贴纸弄醒），结果正是上面那两条：拖一下就抽搐、松手就飞出去。
    func hold(_ id: UUID) {
        var state = states[id] ?? State()
        state.held = true
        state.vx = 0
        state.vy = 0
        state.sleeping = false
        states[id] = state
    }

    /// 拖拽结束：解除暂停。速度保持归零，让它从静止重新开始，
    /// 而不是带着拖拽期间攒下的东西飞出去。
    ///
    /// （"甩出去"是另一个功能，用 `throwVelocity`；目前全项目没有调用点。）
    func release(_ id: UUID) {
        guard var state = states[id] else { return }
        state.held = false
        state.vx = 0
        state.vy = 0
        state.sleeping = false
        states[id] = state
    }

    /// 这些 id 里还有没有"醒着"的运动状态 —— 供 `Stage` 决定要不要留着那条 30Hz 循环。
    ///
    /// 还没有状态的算**醒着**：那只是还没被 tick 过，一 tick 就会动。
    /// 没有这个查询的话，一个"已经全部落定"的桌面会白白留着一条永不空转的定时器，
    /// 与 `FrameTicker` / 本文件的头注释（"完全静止后不再产生计算"）都矛盾。
    func hasAwakeMotion(_ ids: [UUID]) -> Bool {
        ids.contains { states[$0]?.sleeping != true }
    }

    /// 抛掷：拖拽松手后带着惯性继续飞（目前用于 gravity / bounce 模式）。
    func throwVelocity(_ id: UUID, vx: CGFloat, vy: CGFloat) {
        var state = states[id] ?? State()
        state.vx = vx
        state.vy = vy
        state.sleeping = false
        states[id] = state
    }

    /// - Returns: 新的中心点（屏幕坐标）；`nil` 表示**这一帧别动它**
    ///   （拖拽中、已睡眠、`dt == 0`、屏幕尺寸拿不到 —— 返回 nil 让调用方连
    ///   `applyMotion` 都跳过，从根上避免跟鼠标抢位置）。
    func update(id: UUID,
                motion: MotionMode,
                frame: CGRect,
                dt: CFTimeInterval,
                speed: Double,
                screen: CGRect,
                mouse: CGPoint) -> CGPoint? {
        let center = CGPoint(x: frame.midX, y: frame.midY)

        // 运动被关掉（或屏幕尺寸拿不到）—— 这才是真的"不再需要状态"，清掉。
        guard motion != .still, speed > 0.001, screen.width > 0 else {
            states.removeValue(forKey: id)
            return nil
        }

        // ⚠️ `dt == 0` 只是"这一帧没有推进时间"，**不是**"运动被关掉了"，所以不能清状态。
        //
        // `FrameTicker.reschedule()` 每次都会把 `lastTimestamp` 归零，于是重启后的第一帧
        // dt 恒为 0；而定时器在暂停/恢复、帧率协商、全屏切换时都会重启。
        // 以前这里和上面共用一个 guard，把累积的速度、相位、游走目标全丢掉 ——
        // 表现就是"暂停再恢复后，已经在吊床上静止的贴纸又掉一次"。
        guard dt > 0 else { return nil }

        var state = states[id] ?? State()
        // 外部改动过位置（拖拽或窗口布局）→ 以外部为准重新锚定，避免跳回旧坐标。
        if state.lastCenter == .zero || Self.distance(state.lastCenter, center) > 2 {
            state.lastCenter = center
            state.anchor = center
            state.nextDecision = 0
            if !state.held { state.sleeping = false }
        }

        // ⚠️ 用户正拖着它 —— 这一帧绝对不插手。
        //
        // 位置照样认（上面已经认过并写回 `lastCenter`），但**不积分**：
        // 既不会跟鼠标抢窗口位置（那就是"抽搐"），也不会在被拖着的过程中
        // 白白攒起 `vy`（那就是松手瞬间的"跌落"）。
        if state.held {
            states[id] = state
            return nil
        }

        if state.sleeping { return nil }

        let halfW = frame.width / 2
        let halfH = frame.height / 2
        let minX = screen.minX + halfW
        let maxX = screen.maxX - halfW
        let minY = screen.minY + halfH
        let maxY = screen.maxY - halfH
        guard maxX > minX, maxY > minY else { return nil }

        let step = min(dt, 1.0 / 20) // 掉帧时不要穿模
        state.time += Double(step)
        var x = center.x
        var y = center.y

        switch motion {
        case .still:
            break

        case .float:
            // 呼吸：竖直正弦 + 轻微左右摆
            let amp = 8.0 * CGFloat(speed)
            y = state.anchor.y + sin(state.time * 1.1) * amp
            x = state.anchor.x + sin(state.time * 0.53) * amp * 0.4

        case .bounce:
            if state.vx == 0 && state.vy == 0 {
                // 用 id 做种子，保证每个实例初始方向不同但可复现。
                // ⚠️ speed **不要**在这里乘 —— 下面位移处还会乘一次，
                // 两次相乘就把滑块变成了平方标度（0.5× 时只有 1/4 速度）。
                let seed = UInt64(abs(id.hashValue))
                let angle = Double(seed % 360) * .pi / 180
                let v: CGFloat = 90
                state.vx = cos(angle) * v
                state.vy = sin(angle) * v
            }
            x += state.vx * CGFloat(step) * CGFloat(speed)
            y += state.vy * CGFloat(step) * CGFloat(speed)
            if x <= minX { x = minX; state.vx = abs(state.vx) }
            if x >= maxX { x = maxX; state.vx = -abs(state.vx) }
            if y <= minY { y = minY; state.vy = abs(state.vy) }
            if y >= maxY { y = maxY; state.vy = -abs(state.vy) }

        case .gravity:
            let g: CGFloat = 1400
            // 同理：加速度里不乘 speed，只在位移处乘一次。
            // 这样滑块既线性、又能对"飞行途中改速度"立刻生效。
            state.vy -= g * CGFloat(step)
            x += state.vx * CGFloat(step) * CGFloat(speed)
            y += state.vy * CGFloat(step) * CGFloat(speed)
            if x <= minX { x = minX; state.vx = abs(state.vx) * 0.7 }
            if x >= maxX { x = maxX; state.vx = -abs(state.vx) * 0.7 }
            if y <= minY {
                y = minY
                state.vy = abs(state.vy) * 0.55
                state.vx *= 0.9
                // 能量耗尽就休眠，彻底停止计算。
                // ⚠️ 判据要按**物理速度**（即乘上 speed）比，否则同一个"看着已经停了"
                // 画面，在滑块不同位置会对应不同的阈值，休眠时机随速度飘。
                if abs(state.vy) * CGFloat(speed) < 12 {
                    state.vy = 0
                    state.vx *= 0.75
                    if abs(state.vx) * CGFloat(speed) < 4 { state.vx = 0; state.sleeping = true }
                }
            }

        case .followCursor:
            let k = min(1, CGFloat(step) * 5 * CGFloat(speed))
            x += (mouse.x - x) * k
            y += (mouse.y - y) * k

        case .wander:
            if state.time >= state.nextDecision {
                state.nextDecision = state.time + Double.random(in: 1.2...3.2)
                let reachable: CGFloat = 120 * CGFloat(speed)
                state.wanderTarget = CGPoint(
                    x: min(max(center.x + CGFloat.random(in: -reachable...reachable), minX), maxX),
                    y: min(max(center.y + CGFloat.random(in: -reachable...reachable), minY), maxY)
                )
            }
            let v: CGFloat = 55 * CGFloat(speed)
            let dx = state.wanderTarget.x - x
            let dy = state.wanderTarget.y - y
            let len = max(sqrt(dx * dx + dy * dy), 0.01)
            if len > 2 {
                x += (dx / len) * v * CGFloat(step)
                y += (dy / len) * v * CGFloat(step)
            }
        }

        x = min(max(x, minX), maxX)
        y = min(max(y, minY), maxY)
        state.lastCenter = CGPoint(x: x, y: y)
        states[id] = state
        return state.lastCenter
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }
}
