import CoreGraphics
import Foundation

// MARK: - 窗口层级

/// 表情包窗口挂在桌面窗口栈的哪一层。
///
/// 桌面窗口层从上到下大致是：状态栏(25) > 普通窗口(0) > 桌面图标 > 壁纸(-2147483629)。
/// 我们把三种最有用的档位拎出来。
public enum LayerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 壁纸之上、桌面图标之下，观感最贴近原生桌面，代价是会被 Finder 图标盖住。
    case behindIcons
    /// 桌面图标之上、普通应用窗口之下 —— 最实用的默认值。
    case onDesktop
    /// 所有窗口之上（含全屏应用）。
    case floating

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .behindIcons: L(.layerBehindIcons)
        case .onDesktop: L(.layerOnDesktop)
        case .floating: L(.layerFloating)
        }
    }

    public var hint: String {
        switch self {
        case .behindIcons: L(.layerBehindIconsHint)
        case .onDesktop: L(.layerOnDesktopHint)
        case .floating: L(.layerFloatingHint)
        }
    }

    /// 窗口层级低于 normal(0) 时，系统会吞掉它的鼠标事件，交互必然失效。
    public var supportsInteraction: Bool { self != .behindIcons }
}

// MARK: - 运动行为

public enum MotionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case still
    case float
    case bounce
    case gravity
    case followCursor
    case wander

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .still: L(.motionStill)
        case .float: L(.motionFloat)
        case .bounce: L(.motionBounce)
        case .gravity: L(.motionGravity)
        case .followCursor: L(.motionFollowCursor)
        case .wander: L(.motionWander)
        }
    }
}

// MARK: - 几何

/// CGRect 不是 Codable，用这个替身做持久化。
public struct FrameBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }

    /// 换成中心点表达，避免尺寸变化时重心跑偏。
    public func settingCenter(_ c: CGPoint) -> FrameBox {
        FrameBox(x: c.x - width / 2, y: c.y - height / 2, width: width, height: height)
    }
}

// MARK: - 单个表情包实例

public struct StickerConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Security-Scoped Bookmark，保证重启后仍能读到用户选的文件。
    public var bookmark: Data?
    /// 屏幕坐标系（原点左下），单位：点。
    public var frame: FrameBox
    public var opacity: Double
    public var mirrored: Bool
    /// 顺时针角度。
    public var rotation: Double
    /// 播放倍速，0.25 ~ 4。
    public var rate: Double
    public var muted: Bool
    public var volume: Float
    public var clickThrough: Bool
    public var locked: Bool
    public var layerMode: LayerMode
    public var motion: MotionMode
    public var isHidden: Bool

    public init(id: UUID = UUID(),
                name: String,
                bookmark: Data? = nil,
                frame: FrameBox,
                opacity: Double = 1,
                mirrored: Bool = false,
                rotation: Double = 0,
                rate: Double = 1,
                muted: Bool = true,
                volume: Float = 0.7,
                clickThrough: Bool = false,
                locked: Bool = false,
                layerMode: LayerMode = .onDesktop,
                motion: MotionMode = .still,
                isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.frame = frame
        self.opacity = opacity
        self.mirrored = mirrored
        self.rotation = rotation
        self.rate = rate
        self.muted = muted
        self.volume = volume
        self.clickThrough = clickThrough
        self.locked = locked
        self.layerMode = layerMode
        self.motion = motion
        self.isHidden = isHidden
    }

    /// 兼容解码：老版本存档缺字段时不会整个挂掉。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? L(.untitled)
        bookmark = try? c.decode(Data.self, forKey: .bookmark)
        frame = (try? c.decode(FrameBox.self, forKey: .frame)) ?? FrameBox(x: 200, y: 200, width: 200, height: 200)
        opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? 1
        mirrored = (try? c.decode(Bool.self, forKey: .mirrored)) ?? false
        rotation = (try? c.decode(Double.self, forKey: .rotation)) ?? 0
        rate = (try? c.decode(Double.self, forKey: .rate)) ?? 1
        muted = (try? c.decode(Bool.self, forKey: .muted)) ?? true
        volume = (try? c.decode(Float.self, forKey: .volume)) ?? 0.7
        clickThrough = (try? c.decode(Bool.self, forKey: .clickThrough)) ?? false
        locked = (try? c.decode(Bool.self, forKey: .locked)) ?? false
        layerMode = (try? c.decode(LayerMode.self, forKey: .layerMode)) ?? .behindIcons
        motion = (try? c.decode(MotionMode.self, forKey: .motion)) ?? .still
        isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
    }

    private enum Keys: String, CodingKey {
        case id, name, bookmark, frame, opacity, mirrored, rotation, rate, muted, volume
        case clickThrough, locked, layerMode, motion, isHidden
    }
}
