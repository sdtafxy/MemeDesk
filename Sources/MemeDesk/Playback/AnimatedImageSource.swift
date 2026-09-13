import CoreGraphics
import Foundation
import ImageIO

/// 动图（GIF / APNG / 动画 WebP）解码器。
///
/// 三件让它保持轻盈的事：
/// 1. **按显示尺寸解码**：目标尺寸取「这个贴纸实际需要多少像素」和
///    `decodePixelLimit × 屏幕缩放` 里的小者。用 ImageIO 的 thumbnail 接口按目标尺寸解出
///    CGImage，一个 800×800 的表情包放在 200pt 的窗口里只会解出 ~400px 的位图。
/// 2. **按需 + 预取**：解码在 utility 队列，主线程绝不参与；未命中时返回 nil，
///    调用方继续显示上一帧，画面不撕裂也不卡顿。
/// 3. **有界的 LRU 缓存**：按字节数（而非帧数）限流，长图不会把内存吃穿。
///
/// 线程模型：imageSource 只在内部那条**串行** decodeQueue 上被读取，
/// 主线程从不碰它，因此不存在并发解码同一 CGImageSource 的情况。
final class AnimatedImageSource: @unchecked Sendable {
    enum Failure: Error {
        case cannotOpen(URL)
        case notAnimated
    }

    let url: URL
    let frameCount: Int
    /// 原始像素尺寸。
    let pixelSize: CGSize
    private(set) var totalDuration: TimeInterval = 0

    private let imageSource: CGImageSource
    /// 每帧延时（已按浏览器惯例 clamp）。
    private var delays: [TimeInterval] = []
    /// 每帧起始时刻，cumulative[count] 为总时长。
    private var cumulative: [TimeInterval] = []
    /// 目标解码像素（单边最大值）。
    private let targetPixel: Int
    private let needsDownsample: Bool

    private let lock = NSLock()
    private var cache: [Int: CGImage] = [:]
    private var cacheOrder: [Int] = []
    private var cacheBytes: Int = 0
    private var pendingDecode: Set<Int> = []
    /// 单个动图的解码缓存上限。
    ///
    /// 会按需上调到刚好**装下一整轮动画**（见 `budget(frameCount:pixel:)`）—— 那不只是一点
    /// 内存优化：装得下就意味着每一帧一辈子只解一次，而不是每循环一圈重解一遍。
    private let cacheByteLimit: Int
    /// 从全局预算里预扣的字节数，`deinit` 时归还。
    private let reservedBytes: Int

    /// 所有动图共用的缓存总量上限。没有它的话，20 个大动图各占 64MB 就是 1.2GB。
    ///
    /// 用一个小对象持有，而不是 `static var`：可变的全局状态在严格并发检查下会被投诉，
    /// 而 CI 的编译器比本机严。
    private final class SharedBudget: @unchecked Sendable {
        static let shared = SharedBudget()
        private let lock = NSLock()
        private var used = 0
        private let limit = 192 * 1024 * 1024

        func reserve(_ bytes: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard used + bytes <= limit else { return false }
            used += bytes
            return true
        }

        func release(_ bytes: Int) {
            guard bytes > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            used = max(0, used - bytes)
        }
    }

    private let decodeQueue = DispatchQueue(label: "com.memedesk.gif.decode", qos: .utility)

