import AppKit
import Combine
import CoreGraphics
import Foundation

/// 展示给 UI 的轻量快照。
///
/// 刻意**不包含坐标**：拖拽/运动时坐标每帧都在变，
/// 若放进 @Published 会让 SwiftUI 每帧重算 body —— 常驻界面不能这么浪费。
struct StickerSummary: Identifiable, Equatable {
    var id: UUID
    var name: String
    var isHidden: Bool
    var locked: Bool
    var clickThrough: Bool
    var mirrored: Bool
    var muted: Bool
    var layerMode: LayerMode
    var motion: MotionMode
    var rate: Double
    var opacity: Double
}

/// 全局舞台：所有表情包实例的生命周期与策略中枢。
@MainActor
final class Stage: ObservableObject {

    static let shared = Stage()

    @Published private(set) var summaries: [StickerSummary] = []
    @Published var preferences: Preferences = .default
    @Published private(set) var selectedID: UUID?
    /// 临时"全场静止"，不落盘。
    @Published private(set) var globallyPaused = false

    /// 真相的来源，独立存放以便高频改写时不惊动 SwiftUI。
    private var configs: [StickerConfig] = []
    private var controllers: [UUID: StickerWindowController] = [:]
    private let motionTickerID = UUID()
    private var motionEngine = MotionEngine()
    private let environment = EnvironmentMonitor()
    private(set) var fullscreenPauseActive = false
    /// 右键菜单打开期间冻结运动引擎，菜单才不会跟着窗口跑。
    private var menuInteractionCount = 0

    private var saveWork: DispatchWorkItem?
    private var periodicSave: Timer?
    private var prefSink: AnyCancellable?
    private var selectionWatcher: NSObjectProtocol?
    /// 落在本应用之外的鼠标按下 —— 清空选中用，见 `installSelectionWatcher()`。
    private var outsideClickMonitor: Any?

    /// 关掉「下次启动恢复上次桌面」之后，这次启动的桌面是空的 ——
    /// 但那个空状态**不能**被写回存档，否则用户只要把开关拨回去，布局已经被覆盖、再也回不来。
    /// 置位期间一律拒绝落盘，直到用户真的动了桌面（见 `unfreezeArchive()` 的调用点）。
    private var archiveIsFrozen = false

    private init() {
        // 设置面板改动 → 立刻重新裁决播放策略并落盘
        prefSink = $preferences.sink { [weak self] _ in
            self?.scheduleSave()
            self?.refreshRunningState()
        }
    }

    // MARK: - 启动

