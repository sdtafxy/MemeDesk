import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// 缩略图缓存。菜单栏里几十个表情包来回滚动时，不能每张都重新解码。
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let limit = 120

    func cached(url: URL) -> NSImage? {
        let key = url.path
        guard let hit = cache[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    /// 异步取出（必要时解码）缩略图。
    func image(for url: URL, kind: MediaKind, pixel: Int = 88) async -> NSImage? {
        if let hit = cached(url: url) { return hit }
        let result: NSImage?
        switch kind {
        case .video:
            result = await Self.videoThumbnail(url: url, pixel: pixel)
        default:
            result = Self.imageThumbnail(url: url, pixel: pixel)
        }
        guard let image = result else { return nil }
        store(image, for: url.path)
        return image
    }

    private func store(_ image: NSImage, for key: String) {
        cache[key] = image
        order.append(key)
        while order.count > limit, let victim = order.first {
            order.removeFirst()
            cache.removeValue(forKey: victim)
        }
    }

    private static func imageThumbnail(url: URL, pixel: Int) -> NSImage? {
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

    private static func videoThumbnail(url: URL, pixel: Int) async -> NSImage? {
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