    /// - Parameters:
    ///   - targetPixel: 解码像素的**上限**（`decodePixelLimit × 屏幕缩放`）。
    ///   - displayPixel: 这个贴纸当前实际占多少像素；0 表示未知，那就只用上限。
    ///     传它是为了别给一个 200pt 的小贴纸解 640px 的图 —— 解码、色彩转换、
    ///     纹理上传、内存四样全都在浪费。
    init(url: URL, targetPixel: Int, displayPixel: Int = 0) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Failure.cannotOpen(url)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw Failure.notAnimated }

        self.url = url
        self.imageSource = source
        self.frameCount = count

        let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let containerW = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let containerH = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        // 容器属性经常缺尺寸（不少 GIF 只写在第 0 帧里），所以再从单帧属性兜底
        let fallback = MediaProbe.imagePixelSize(of: url) ?? .zero
        let w = containerW > 0 ? containerW : fallback.width
        let h = containerH > 0 ? containerH : fallback.height
        self.pixelSize = CGSize(width: w, height: h)

        // 目标像素不允许超过原始像素：放大毫无意义，纯属浪费。
        let nativeMax = Int(max(w, h))
        var want = targetPixel
        if displayPixel > 0 { want = min(want, displayPixel) }
        if nativeMax > 0 { want = min(want, nativeMax) }
        let clamped = max(16, want)

        let plan = Self.plan(nativeWidth: w, nativeHeight: h,
                             limit: clamped, frameCount: count)
        self.targetPixel = plan.pixel
        self.needsDownsample = plan.downsample

        self.delays = (0..<count).map { Self.delay(of: source, at: $0) }
        var acc: TimeInterval = 0
        var table: [TimeInterval] = [0]
        for d in delays {
            acc += d
            table.append(acc)
        }
        self.cumulative = table
        self.totalDuration = max(acc, 0.001)

        let reserve = Self.budget(frameCount: count, frameBytes: plan.frameBytes)
        self.cacheByteLimit = reserve.limit
        self.reservedBytes = reserve.reserved
    }

    /// 能一次性装下整轮动画的字节上限（单个动图）。
    private static let wholeAnimationCap = 96 * 1024 * 1024

    /// 决定按多大尺寸解码、要不要走缩略图路径。
    ///
    /// 这里有个**耦合**，分开判断会做出错误决定：
    ///
    /// - 流式播放时（装不下整轮），ImageIO 的缩略图路径要先全量解码再重采样，
    ///   小幅缩水（比如 630×824 → 640）代价是原尺寸解码的**两倍**，所以只有
    ///   至少能缩掉一半才值得缩 —— 否则宁可原尺寸解出来交给 GPU 缩放。
    /// - 但如果缩完之后**整轮动画都能装进缓存**，那每帧一辈子只解一次，
    ///   单帧贵一点完全无所谓，此时哪怕只缩一点点也应该缩，好把整轮塞进去。
    private static func plan(nativeWidth w: Double, nativeHeight h: Double,
                             limit: Int, frameCount: Int)
        -> (pixel: Int, downsample: Bool, frameBytes: Int) {
        // 先按"缩到 limit"估一版，看看能不能整轮装下
        let nativeMax = max(w, h)
        let ratio = nativeMax > 0 ? Double(limit) / nativeMax : 1
        let scaledW = w > 0 ? Int(w * ratio) : limit
        let scaledH = h > 0 ? Int(h * ratio) : limit
        let scaledBytes = max(1, scaledW) * max(1, scaledH) * 4
        let fitsWhole = frameCount * scaledBytes <= wholeAnimationCap

        let downsample: Bool
        if fitsWhole {
            downsample = Int(nativeMax) > limit
        } else {
            downsample = Int(nativeMax) >= limit * 2
        }

        if downsample {
            return (limit, true, scaledBytes)
        }
        // 不缩：按原始尺寸解，单帧大小直接用原始宽高
        let nativeBytes = max(1, Int(w)) * max(1, Int(h)) * 4
        return (limit, false, nativeBytes)
    }

    /// 缓存的字节预算。
    ///
    /// 默认 32MB；但如果"装下整轮动画"只要不到 `wholeAnimationCap`，就把预算提到那个数 ——
    /// 这样每一帧只解一次，之后全是内存命中。对一个 24 小时挂在桌面上的东西来说，
    /// 拿几十 MB 换掉持续的解码开销是划算的。
    private static func budget(frameCount: Int, frameBytes: Int) -> (limit: Int, reserved: Int) {
        let base = 32 * 1024 * 1024
        let wholeAnimation = frameCount * frameBytes
        guard wholeAnimation > base, wholeAnimation <= wholeAnimationCap else {
            return (base, 0)
        }
        guard SharedBudget.shared.reserve(wholeAnimation) else { return (base, 0) }
        return (wholeAnimation, wholeAnimation)
    }


    deinit {
        cache.removeAll(keepingCapacity: false)
        SharedBudget.shared.release(reservedBytes)
    }

    // MARK: - 帧数据

    /// 取某一帧。**同步且可能返回 nil**（未命中缓存时后台补解码），
    /// 调用方应当在 nil 时保持显示上一帧。
    func image(at index: Int) -> CGImage? {
        guard frameCount > 0 else { return nil }
        let i = ((index % frameCount) + frameCount) % frameCount
        lock.lock()
        let hit = cache[i]
        if hit != nil {
            touchLocked(i)
            lock.unlock()
            return hit
        }
        let already = pendingDecode.contains(i)
        if !already { pendingDecode.insert(i) }
        lock.unlock()

        if !already { scheduleDecode(i) }
        return nil
    }

    /// 提前把接下来若干帧解出来。播放时每帧都会调用一次，窗口很小（默认 5 帧）。
    func preload(around index: Int, window: Int = 5) {
        for offset in 0..<window {
            let i = (index + offset) % frameCount
            lock.lock()
            let cached = cache[i] != nil
            let scheduled = pendingDecode.contains(i)
            if !cached && !scheduled { pendingDecode.insert(i) }
            lock.unlock()
            if !cached && !scheduled { scheduleDecode(i) }
        }
    }

    /// 给定已播放时长，返回应显示的帧下标（二分查找，长图也不掉帧）。
    func frameIndex(at time: TimeInterval) -> Int {
        guard frameCount > 1, totalDuration > 0 else { return 0 }
        let t = time.truncatingRemainder(dividingBy: totalDuration)
        var lo = 0
        var hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumulative[mid] <= t {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return min(lo, frameCount - 1)
    }

    func delay(of index: Int) -> TimeInterval {
        guard delays.indices.contains(index) else { return 0.1 }
        return delays[index]
    }

    // MARK: - 内部

    private func scheduleDecode(_ index: Int) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            guard let image = self.decodeFrameLockedFree(index) else {
                self.lock.lock()
                self.pendingDecode.remove(index)
                self.lock.unlock()
                return
            }
            let bytes = image.width * image.height * 4
            self.lock.lock()
            self.pendingDecode.remove(index)
            if self.cache[index] == nil {
                self.cache[index] = image
                self.cacheBytes += bytes
            }
            self.touchLocked(index)
            self.trimLocked()
            self.lock.unlock()
        }
    }

    private func decodeFrameLockedFree(_ index: Int) -> CGImage? {
        if needsDownsample {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: targetPixel,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary)
        }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateImageAtIndex(imageSource, index, options as CFDictionary)
    }

    private func touchLocked(_ index: Int) {
        cacheOrder.removeAll { $0 == index }
        cacheOrder.append(index)
    }

    private func trimLocked() {
        while cacheBytes > cacheByteLimit, let victim = cacheOrder.first {
            cacheOrder.removeFirst()
            if let img = cache.removeValue(forKey: victim) {
                cacheBytes -= img.width * img.height * 4
            }
        }
        cacheBytes = max(cacheBytes, 0)
    }

    static func delay(of source: CGImageSource, at index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        var raw: Double?
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            // 部分动图把 0 延时藏在 Unclamped 里。
            raw = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        } else if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            raw = (png[kCGImagePropertyAPNGDelayTime] as? NSNumber)?.doubleValue
        }
        let value = raw ?? 0.1
        // 浏览器惯例：小于 20ms 的帧钳到 ~20fps，避免恶意 0 延时图烧 CPU。
        return max(0.02, min(value, 1.0))
    }
}