    func bootstrap() {
        load()
        environment.onEnvironmentChange = { [weak self] in self?.refreshRunningState() }
        installSelectionWatcher()

        for config in configs { spawn(config) }
        publishSummaries()
        refreshRunningState()

        // 位置每帧都可能变，没必要每次都写硬盘。
        periodicSave = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.saveNow() }
        }
    }

    /// 选中框只在"用户正对着这个素材"时才有意义，于是有两条清理路径：
    ///
    /// ① 应用失去焦点（点了别的 App / 桌面）—— 传统做法；
    /// ② **任何落在本应用之外的鼠标按下**。
    ///
    /// 只留 ① 是不够的：走完一次右键菜单后，应用的激活状态往往根本没变过，
    /// `didResignActiveNotification` 自然不触发，那圈高亮就会一直挂在桌面上
    /// （真机反馈：选完"运动行为"/"图层位置"后点别处，蓝框不消失）。
    /// ② 不依赖激活状态，行为是确定的。
    private func installSelectionWatcher() {
        if selectionWatcher == nil {
            selectionWatcher = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in self.clearSelection() }
            }
        }

        guard outsideClickMonitor == nil else { return }
        // 全局监听只收"发给别人的"鼠标事件，所以点我们自己的素材不会走到这里，
        // 那时候由 StickerView.mouseDown 负责选中。鼠标类全局监听不需要辅助功能权限。
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                // 菜单开着的时候不动它，交回给弹出菜单自己的收尾逻辑。
                guard let self, self.menuInteractionCount == 0 else { return }
                self.clearSelection()
            }
        }
    }

    /// 只在真有选中时才广播，避免每次点桌面都白跑一圈控制器。
    private func clearSelection() {
        guard selectedID != nil else { return }
        select(nil)
    }

    // MARK: - 增删

    func add(urls: [URL]) async {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        var addedCount = 0
        for (offset, url) in urls.enumerated() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let kind = MediaProbe.kind(of: url)
            let size = await MediaProbe.intrinsicSize(of: url, kind: kind)
            let rawAspect = size.height > 0 ? size.width / size.height : 1
            let aspect = min(max(rawAspect, 0.35), 3.2)

            let base = preferences.defaultSize
            let width = base * aspect
            let height = base
            let step = CGFloat((configs.count + offset) % 10) * 26
            let x = min(screen.visibleFrame.minX + 90 + step, screen.visibleFrame.maxX - width - 20)
            let y = min(screen.visibleFrame.minY + 90 + step, screen.visibleFrame.maxY - height - 20)

            let config = StickerConfig(
                name: url.deletingPathExtension().lastPathComponent,
                bookmark: Bookmark.data(for: url),
                frame: FrameBox(x: x, y: y, width: width, height: height),
                muted: preferences.videosMutedByDefault,
                layerMode: .onDesktop
            )
            configs.append(config)
            spawn(config)
            addedCount += 1
        }
        // 一个都没加进来（文件都被删了）时桌面没变，保持冻结，别覆盖存档。
        if addedCount > 0 { unfreezeArchive() }
        publishSummaries()
        refreshRunningState()
        markDirty()
    }

    private func spawn(_ config: StickerConfig) {
        guard controllers[config.id] == nil else { return }
        let controller = StickerWindowController(id: config.id, config: config, stage: self)
        controllers[config.id] = controller
    }

    func remove(_ id: UUID) {
        guard index(of: id) != nil else { return }
        unfreezeArchive()
        controllers.removeValue(forKey: id)?.teardown()
        configs.removeAll { $0.id == id }
        motionEngine.reset(id)
        if selectedID == id { selectedID = nil }
        publishSummaries()
        markDirty()
    }

    func duplicate(_ id: UUID) {
        guard let cfg = config(for: id) else { return }
        unfreezeArchive()
        var copy = cfg
        copy.id = UUID()
        copy.frame = FrameBox(x: cfg.frame.x + 32, y: cfg.frame.y - 32,
                              width: cfg.frame.width, height: cfg.frame.height)
        configs.append(copy)
        spawn(copy)
        publishSummaries()
        markDirty()
    }

    func removeAll() {
        guard !configs.isEmpty else { return }
        unfreezeArchive()
        for controller in controllers.values { controller.teardown() }
        controllers.removeAll()
        configs.removeAll()
        motionEngine = MotionEngine()
        selectedID = nil
        publishSummaries()
        markDirty()
    }

    // MARK: - 属性修改

    func select(_ id: UUID?) {
        selectedID = id
        for (key, controller) in controllers {
            controller.setSelected(key == id)
        }
    }

    func config(for id: UUID) -> StickerConfig? {
        configs.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        configs.firstIndex { $0.id == id }
    }

    /// 唯一的写入口：改数据 → 应用到窗口 → 更新 UI 快照 → 落盘。
    func update(_ id: UUID, publish: Bool = true, mutate: (inout StickerConfig) -> Void) {
        guard let i = index(of: id) else { return }
        unfreezeArchive()
        mutate(&configs[i])
        let updated = configs[i]
        controllers[id]?.apply(config: updated)
        if publish { publishSummaries() }
        if publish { markDirty() } else { scheduleSave() }
    }

    func setHidden(_ id: UUID, _ hidden: Bool) {
        update(id) { $0.isHidden = hidden }
        refreshRunningState()
    }

    func setOpacity(_ id: UUID, _ value: Double) { update(id) { $0.opacity = value } }

    func setRate(_ id: UUID, _ value: Double) { update(id) { $0.rate = value } }

    func rotate(_ id: UUID, by degrees: Double) { update(id) { $0.rotation += degrees } }

    func setRotation(_ id: UUID, _ degrees: Double) { update(id) { $0.rotation = degrees } }

    func setLayerMode(_ id: UUID, _ mode: LayerMode) {
        update(id) { $0.layerMode = mode }
        refreshRunningState()
    }

    func setMotion(_ id: UUID, _ mode: MotionMode) {
        update(id) { $0.motion = mode }
        motionEngine.reset(id)
        ensureMotionLoop()
    }

    /// 右键菜单打开期间冻结运动：菜单锚在屏幕上，窗口一动就会"追着人跑"。
    func setMenuInteraction(_ active: Bool) {
        menuInteractionCount = max(0, menuInteractionCount + (active ? 1 : -1))
        ensureMotionLoop()
    }

    /// 菜单栏面板里复用桌面右键菜单。
    func menu(for id: UUID) -> NSMenu? {
        controllers[id]?.buildMenu()
    }

    func toggleMirror(_ id: UUID) { update(id) { $0.mirrored.toggle() } }

    func toggleClickThrough(_ id: UUID) {
        update(id) { $0.clickThrough.toggle() }
        refreshRunningState()
    }

    func toggleLock(_ id: UUID) {
        update(id) { $0.locked.toggle() }
        refreshRunningState()
    }

    func toggleMute(_ id: UUID) {
        update(id) { $0.muted.toggle() }
        refreshRunningState()
    }

    func resize(to id: UUID, width: CGFloat, aspect: CGFloat) {
        update(id) { cfg in
            let height = width / max(aspect, 0.01)
            let center = cfg.frame.center
            cfg.frame = FrameBox(x: center.x - width / 2, y: center.y - height / 2,
                                 width: width, height: height)
        }
    }

    /// 拿到真实宽高比后修正窗口（保持宽度不变，调整高度）。
    func normalizeAspect(for id: UUID, aspect: CGFloat) {
        update(id, publish: false) { cfg in
            let height = cfg.frame.width / max(aspect, 0.01)
            let center = cfg.frame.center
            cfg.frame = FrameBox(x: center.x - cfg.frame.width / 2, y: center.y - height / 2,
                                 width: cfg.frame.width, height: height)
        }
    }

    // MARK: - 全局控制

    func hideAllTemporary() {
        updateAllGlobally { $0.isHidden = true }
    }

    func showAll() {
        updateAllGlobally { $0.isHidden = false }
    }

    private func updateAllGlobally(_ mutate: (inout StickerConfig) -> Void) {
        guard !configs.isEmpty else { return }
        unfreezeArchive()
        for i in configs.indices { mutate(&configs[i]) }
        for config in configs { controllers[config.id]?.apply(config: config) }
        publishSummaries()
        refreshRunningState()
        markDirty()
    }

    func toggleGlobalPause() {
        globallyPaused.toggle()
        refreshRunningState()
    }

    // MARK: - 播放状态

    func refreshRunningState() {
        let sleeping = environment.sleeping
        let batteryPause = preferences.pauseOnBattery && environment.isOnBattery
        let suspendAll = sleeping || batteryPause || globallyPaused
        fullscreenPauseActive = preferences.hideOnFullscreen && environment.frontmostAppIsFullscreen

        FrameTicker.shared.setSuspended(suspendAll)

        for config in configs {
            guard let controller = controllers[config.id] else { continue }
            if config.isHidden || fullscreenPauseActive {
                controller.hideWindow()
            } else if suspendAll || controller.pausedByUser {
                controller.stop()
            } else if preferences.pauseWhenOccluded && controller.isOccluded {
                controller.stop()
            } else {
                controller.start(config: config)
            }
        }
        ensureMotionLoop()
    }

    private func ensureMotionLoop() {
        let needed = !globallyPaused
            && menuInteractionCount == 0
            && !environment.sleeping
            && preferences.motionSpeed > 0
            && configs.contains { !$0.isHidden && $0.motion != .still }
        if needed {
            FrameTicker.shared.add(id: motionTickerID, fps: 30) { [weak self] dt in self?.motionTick(dt) }
        } else {
            FrameTicker.shared.remove(motionTickerID)
        }
    }

    private func motionTick(_ dt: CFTimeInterval) {
        guard menuInteractionCount == 0 else { return }
        let mouse = NSEvent.mouseLocation
        let speed = preferences.motionSpeed
        for config in configs where !config.isHidden && config.motion != .still {
            guard let screen = screen(containing: config) else { continue }
            let center = motionEngine.update(id: config.id,
                                             motion: config.motion,
                                             frame: config.frame.cgRect,
                                             dt: dt,
                                             speed: speed,
                                             screen: screen.frame,
                                             mouse: mouse)
            guard let i = index(of: config.id) else { continue }
            // 走轻量路径：只动窗口，不重设 alpha / 图层 / 菜单
            configs[i].frame = configs[i].frame.settingCenter(center)
            controllers[config.id]?.applyMotion(config: configs[i])
        }
        ensureMotionLoop()
    }

    private func screen(containing config: StickerConfig) -> NSScreen? {
        let center = config.frame.center
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - UI 快照

    private func publishSummaries() {
        summaries = configs.map { cfg in
            StickerSummary(id: cfg.id,
                           name: cfg.name,
                           isHidden: cfg.isHidden,
                           locked: cfg.locked,
                           clickThrough: cfg.clickThrough,
                           mirrored: cfg.mirrored,
                           muted: cfg.muted,
                           layerMode: cfg.layerMode,
                           motion: cfg.motion,
                           rate: cfg.rate,
                           opacity: cfg.opacity)
        }
    }

    // MARK: - 持久化

    private struct Snapshot: Codable {
        var stickers: [StickerConfig]
        var preferences: Preferences
    }

    private var stateFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MemeDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("desk.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateFile),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }

        // 「下次启动恢复上次桌面」关掉时，这次启动就该是空桌面。
        // 注意**不要**顺手把空状态落盘：`preferences` 的赋值会立刻触发 `prefSink`，
        // 5 秒一次的周期保存也会跟上来，两者都会把空的 configs 写回 desk.json ——
        // 于是用户把开关拨回去时布局已经没了。冻结到用户真的动了桌面为止。
        let startsEmpty = !snapshot.preferences.restoreSession
        archiveIsFrozen = startsEmpty

        configs = startsEmpty ? [] : snapshot.stickers
        preferences = snapshot.preferences
    }

    /// 用户动了桌面 —— 从此当前状态就是新的存档，允许落盘。
    private func unfreezeArchive() {
        archiveIsFrozen = false
    }

    func saveNow() {
        guard !archiveIsFrozen else { return }
        let snapshot = Snapshot(stickers: configs, preferences: preferences)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: stateFile, options: .atomic)
    }

    /// 结构性变化：稍等一下再写，避免爆炸式 IO。
    private func markDirty() { scheduleSave() }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    var count: Int { configs.count }
}
