import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore

/// 单个表情包的渲染视图。
///
/// 走 **layer-hosting** 路线（手工给 NSView 赋 root layer），而不是 layer-backed：
/// 图像与视频像素直接交给窗口合成器，NSView 的 draw(_:) 光栅化路径完全不参与，
/// 画面静止时主线程开销是零。
@MainActor
final class StickerView: NSView {

    // 交互回调
    var onMove: ((CGPoint) -> Void)?
    var onResize: ((CGSize) -> Void)?
    var onSelect: (() -> Void)?
    var onTogglePlay: (() -> Void)?
    /// 拖拽开始 / 结束。开始那一下必须让运动引擎停手，否则引擎会和鼠标抢窗口位置。
    var onDragState: ((Bool) -> Void)?

    private let imageLayer = CALayer()
    private let playerLayer = AVPlayerLayer()

    private var source: AnimatedImageSource?
    private var video: VideoSource?
    private var elapsed: TimeInterval = 0
    private var currentFrameIndex: Int = -1
    private var rate: Double = 1
    private var running = false
    private let stickerID: UUID

    /// 未旋转时的内容视觉尺寸（旋转后窗口会被撑大到外接矩形，这个尺寸不变）。
    private var contentSize: CGSize = .zero
    private var aspect: CGFloat = 1

    private var dragStartMouse: NSPoint = .zero
    private var dragStartVisualFrame: CGRect = .zero
    private var isResizing = false
    /// 这一轮按下真的进过拖拽（用来配对 `onDragState`，见 `endDragIfNeeded`）。
    private var isDragging = false
    /// 双击已经处理过了 —— 这一轮不要再当成拖拽（见 `mouseDown`）。
    private var suppressDrag = false

    init(id: UUID, frame frameRect: NSRect) {
        self.stickerID = id
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer() // layer-hosting：后续所有绘制都在 Icon layer 子树里
        layer?.masksToBounds = false

        imageLayer.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.addSublayer(imageLayer)

        playerLayer.videoGravity = .resizeAspect
        playerLayer.actions = ["position": NSNull(), "bounds": NSNull()]
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)

