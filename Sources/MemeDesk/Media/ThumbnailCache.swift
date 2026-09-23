import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// 缩略图缓存。菜单栏里几十个表情包来回滚动时，不能每张都重新解码。
///
/// ⚠️ 这个类整体是 `@MainActor`（缓存要主线程独占），但**解码必须在后台**。
/// 以前 `image(for:)` 虽然标了 `async`，里面走的却是同一个类的 `static func` ——
/// 那也会被推断成主 actor 隔离，于是 `.task` 里其实是**同步跑在主线程**上的，
/// 素材库/面板滚动时每个单元格都解码一次，必然掉帧。现在解码统一走 `Task.detached`。
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    /// 正在解码中的任务，按 key 索引。见 `image(for:)` 的说明。
    private var inFlight: [String: DecodeJob] = [:]
    private let limit = 120

    func cached(url: URL) -> NSImage? {
        let key = url.path
        guard let hit = cache[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    /// 异步取出（必要时解码）缩略图。
    ///
    /// `kind` 传 nil 时会**在后台**顺手探测 —— 探测本身要读文件头，
    /// 也不该占主线程。
    func image(for url: URL, kind: MediaKind? = nil, pixel: Int = 88) async -> NSImage? {
        if let hit = cached(url: url) { return hit }
        let key = url.path

        // ⚠️ **在飞去重**。主 actor 只保证"检查缓存"与"写入缓存"之间原子；
        // `await ...value` 挂起期间，另一路对同一个 key 的请求照样会 miss，
        // 于是两次解码、两次 `store` —— `order` 里出现重复 key，
        // 较早那份被 LRU 淘汰时会把仍在用的条目删掉。素材库网格和菜单栏面板
        // 完全可能同时指向同一个文件，所以这不是理论问题。
        let job: DecodeJob
        if let existing = inFlight[key] {
            job = existing
        } else {
            let id = UUID()
            let task = Task.detached(priority: .utility) {
                let resolved = kind ?? MediaProbe.kind(of: url)
                return ThumbnailBox(decoded: resolved == .video
                                    ? await Self.videoThumbnail(url: url, pixel: pixel)
                                    : Self.imageThumbnail(url: url, pixel: pixel))
            }
            job = DecodeJob(id: id, task: task)
            inFlight[key] = job
        }

        let box = await job.task.value
        // 只清掉自己发起的那一份：晚到的请求可能已经换了新任务，别替它清。
        if inFlight[key]?.id == job.id { inFlight[key] = nil }
        guard let image = box.decoded else { return nil }
        // 另一路可能已经先写进去了，这里再查一次，避免重复记账。
        if let hit = cached(url: url) { return hit }
        store(image, for: key)
        return image
    }

    /// 正在解码中的一个任务 + 它的身份。身份用来判断"要不要由我来清账"。
    private struct DecodeJob {
        let id: UUID
        let task: Task<ThumbnailBox, Never>
    }

    /// 只是为了把 `NSImage` 送过后台 → 主线程的边界。
    ///
    /// `NSImage` 不是 `Sendable`（它是 NSObject 子类），但这里传的是**后台刚建好、
    /// 还没有别人引用过**的实例，跨过去之后只在主线程用，不存在并发写。
    private struct ThumbnailBox: @unchecked Sendable {
        let decoded: NSImage?
    }

    private func store(_ image: NSImage, for key: String) {
        cache[key] = image
        order.append(key)
        while order.count > limit, let victim = order.first {
            order.removeFirst()
            cache.removeValue(forKey: victim)
        }
    }

    private nonisolated static func imageThumbnail(url: URL, pixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private nonisolated static func videoThumbnail(url: URL, pixel: Int) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixel, height: pixel)
        do {
            let cg = try await generator.image(at: .zero).image
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }
}
