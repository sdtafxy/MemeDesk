import AppKit
import AVFoundation
import CoreGraphics
import Foundation

/// 一个窗口 = 一个表情包实例的控制器。
///
/// 它负责：① 建无边框透明窗口 ② 加载媒体 ③ 把 config 的每一项翻译成 AppKit 调用
/// ④ 提供右键菜单 ⑤ 把用户的拖拽/缩放回写成 config。
@MainActor
final class StickerWindowController: NSWindowController {

    let stickerID: UUID
    private unowned let stage: Stage
    /// 保留类型信息：`NSWindowController.window` 只是 `NSWindow?`，拿不到 StickerWindow 的扩展。
    private let stickerWindow: StickerWindow

    private let contentView: StickerView
    private var kind: MediaKind = .stillImage
    private var naturalSize: CGSize = CGSize(width: 1, height: 1)
    private var aspect: CGFloat = 1
    private var mediaURL: URL?
    private var loadTask: Task<Void, Never>?
    /// 双击造成的临时暂停，不落盘。
    private var isPaused = false
    private var occlusionObserver: NSObjectProtocol?

    init(id: UUID, config: StickerConfig, stage: Stage) {
        self.stickerID = id
        self.stage = stage
        let window = StickerWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200),
                                   mode: config.layerMode)
        let contentView = StickerView(id: id,
                                      frame: NSRect(origin: .zero,
                                                    size: window.contentView?.bounds.size ?? .zero))
        self.contentView = contentView
        self.stickerWindow = window
        super.init(window: window)

        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        contentView.onMove = { [weak self] center in self?.handleMove(center) }
        contentView.onResize = { [weak self] size in self?.handleResize(size) }
        contentView.onSelect = { [weak self] in
            guard let self else { return }
            self.stage.select(self.stickerID)
        }
        contentView.onTogglePlay = { [weak self] in self?.togglePlay() }
        contentView.onMenuInteraction = { [weak self] active in
            guard let self else { return }
            active ? self.beginMenuPresentation() : self.endMenuPresentation()
        }
        installMenu()

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.stage.refreshRunningState() }
        }

        apply(config: config)
        loadMedia(config: config)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StickerWindowController is code-only")
    }

    deinit {
        occlusionObserver.map(NotificationCenter.default.removeObserver)
    }

    var isOccluded: Bool {
        guard let window, window.isVisible else { return true }
        return window.occlusionState.contains(.visible) == false
    }

    // MARK: - 媒体加载

    private func loadMedia(config: StickerConfig) {
        guard let bookmark = config.bookmark, let url = Bookmark.url(from: bookmark) else {
            showPlaceholder(L(.fileMissing))
            return
        }
        mediaURL = url
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.decode(url: url)
        }
    }

    private func decode(url: URL) async {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let kind = MediaProbe.kind(of: url)
        let size = await MediaProbe.intrinsicSize(of: url, kind: kind)
        guard !Task.isCancelled else { return }

        self.kind = kind
        self.naturalSize = size
        self.aspect = size.height > 0 ? size.width / size.height : 1

        switch kind {
        case .animatedImage:
            let limit = stage.preferences.decodePixelLimit
            let scale = window?.backingScaleFactor ?? 2
            // 这个贴纸当前实际占多少像素。把 decodePixelLimit 当**上限**，
            // 实际按显示尺寸来 —— 否则一个 200pt 的小贴纸也要解 640px 的图，
            // 解码、色彩转换、纹理上传、内存四样一起浪费。
            let frameSize = window?.frame.size ?? .zero
            let displayPixel = Int(max(frameSize.width, frameSize.height) * scale)
            do {
                let source = try AnimatedImageSource(url: url,
                                                     targetPixel: Int(Double(limit) * scale),
                                                     displayPixel: displayPixel)
                contentView.configure(animated: source, aspect: aspect)
            } catch {
                if let fallback = firstFrame(of: url, pixel: limit) {
                    contentView.configure(still: fallback, aspect: aspect)
                } else {
                    showPlaceholder(L(.decodeFailed))
                }
            }
        case .stillImage:
            guard let image = firstFrame(of: url, pixel: stage.preferences.decodePixelLimit) else {
                showPlaceholder(L(.decodeFailed))
                return
            }
            contentView.configure(still: image, aspect: aspect)
        case .video:
            await decodeVideo(url: url)
        }

        // 首次加载后按真实宽高比重算窗口尺寸
        stage.normalizeAspect(for: stickerID, aspect: aspect)
        stage.refreshRunningState()
    }

    /// 视频走单独路径：解不出来时给出**带原因**的提示，而不是笼统的"解码失败"。
    private func decodeVideo(url: URL) async {
        var video = await VideoSource(url: url, stripAudio: true)
        if !video.isPlayable {
            // 个别封装剥音轨后会失败，退回原始素材再试一次
            video = await VideoSource(url: url, stripAudio: false)
        }
        guard !Task.isCancelled else { return }

        let realAspect = video.naturalSize.height > 0
            ? video.naturalSize.width / video.naturalSize.height : aspect
        self.aspect = realAspect

        guard video.isPlayable else {
            video.pause()
            if let still = firstFrame(of: url, pixel: stage.preferences.decodePixelLimit) {
                contentView.configure(still: still, aspect: realAspect)
            } else {
                showPlaceholder(L(.videoUnplayable))
            }
            return
        }

        contentView.configure(video: video, aspect: realAspect)

        // 播放器真正起播后才见分晓：失败时把系统给的原因一并显示出来，方便定位
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            guard let current = self.contentView.currentVideo, current.hasFailed else { return }
            self.showPlaceholder(L(.videoUnplayable), detail: current.failureReason)
        }
    }

    /// 静态首帧 —— 同时也当作缩略图用。
    private func firstFrame(of url: URL, pixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func showPlaceholder(_ text: String, detail: String? = nil) {
        let width: CGFloat = 280
        let height: CGFloat = detail == nil ? 160 : 190
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemGray.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                     xRadius: 16, yRadius: 16).fill()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 11),
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let title = NSAttributedString(string: text, attributes: titleAttrs.merging(
            [.paragraphStyle: paragraph], uniquingKeysWith: { $1 }))
        let titleRect = CGRect(x: 12, y: height / 2 + (detail == nil ? 4 : 14),
                               width: width - 24, height: 30)
        title.draw(with: titleRect, options: [.usesLineFragmentOrigin])

        if let detail, !detail.isEmpty {
            let body = NSAttributedString(string: detail, attributes: detailAttrs.merging(
                [.paragraphStyle: paragraph], uniquingKeysWith: { $1 }))
            body.draw(with: CGRect(x: 16, y: height / 2 - 30, width: width - 32, height: 40),
                      options: [.usesLineFragmentOrigin])
        }
        image.unlockFocus()
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            contentView.configure(still: cg, aspect: width / height)
        }
    }

    // MARK: - 应用 config

    func apply(config: StickerConfig) {
        guard let window else { return }
        window.alphaValue = max(0.05, min(config.opacity, 1))
        stickerWindow.applyLayerMode(config.layerMode)

        let interactive = !config.clickThrough && !config.locked && config.layerMode.supportsInteraction && !config.isHidden
        window.ignoresMouseEvents = !interactive

        let radians = config.rotation * .pi / 180
        contentView.setContentSize(config.frame.cgRect.size, rotation: radians, mirrored: config.mirrored)
        contentView.setRate(config.rate)

        // 视频音量：静音或按配置
        if let video = contentView.currentVideo {
            video.setMuted(config.muted)
            if !config.muted { video.player.volume = config.volume }
        }

        layoutWindow(config: config)
        setHiddenStyle(config.isHidden)
    }

    /// 窗口的实际尺寸 = 旋转外接矩形，保证旋转 / 镜像都不被窗口边缘裁掉。
    func layoutWindow(config: StickerConfig) {
        guard let window else { return }
        let box = config.frame
        let angle = abs(cos(config.rotation * .pi / 180))
        let sine = abs(sin(config.rotation * .pi / 180))
        let w = box.width * angle + box.height * sine
        let h = box.width * sine + box.height * angle
        let frame = CGRect(x: box.center.x - w / 2, y: box.center.y - h / 2, width: w, height: h)
        window.setFrame(frame, display: false)
    }

    private func setHiddenStyle(_ hidden: Bool) {
        guard let window else { return }
        if hidden {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    // MARK: - 播放控制

    func setSelected(_ value: Bool) { contentView.setSelected(value) }

    func start(config: StickerConfig) {
        guard !config.isHidden else { return }
        window?.orderFrontRegardless()
        contentView.setRunning(true)
        contentView.setRate(config.rate)
        if let video = contentView.currentVideo {
            video.setMuted(config.muted)
            if !config.muted { video.player.volume = config.volume }
        }
    }

    func stop() { contentView.setRunning(false) }

    func hideWindow() {
        stop()
        window?.orderOut(nil)
    }

    /// 运动引擎专用：每一次 tick 都调用，因此必须避开一切非几何操作。
    func applyMotion(config: StickerConfig) {
        layoutWindow(config: config)
    }

    // MARK: - 交互回写

    private func handleMove(_ center: CGPoint) {
        // 位置变化不参与 UI 快照对比，走静默路径避免每帧刷新 SwiftUI
        stage.update(stickerID, publish: false) { cfg in
            var box = cfg.frame.settingCenter(center)
            // 防止一路拖到屏幕外再也找不回来
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
                ?? NSScreen.main {
                let margin: CGFloat = 40
                box.x = min(max(box.x, screen.frame.minX - box.width + margin), screen.frame.maxX - margin)
                box.y = min(max(box.y, screen.frame.minY - box.height + margin), screen.frame.maxY - margin)
                if stage.preferences.snapToEdges {
                    let threshold: CGFloat = 12
                    if abs(box.x - screen.frame.minX) < threshold { box.x = screen.frame.minX }
                    if abs(box.y - screen.frame.minY) < threshold { box.y = screen.frame.minY }
                    if abs((box.x + box.width) - screen.frame.maxX) < threshold { box.x = screen.frame.maxX - box.width }
                    if abs((box.y + box.height) - screen.frame.maxY) < threshold { box.y = screen.frame.maxY - box.height }
                }
            }
            cfg.frame = box
        }
        guard let latest = stage.config(for: stickerID) else { return }
        layoutWindow(config: latest)
    }

    private func handleResize(_ size: CGSize) {
        stage.update(stickerID, publish: false) { cfg in
            let center = cfg.frame.center
            cfg.frame = FrameBox(x: center.x - size.width / 2,
                                 y: center.y - size.height / 2,
                                 width: size.width,
                                 height: size.height)
        }
        guard let latest = stage.config(for: stickerID) else { return }
        layoutWindow(config: latest)
    }

    private func togglePlay() {
        isPaused.toggle()
        stage.refreshRunningState()
    }

    var pausedByUser: Bool { isPaused }

    func teardown() {
        loadTask?.cancel()
        contentView.teardown()
        close()
    }

    // MARK: - 右键菜单的前后处理
    //
    // 1) 冻结运动：菜单锚在屏幕上，窗口一动菜单就"追着人跑"；
    // 2) 把窗口压到弹出菜单之下，免得"悬浮于一切之上"的素材盖住自己的菜单；
    // 3) 菜单收起后取消选中 —— 高亮只在"用户正对着这个素材"时才有意义。

    private func beginMenuPresentation() {
        stage.setMenuInteraction(true)
        stickerWindow.setMenuPresentation(true)
    }

    private func endMenuPresentation() {
        stickerWindow.setMenuPresentation(false)
        stage.setMenuInteraction(false)
        // 不要只指望 NSApplication.didResignActiveNotification：走完菜单之后，
        // 应用的激活状态往往根本没变过，那个通知不触发，蓝框就留在桌面上了。
        stage.select(nil)
    }

    // MARK: - 右键菜单

    func buildMenu() -> NSMenu {
        let id = stickerID
        guard let config = stage.config(for: id) else { return NSMenu() }
        let menu = NSMenu(title: config.name)

        menu.addItem(ClosureMenuItem(title: config.name, enabled: false))
        menu.addItem(.separator())

        // 缩放
        let zoomMenu = NSMenu(title: L(.menuSize))
        for percent in [25, 50, 75, 100, 150, 200, 300, 400] {
            zoomMenu.addItem(ClosureMenuItem(title: "\(percent)%", handler: { [weak self] in
                self?.setZoom(percent: percent)
            }))
        }
        zoomMenu.addItem(.separator())
        zoomMenu.addItem(ClosureMenuItem(title: L(.restoreOriginalSize), handler: { [weak self] in
            self?.setZoom(percent: nil)
        }))
        let zoomItem = NSMenuItem(title: L(.menuSize), action: nil, keyEquivalent: "")
        zoomItem.submenu = zoomMenu
        menu.addItem(zoomItem)

        // 不透明度
        let opacityMenu = NSMenu(title: L(.opacity))
        for value in [100, 80, 60, 40, 20] {
            opacityMenu.addItem(ClosureMenuItem(title: "\(value)%",
                                                state: Int(config.opacity * 100) == value,
                                                handler: { [weak self] in self?.stage.setOpacity(id, Double(value) / 100) }))
        }
        wrap(opacityMenu, as: L(.opacity), into: menu)

        // 播放速度
        let rateMenu = NSMenu(title: L(.speed))
        for value in [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0] {
            rateMenu.addItem(ClosureMenuItem(title: "\(value)×",
                                             state: abs(config.rate - value) < 0.01,
                                             handler: { [weak self] in self?.stage.setRate(id, value) }))
        }
        wrap(rateMenu, as: L(.speed), into: menu)

        // 旋转
        let rotateMenu = NSMenu(title: L(.menuRotation))
        rotateMenu.addItem(ClosureMenuItem(title: L(.rotateLeft), handler: { [weak self] in self?.stage.rotate(id, by: -15) }))
        rotateMenu.addItem(ClosureMenuItem(title: L(.rotateRight), handler: { [weak self] in self?.stage.rotate(id, by: 15) }))
        rotateMenu.addItem(ClosureMenuItem(title: L(.rotationReset), handler: { [weak self] in self?.stage.setRotation(id, 0) }))
        wrap(rotateMenu, as: L(.menuRotation), into: menu)

        // 图层
        let layerMenu = NSMenu(title: L(.layerPosition))
        for mode in LayerMode.allCases {
            layerMenu.addItem(ClosureMenuItem(title: mode.label,
                                              state: config.layerMode == mode,
                                              handler: { [weak self] in self?.stage.setLayerMode(id, mode) }))
        }
        wrap(layerMenu, as: L(.layerPosition), into: menu)

        // 行为
        let motionMenu = NSMenu(title: L(.motion))
        for mode in MotionMode.allCases {
            motionMenu.addItem(ClosureMenuItem(title: mode.label,
                                               state: config.motion == mode,
                                               handler: { [weak self] in self?.stage.setMotion(id, mode) }))
        }
        wrap(motionMenu, as: L(.motion), into: menu)

        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(title: L(.mirror),
                                     state: config.mirrored,
                                     handler: { [weak self] in self?.stage.toggleMirror(id) }))
        menu.addItem(ClosureMenuItem(title: L(.clickThrough),
                                     state: config.clickThrough || !config.layerMode.supportsInteraction,
                                     handler: { [weak self] in self?.stage.toggleClickThrough(id) }))
        menu.addItem(ClosureMenuItem(title: L(.lockDetailed),
                                     state: config.locked,
                                     handler: { [weak self] in self?.stage.toggleLock(id) }))
        if kind == .video {
            menu.addItem(ClosureMenuItem(title: L(.mute),
                                         state: config.muted,
                                         handler: { [weak self] in self?.stage.toggleMute(id) }))
        }
        menu.addItem(ClosureMenuItem(title: isPaused ? L(.resume) : L(.pause),
                                     handler: { [weak self] in self?.togglePlay() }))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L(.revealInFinder),
                                     handler: { [weak self] in
                                         guard let url = self?.mediaURL else { return }
                                         NSWorkspace.shared.activateFileViewerSelecting([url])
                                     }))
        menu.addItem(ClosureMenuItem(title: L(.duplicate), key: "d",
                                     handler: { [weak self] in self?.stage.duplicate(id) }))
        menu.addItem(ClosureMenuItem(title: L(.hide), key: "w",
                                     handler: { [weak self] in self?.stage.setHidden(id, true) }))
        menu.addItem(ClosureMenuItem(title: L(.removeFromDesk), key: "\u{8}",
                                     handler: { [weak self] in self?.stage.remove(id) }))
        return menu
    }

    private func wrap(_ submenu: NSMenu, as title: String, into menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func setZoom(percent: Int?) {
        guard let config = stage.config(for: stickerID) else { return }
        // 原始宽度拿不到时（解码失败 / 视频元数据缺失），退回当前窗口宽度，
        // 绝不能拿 1pt 去乘 —— 否则窗口会被缩到看不见。
        let nativeWidth = naturalSize.width > 8 ? naturalSize.width : max(config.frame.width, 48)
        let target = nativeWidth * CGFloat(percent ?? 100) / 100
        let clamped = max(24, min(target, 4000))
        let safeAspect = aspect > 0.05 ? aspect : max(config.frame.width / max(config.frame.height, 1), 0.05)
        stage.resize(to: stickerID, width: clamped, aspect: safeAspect)
    }

    /// 菜单每次右键重建。
    private func installMenu() {
        contentView.menuProvider = { [weak self] in self?.buildMenu() }
    }
}

/// 闭包版菜单项：省掉一整排 target/action switch。
private final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    convenience init(title: String, state: Bool = false, key: String = "",
                     enabled: Bool = true, handler: (() -> Void)? = nil) {
        self.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        self.handler = handler
        self.state = state ? .on : .off
        self.isEnabled = enabled
    }

    @objc private func fire() { handler?() }
}