        autoresizesSubviews = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StickerView is code-only")
    }

    // MARK: - 配置

    func configure(animated source: AnimatedImageSource, aspect: CGFloat) {
        teardownVideo()
        self.source = source
        self.aspect = aspect
        imageLayer.isHidden = false
        playerLayer.isHidden = true
        if running { startTicker() }
        renderFrame(force: true)
    }

    func configure(still image: CGImage, aspect: CGFloat) {
        teardownVideo()
        source = nil
        self.aspect = aspect
        imageLayer.isHidden = false
        playerLayer.isHidden = true
        stopTicker()
        setImage(image)
    }

    func configure(video: VideoSource, aspect: CGFloat) {
        source = nil
        stopTicker()
        self.video = video
        self.aspect = aspect
        imageLayer.isHidden = true
        playerLayer.isHidden = false
        playerLayer.player = video.player
        video.setMuted(true) // 真实音量由 Stage 稍后统一纠正
        video.setRate(running ? Float(rate) : 0)
    }

    /// 窗口本身的实际内容区（可能小于 bounds，因为旋转会撑大窗口）。
    var contentFrame: CGRect {
        CGRect(x: bounds.midX - contentSize.width / 2,
               y: bounds.midY - contentSize.height / 2,
               width: contentSize.width,
               height: contentSize.height)
    }

    // MARK: - 播放控制

    func setRunning(_ value: Bool) {
        running = value
        if let video {
            value ? video.play() : video.pause()
            if value { video.setRate(Float(rate)) }
            return
        }
        value ? startTicker() : stopTicker()
    }

    func setRate(_ value: Double) {
        rate = max(0.1, min(value, 4))
        video?.setRate(running ? Float(rate) : 0)
    }

    var isRunning: Bool { running }

    private func startTicker() {
        guard let source else { return }
        // 用素材自身的帧率参与全局频率协商：10fps 的 GIF 不会逼着 Timer 跑 60Hz
        let natural = source.totalDuration > 0 ? Double(source.frameCount) / source.totalDuration : 24
        let fps = min(max(natural, 12), 45)
        FrameTicker.shared.add(id: stickerID, fps: fps) { [weak self] dt in
            self?.handleTick(dt)
        }
    }

    private func stopTicker() {
        FrameTicker.shared.remove(stickerID)
    }

    private func handleTick(_ dt: CFTimeInterval) {
        guard let source, dt >= 0 else { return }
        elapsed += dt * rate
        if elapsed > source.totalDuration {
            elapsed.formTruncatingRemainder(dividingBy: source.totalDuration)
        }
        renderFrame(force: false)
    }

    private func renderFrame(force: Bool) {
        guard let source else { return }
        let idx = source.frameIndex(at: elapsed)
        guard idx != currentFrameIndex || force else { return }
        guard let image = source.image(at: idx) else {
            // 未命中：继续显示上一帧，同时把后面几帧预取上来
            source.preload(around: idx)
            return
        }
        currentFrameIndex = idx
        setImage(image)
        source.preload(around: idx)
    }

    private func setImage(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
    }

    // MARK: - 几何 / 变换

    func setContentSize(_ size: CGSize, rotation radians: CGFloat, mirrored: Bool) {
        contentSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var transform = CATransform3DIdentity
        if abs(radians) > 0.0001 {
            transform = CATransform3DRotate(transform, radians, 0, 0, 1)
        }
        if mirrored {
            transform = CATransform3DScale(transform, -1, 1, 1)
        }
        imageLayer.transform = transform
        playerLayer.transform = transform
        layoutContent()
        CATransaction.commit()
    }

    var currentAspect: CGFloat { aspect }

    func setSelected(_ value: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if value {
            imageLayer.borderWidth = 2
            imageLayer.borderColor = NSColor.controlAccentColor.cgColor
            playerLayer.borderWidth = 2
            playerLayer.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            imageLayer.borderWidth = 0
            playerLayer.borderWidth = 0
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contentsScale = scale
        CATransaction.commit()
        layer?.contentsScale = scale
    }

    private func layoutContent() {
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        root.contentsScale = scale
        imageLayer.contentsScale = scale
        // 用 bounds + position 而不是 frame：layer 带着 transform 时 frame 语义是不可靠的。
        imageLayer.bounds = CGRect(origin: .zero, size: contentSize)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        playerLayer.bounds = CGRect(origin: .zero, size: contentSize)
        playerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    // MARK: - 鼠标交互

    /// 每次右键都重新构建菜单，选中态永远是最新的。
    var menuProvider: (() -> NSMenu?)?
    /// 菜单打开/关闭回调：冻结运动引擎，免得菜单跟着窗口跑。
    var onMenuInteraction: ((Bool) -> Void)?

    /// 当前持有的视频源（供控制器调整音量）。
    var currentVideo: VideoSource? { video }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // 没有窗口就等于没有正确的坐标系，直接放弃本次拖拽
        guard window != nil else { return }
        onSelect?()
        // 双击 = 暂停 / 继续这个素材。这也是 `onTogglePlay` 唯一的调用点 ——
        // 之前它一直"接了线没人调"，所以文档里写的双击暂停其实并不存在。
        if event.clickCount == 2 {
            onTogglePlay?()
            // 双击的第二下不能顺带开启一次拖拽，否则鼠标只要抖一点窗口就跟着跑。
            suppressDrag = true
            return
        }
        suppressDrag = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartVisualFrame = contentFrameInScreen
        isResizing = event.modifierFlags.contains(.option)
        // ⚠️ 手一按下去就得让运动引擎停手，见 `MotionEngine.hold(_:)`。
        // 只在"这一下真的可能是拖拽"时通知（双击已经在上面 return 了）。
        isDragging = true
        onDragState?(true)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard !suppressDrag else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        if isResizing {
            let newWidth = max(48, dragStartVisualFrame.width + dx)
            let newHeight = newWidth / max(aspect, 0.01)
            onResize?(CGSize(width: newWidth, height: newHeight))
        } else {
            let center = CGPoint(x: dragStartVisualFrame.midX + dx, y: dragStartVisualFrame.midY + dy)
            onMove?(center)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isResizing = false
        suppressDrag = false
        endDragIfNeeded()
    }

    /// 收尾拖拽。**只在真的开始过拖拽时**才回调 —— 双击那一路会 `suppressDrag`
    /// 直接 return，从来没 signal 过 `true`；无脑配一个 `false` 会把
    /// 弹跳贴纸的速度清零（双击是"暂停"，不该顺手改变它的运动状态）。
    private func endDragIfNeeded() {
        guard isDragging else { return }
        isDragging = false
        onDragState?(false)
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0 else { return }
        let unit: CGFloat = event.hasPreciseScrollingDeltas ? 0.6 : 6
        let step = 1 + (event.scrollingDeltaY * unit) / 300
        let newWidth = max(48, min(contentSize.width * step, 4000))
        onResize?(CGSize(width: newWidth, height: newWidth / max(aspect, 0.01)))
    }

    override func rightMouseDown(with event: NSEvent) {
        onSelect?()
        guard let menu = menuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        onMenuInteraction?(true)
        defer { onMenuInteraction?(false) }
        // 用屏幕坐标弹出，而不是锚在视图上：锚视图的菜单会跟着窗口一起跑
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// 内容 frames 在屏幕坐标系（AppKit 左下原点）里的位置。
    private var contentFrameInScreen: CGRect {
        guard let window else { return .zero }
        let local = contentFrame
        return CGRect(x: window.frame.origin.x + local.origin.x,
                      y: window.frame.origin.y + local.origin.y,
                      width: local.width,
                      height: local.height)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    // MARK: - 清理

    private func teardownVideo() {
        if let video {
            video.pause()
            playerLayer.player = nil
            self.video = nil
        }
    }

    func teardown() {
        stopTicker()
        teardownVideo()
        source = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        CATransaction.commit()
    }
}
