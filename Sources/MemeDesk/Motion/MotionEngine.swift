import CoreGraphics
import Foundation

/// 提供六种运动行为的纯几何计算，不持有任何 AppKit 对象。
///
/// 所有模式共用一条原则：**外部改了位置就以外部为准**（拖过之后立刻接着运动，不会弹回去）。
/// 任何模式在完全静止后都会进入睡眠状态，不再产生计算。
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
    }

    private var states: [UUID: State] = [:]

    func reset(_ id: UUID) { states.removeValue(forKey: id) }

    func wake(_ id: UUID) { states[id]?.sleeping = false }

    /// 抛掷：拖拽松手后带着惯性继续飞（目前用于 gravity / bounce 模式）。
    func throwVelocity(_ id: UUID, vx: CGFloat, vy: CGFloat) {
        var state = states[id] ?? State()
        state.vx = vx
        state.vy = vy
        state.sleeping = false
        states[id] = state
    }

    /// - Returns: 新的中心点（屏幕坐标）。
    func update(id: UUID,
                motion: MotionMode,
                frame: CGRect,
                dt: CFTimeInterval,
                speed: Double,
                screen: CGRect,
                mouse: CGPoint) -> CGPoint {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard motion != .still, speed > 0.001, dt > 0, screen.width > 0 else {
            states.removeValue(forKey: id)
            return center
        }

        var state = states[id] ?? State()
        // 外部改动过位置（拖拽或窗口布局）→ 以外部为准重新锚定，避免跳回旧坐标
        if state.lastCenter == .zero || Self.distance(state.lastCenter, center) > 2 {
            state.lastCenter = center
            state.anchor = center
            state.nextDecision = 0
        }
        if state.sleeping { return center }

        let halfW = frame.width / 2
        let halfH = frame.height / 2
        let minX = screen.minX + halfW
        let maxX = screen.maxX - halfW
        let minY = screen.minY + halfH
        let maxY = screen.maxY - halfH
        guard maxX > minX, maxY > minY else { return center }

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
                // 用 id 做种子，保证每个实例初始方向不同但可复现
                let seed = UInt64(abs(id.hashValue))
                let angle = Double(seed % 360) * .pi / 180
                let v: CGFloat = 90 * CGFloat(speed)
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
            state.vy -= g * CGFloat(step) * CGFloat(speed)
            x += state.vx * CGFloat(step) * CGFloat(speed)
            y += state.vy * CGFloat(step) * CGFloat(speed)
            if x <= minX { x = minX; state.vx = abs(state.vx) * 0.7 }
            if x >= maxX { x = maxX; state.vx = -abs(state.vx) * 0.7 }
            if y <= minY {
                y = minY
                state.vy = abs(state.vy) * 0.55
                state.vx *= 0.9
                // 能量耗尽就休眠，彻底停止计算
                if abs(state.vy) < 12 {
                    state.vy = 0
                    state.vx *= 0.75
                    if abs(state.vx) < 4 { state.vx = 0; state.sleeping = true }
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
