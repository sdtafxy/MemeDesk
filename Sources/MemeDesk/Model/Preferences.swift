import AppKit
import Foundation

/// 全局偏好。变更即落盘（带去抖，拖拽窗口时不会疯狂写 SSD）。
struct Preferences: Codable, Equatable {
    /// 所有运动行为的统一速度系数，0 = 全场禁用运动。
    var motionSpeed: Double = 1
    /// 全屏应用在前台时自动隐藏（省电，也不挡电影）。
    var hideOnFullscreen: Bool = true
    /// 遮挡即暂停：窗口被别的窗口完全盖住时停止解码。
    var pauseWhenOccluded: Bool = true
    /// 使用电池供电时暂停播放。
    var pauseOnBattery: Bool = false
    /// GIF 解码目标像素上限（单边）。超过会下采样，这是低占用的主开关之一。
    var decodePixelLimit: Int = 320
    /// 新增表情包的默认边长（点）。
    var defaultSize: Double = 220
    /// 退出后下次启动自动恢复上一次的桌面布局。
    var restoreSession: Bool = true
    /// 开机自启（封装 SMAppService）。
    var launchAtLogin: Bool = false
    /// 拖拽时是否吸边到 8pt 网格。
    var snapToEdges: Bool = true
    /// 视频音轨默认静音 —— 桌面常驻的东西出声通常很吵。
    var videosMutedByDefault: Bool = true

    static let `default` = Preferences()
}
