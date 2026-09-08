import CoreGraphics
import Foundation
import ImageIO

/// 动图（GIF / APNG / 动画 WebP）解码器。
///
/// 三件让它保持轻盈的事：
/// 1. **下采样解码**：用 ImageIO 的 thumbnail 接口按目标尺寸解出 CGImage，
///    一个 800×800 的表情包在 200pt 的窗口里只会解出 ~400px 的位图，
///    内存与解压耗时都降到原来的 1/4 —— 这比解码后再用 CALayer 缩放省得多。
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
    private var needsDownsample: Bool

    private let lock = NSLock()
    private var cache: [Int: CGImage] = [:]
    private var cacheOrder: [Int] = []
    private var cacheBytes: Int = 0
    private var pendingDecode: Set<Int> = []
    /// 最大单边像素超过这个值时即便用户要求也强制降档，防止 4K 动图把 Mac 拖死。
    private let cacheByteLimit = 32 * 1024 * 1024

    private let decodeQueue = DispatchQueue(label: "com.memedesk.gif.decode", qos: .utility)

    init(url: URL, targetPixel: Int) throws {
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
        let clamped = max(16, min(targetPixel, nativeMax > 0 ? nativeMax : targetPixel))
        self.targetPixel = clamped
        self.needsDownsample = nativeMax > clamped

        self.delays = (0..<count).map { Self.delay(of: source, at: $0) }
        var acc: TimeInterval = 0
        var table: [TimeInterval] = [0]
        for d in delays {
            acc += d
            table.append(acc)
        }
        self.cumulative = table
        self.totalDuration = max(acc, 0.001)
    }

    deinit {
        cache.removeAll(keepingCapacity: false)
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
