import Foundation
import SwiftUI

// MARK: - Language

/// 界面语言选择。`system` 会跟随 macOS 的首选语言。
public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans
    case english

    public var id: String { rawValue }

    /// 语言选择项自己的标签。语言名一律用该语言的母语书写，这是惯例。
    public var name: String {
        switch self {
        case .system: return Localization.shared[.followSystem]
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

// MARK: - Keys

/// 所有面向用户的文案。新增文案请先在这里登记，编译器会保证两个语种都不漏。
public enum LKey: String, Sendable {

    // 通用
    case followSystem
    case untitled
    case settings
    case refresh
    case opacity
    case speed
    case mirror
    case clickThrough
    case lock
    case hide
    case duplicate
    case pause
    case resume
    case quit

    // 菜单栏面板
    case appTitle
    case paused
    case onDesktopCount
    case addStickerTip
    case emptyTitle
    case emptyBody
    case addFirst
    case pauseAll
    case showAll
    case hideAll
    case clearDesk
    case removeFromDesk
    case layerPosition
    case motion

    // 素材库
    case library
    case addFiles
    case addAll
    case bundledSamples
    case onDeskCount
    case dropToAdd
    case dropHintTitle
    case dropHintBody

    // 欢迎页
    case welcomeTitle
    case tagline
    case tip1
    case tip2
    case tip3
    case tip4
    case chooseStickers
    case openLibrary
    case openSettings

    // 设置
    case settingsTitle
    case language
    case placement
    case defaultSize
    case snapToEdges
    case muteByDefault
    case restoreSession
    case performance
    case decodePixelLimit
    case decodeHint
    case pauseWhenOccluded
    case hideOnFullscreen
    case pauseOnBattery
    case motionSpeed
    case startup
    case launchAtLogin
    case statusLabel
    case about
    case aboutVersion
    case aboutNote
    case aboutCLI
    case instanceCount
    case openSamples

    // 开机自启状态
    case loginEnabled
    case loginNeedsApproval
    case loginNotFound
    case loginUnknown

    // 图层
    case layerBehindIcons
    case layerOnDesktop
    case layerFloating
    case layerBehindIconsHint
    case layerOnDesktopHint
    case layerFloatingHint

    // 运动行为
    case motionStill
    case motionFloat
    case motionBounce
    case motionGravity
    case motionFollowCursor
    case motionWander

    // 右键菜单
    case menuSize
    case restoreOriginalSize
    case menuRotation
    case rotateLeft
    case rotateRight
    case rotationReset
    case mute
    case lockDetailed
    case revealInFinder
    case fileMissing
    case decodeFailed
    case videoUnplayable

    // 文件面板
    case pickerMessage
    case pickerPrompt

    // 素材类型
    case kindAnimated
    case kindStill
    case kindVideo

    // 更新
    case updateSection
    case updateCurrentVersion
    case updateAutoCheck
    case updateAutoInstall
    case updateCheckNow
    case updateChecking
    case updateUpToDate
    case updateAvailable
    case updateDownloading
    case updateReady
    case updateInstalling
    case updateInstallNow
    case updateDownloadNow
    case updateSkip
    case updateNotes
    case updateLastChecked
    case updateNeverChecked
    case updateErrorTitle
    case updateManualHint
    case updateNotWritable
    case updateRevealDownload
    case updateShowLog
    case updateOpenRelease
    case updateBadgeTip
    case updateNoFeed
    case updateRateLimited
    case updateBadResponse
    case updateHTTPError
    case updateNoArchive
    case updateChecksumFailed
    case updateSignatureFailed
    case updateVerificationUnavailable
    case updateWrongBundle
    case updateUnarchiveFailed
    case updateInstallFailed

    var text: (zh: String, en: String) {
        switch self {
        case .followSystem: return ("跟随系统", "Follow System")
        case .untitled: return ("表情包", "Sticker")
        case .settings: return ("设置", "Settings")
        case .refresh: return ("刷新", "Refresh")
        case .opacity: return ("不透明度", "Opacity")
        case .speed: return ("速度", "Speed")
        case .mirror: return ("水平镜像", "Mirror horizontally")
        case .clickThrough: return ("鼠标穿透", "Click-through")
        case .lock: return ("锁定", "Lock")
        case .hide: return ("收起", "Hide")
        case .duplicate: return ("复制一份", "Duplicate")
        case .pause: return ("暂停", "Pause")
        case .resume: return ("继续播放", "Resume")
        case .quit: return ("退出", "Quit")

        case .appTitle: return ("表情包桌面", "Sticker Desk")
        case .paused: return ("已暂停", "Paused")
        case .onDesktopCount: return ("%d 个正在桌面", "%d on desktop")
        case .addStickerTip: return ("投放新的表情包到桌面", "Place another sticker on the desktop")
        case .emptyTitle: return ("桌面还很干净", "Your desk is clean")
        case .emptyBody: return ("点击右上角的 + 号投放 GIF，或者把文件拖进素材库。", "Tap + up top to place a GIF, or drop files into the library.")
        case .addFirst: return ("投放第一个表情包", "Add your first sticker")
        case .pauseAll: return ("全部暂停", "Pause all")
        case .showAll: return ("全部显示", "Show all")
        case .hideAll: return ("全部收起", "Hide all")
        case .clearDesk: return ("清空桌面", "Clear desk")

        case .removeFromDesk: return ("从桌面移除", "Remove from desk")
        case .layerPosition: return ("图层位置", "Layer")
        case .motion: return ("运动行为", "Motion")

        case .library: return ("素材库", "Library")
        case .addFiles: return ("添加文件…", "Add Files…")
        case .addAll: return ("全部投放", "Add All")
        case .bundledSamples: return ("内置示例", "Bundled Samples")
        case .onDeskCount: return ("桌面上的 %d 个", "%d on desk")
        case .dropToAdd: return ("松手即投放桌面", "Drop to place on the desktop")
        case .dropHintTitle: return ("把 GIF / PNG / MP4 拖到这里", "Drop GIF / PNG / MP4 here")
        case .dropHintBody: return ("右键单击桌面上的表情包，可以调出它的菜单。", "Right-click any sticker on the desktop to open its menu.")

        case .welcomeTitle: return ("欢迎使用 MemeDesk", "Welcome to MemeDesk")
        case .tagline: return ("让你的表情包在桌面上常驻循环播放", "Keep your favourite memes looping on the desktop")
        case .tip1: return ("拖动移动，按住 Option 拖动缩放，滚轮微调大小", "Drag to move, Option-drag to resize, scroll to fine-tune")
        case .tip2: return ("右键呼出菜单：图层、行为、速度、镜像、复制", "Right-click for layer, motion, speed, mirror and duplicate")
        case .tip3: return ("全屏看片、锁屏、切到电池时会自动安静下来", "It goes quiet on full-screen apps, lock screen and battery power")
        case .tip4: return ("不占用 Dock，全部操作都在菜单栏里", "No Dock icon — everything lives in the menu bar")
        case .chooseStickers: return ("选择表情包…", "Choose Stickers…")
        case .openLibrary: return ("打开素材库", "Open Library")
        case .openSettings: return ("先看设置", "Open Settings")

        case .settingsTitle: return ("MemeDesk 设置", "MemeDesk Settings")
        case .language: return ("语言", "Language")
        case .placement: return ("投放", "Placement")
        case .defaultSize: return ("新表情包边长", "Default size")
        case .snapToEdges: return ("拖拽时自动吸边", "Snap to screen edges while dragging")
        case .muteByDefault: return ("视频默认静音", "Mute videos by default")
        case .restoreSession: return ("下次启动恢复上次桌面", "Restore the last session on launch")
        case .performance: return ("性能", "Performance")
        case .decodePixelLimit: return ("解码像素上限", "Decode pixel limit")
        case .decodeHint: return ("超过这个尺寸的 GIF 会先降采样再解码。调低＝更省；想要极致清楚就调高。", "GIFs larger than this are downsampled before decoding. Lower it to save power, raise it for maximum sharpness.")
        case .pauseWhenOccluded: return ("被遮挡时暂停播放", "Pause playback when fully occluded")
        case .hideOnFullscreen: return ("全屏应用在前台时收起", "Hide when a full-screen app is in front")
        case .pauseOnBattery: return ("使用电池时暂停", "Pause on battery power")
        case .motionSpeed: return ("运动行为速度", "Motion speed")
        case .startup: return ("开机", "Startup")
        case .launchAtLogin: return ("登录时自动启动", "Launch at login")
        case .statusLabel: return ("状态：%@", "Status: %@")
        case .about: return ("关于", "About")
        case .aboutVersion: return ("MemeDesk %@ · 桌面表情包播放器", "MemeDesk %@ · desktop sticker player")
        case .aboutNote: return ("界面语言、桌面布局等设置只保存在这台 Mac 上。", "Language and desk layout stay on this Mac.")
        case .aboutCLI: return ("命令行控制：open 'memedesk://hide' · 'memedesk://show' · 'memedesk://resume'", "Command line: open 'memedesk://hide' · 'memedesk://show' · 'memedesk://resume'")
        case .instanceCount: return ("当前 %d 个实例", "%d active now")
        case .openSamples: return ("打开示例素材", "Open Samples")

        case .loginEnabled: return ("已开启", "Enabled")
        case .loginNeedsApproval: return ("需要在「系统设置 → 通用 → 登录项」里手动允许一次", "Allow it once in System Settings → General → Login Items")
        case .loginNotFound: return ("未注册", "Not registered")
        case .loginUnknown: return ("未知", "Unknown")

        case .layerBehindIcons: return ("沉在图标下", "Behind desktop icons")
        case .layerOnDesktop: return ("贴伏在桌面上", "Above desktop icons")
        case .layerFloating: return ("悬浮于一切之上", "Floating above everything")
        case .layerBehindIconsHint: return ("夹在壁纸与图标之间，鼠标永远点不到它", "Sandwiched between wallpaper and icons — it never receives clicks")
        case .layerOnDesktopHint: return ("压住桌面图标，被任何 App 窗口盖住", "Covers desktop icons, sits under every app window")
        case .layerFloatingHint: return ("覆盖包括全屏视频在内的一切，慎用", "Covers everything, full-screen video included — use with care")

        case .motionStill: return ("静止", "Still")
        case .motionFloat: return ("呼吸浮动", "Breathing")
        case .motionBounce: return ("屏幕弹跳", "Screen bounce")
        case .motionGravity: return ("重力吊床", "Gravity hammock")
        case .motionFollowCursor: return ("追随鼠标", "Follow cursor")
        case .motionWander: return ("随机游荡", "Wander")

        case .menuSize: return ("大小", "Size")
        case .restoreOriginalSize: return ("还原原始像素", "Reset to native pixels")
        case .menuRotation: return ("旋转", "Rotate")
        case .rotateLeft: return ("左旋 15°", "Rotate left 15°")
        case .rotateRight: return ("右旋 15°", "Rotate right 15°")
        case .rotationReset: return ("归正", "Reset rotation")
        case .mute: return ("静音", "Mute")
        case .lockDetailed: return ("锁定（不可拖动）", "Lock (undraggable)")
        case .revealInFinder: return ("在访达中显示", "Reveal in Finder")
        case .fileMissing: return ("文件已丢失", "File missing")
        case .decodeFailed: return ("解码失败", "Decode failed")
        case .videoUnplayable: return ("无法播放这个视频", "Cannot play this video")

        case .pickerMessage: return ("挑选表情包：GIF / PNG / MP4 / MOV", "Pick stickers: GIF / PNG / MP4 / MOV")
        case .pickerPrompt: return ("投放桌面", "Place on Desk")

        case .kindAnimated: return ("动图", "Animated")
        case .kindStill: return ("静态图", "Still image")
        case .kindVideo: return ("视频", "Video")

        case .updateSection: return ("更新", "Updates")
        case .updateCurrentVersion: return ("当前版本 %@", "Current version %@")
        case .updateAutoCheck: return ("自动检查更新", "Check for updates automatically")
        case .updateAutoInstall: return ("发现新版本后自动下载并安装", "Download and install updates automatically")
        case .updateCheckNow: return ("检查更新", "Check Now")
        case .updateChecking: return ("正在检查…", "Checking…")
        case .updateUpToDate: return ("已是最新版本", "You're up to date")
        case .updateAvailable: return ("发现新版本 %@", "Version %@ is available")
        case .updateDownloading: return ("正在下载… %d%%", "Downloading… %d%%")
        case .updateReady: return ("已下载并校验通过，可以安装", "Downloaded and verified — ready to install")
        case .updateInstalling: return ("正在替换 App，马上重启…", "Replacing the app and relaunching…")
        case .updateInstallNow: return ("立即安装并重启", "Install and Relaunch")
        case .updateDownloadNow: return ("下载更新", "Download Update")
        case .updateSkip: return ("忽略此版本", "Skip This Version")
        case .updateNotes: return ("更新说明", "Release notes")
        case .updateLastChecked: return ("上次检查 %@", "Last checked %@")
        case .updateNeverChecked: return ("尚未检查过", "Never checked")
        case .updateErrorTitle: return ("更新失败", "Update failed")
        case .updateManualHint: return ("安装会在原地替换 App 本体；桌面布局、素材和设置都存在 App 之外，不受影响。", "Installing replaces the app in place. Your desk layout, stickers and settings live outside the app and are left untouched.")
        case .updateNotWritable: return ("没有权限替换 App 本体。可以在访达里手动替换，或把 App 移到你有写权限的位置再试。", "No permission to replace the app. Swap it manually in Finder, or move the app somewhere you can write to and try again.")
        case .updateRevealDownload: return ("在访达中显示", "Reveal in Finder")
        case .updateShowLog: return ("查看安装日志", "View install log")
        case .updateOpenRelease: return ("打开 Release 页面", "Open the release page")
        case .updateBadgeTip: return ("有可用的新版本", "An update is available")
        case .updateNoFeed: return ("这个构建没有配置更新源", "This build has no update feed configured")
        case .updateRateLimited: return ("GitHub 接口请求过于频繁，请稍后再试", "GitHub is rate-limiting requests — try again later")
        case .updateBadResponse: return ("更新信息无法解析", "The update information could not be read")
        case .updateHTTPError: return ("服务器返回 %d", "The server returned %d")
        case .updateNoArchive: return ("这个 Release 里没有可用的更新包", "This release has no update archive")
        case .updateChecksumFailed: return ("更新包校验和不匹配，已丢弃", "The update archive failed its checksum and was discarded")
        case .updateSignatureFailed: return ("更新包签名无效，已丢弃", "The update archive failed signature verification and was discarded")
        case .updateVerificationUnavailable: return ("拿不到校验文件，无法确认更新包是否完整", "Could not fetch verification data for the update archive")
        case .updateWrongBundle: return ("下载到的东西不是 MemeDesk，已丢弃", "The downloaded bundle is not MemeDesk — discarded")
        case .updateUnarchiveFailed: return ("更新包解压失败", "Could not unpack the update archive")
        case .updateInstallFailed: return ("安装程序没能启动", "The installer could not be started")
        }
    }
}

// MARK: - Localization

/// 界面语言中枢。SwiftUI 视图把它当 `ObservableObject` 观察，
/// 切换语言时所有已打开的面板会立即重绘。
public final class Localization: ObservableObject {

    public static let shared = Localization()

    private static let defaultsKey = "MemeDesk.language"

    @Published public private(set) var language: AppLanguage

    private var store: UserDefaults { .standard }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// 实际生效的语言：`system` 时按 macOS 首选语言判定。
    public var effective: AppLanguage {
        guard language == .system else { return language }
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("zh") ? .zhHans : .english
    }

    public func setLanguage(_ value: AppLanguage) {
        language = value
        store.set(value.rawValue, forKey: Self.defaultsKey)
    }

    public subscript(_ key: LKey) -> String {
        let pair = key.text
        return effective == .zhHans ? pair.zh : pair.en
    }
}

/// 非 SwiftUI 代码（NSMenu、NSPanel 等）的取词捷径。
public func L(_ key: LKey) -> String { Localization.shared[key] }
