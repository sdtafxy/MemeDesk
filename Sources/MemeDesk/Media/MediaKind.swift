import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 素材种类。
public enum MediaKind: String, Codable, CaseIterable, Sendable {
    /// 动图：GIF / APNG / 动画 WebP。
    case animatedImage
    /// 静态图：PNG / JPG / HEIC / WebP。
    case stillImage
    /// 视频：MP4 / MOV / M4V。
    case video

    var label: String {
        switch self {
        case .animatedImage: L(.kindAnimated)
        case .stillImage: L(.kindStill)
        case .video: L(.kindVideo)
        }
    }

    /// 是否支持循环连续播放。
    var isAnimated: Bool { self != .stillImage }
}

/// Security-Scoped Bookmark 的读写助手。
enum Bookmark {
    static func data(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
    }

    static func url(from data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return url
    }
}

/// 素材探测：不靠扩展名猜，直接看着魔数说话。
enum MediaProbe {
    /// 被支持的扩展名（用于文件面板过滤）。
    static let allowedExtensions: [String] = [
        "gif", "png", "apng", "jpg", "jpeg", "heic", "webp", "bmp", "tiff",
        "mp4", "mov", "m4v",
    ]

    /// 这些扩展名直接按视频处理。
    ///
    /// 关键点：**必须排在 ImageIO 之前**。ImageIO 在部分系统版本上能把 MP4/MOV
    /// 打开成一个"单帧图像源"，一旦被它抢走就会走静态图路径，最后报"解码失败"，
    /// 而 QuickTime 明明能正常播放同一个文件。
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// 判断顺序：扩展名 -> UTType -> ImageIO -> 魔数。比单纯看扩展名可靠得多。
    static func kind(of url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .video }

        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .movie) || type.conforms(to: .video) {
            return .video
        }

        // ImageIO 能打开就是图；帧数 > 1 就是动图
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            if CGImageSourceGetCount(source) > 1 { return .animatedImage }
            if let raw = CGImageSourceGetType(source) as? String,
               raw == UTType.gif.identifier || raw == UTType.webP.identifier {
                // 少数动图只声明一帧（例如某些循环标记写在全局属性里的 GIF 变体）
                return .animatedImage
            }
            return .stillImage
        }

        // ImageIO 完全打不开：按魔数兜底，认不出也按视频处理（之后会给出明确的错误提示）
        return sniffHeader(of: url) ?? .video
    }

    /// 读文件头判断容器类型，只读 16 字节。
    private static func sniffHeader(of url: URL) -> MediaKind? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 16)
        guard data.count >= 12 else { return nil }
        let b = [UInt8](data)

        // GIF8
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return .animatedImage }
        // PNG / JPEG / HEIC(ftyp 之外的常见图片容器这里不展开)
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return .stillImage }
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return .stillImage }
        // RIFF 容器：WEBP 是图，AVI 是视频
        if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46 {
            if b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return .stillImage }
            if b[8] == 0x41, b[9] == 0x56, b[10] == 0x49, b[11] == 0x20 { return .video }
        }
        // ISO BMFF：第 4..8 字节是 box 类型，ftyp/moov/mdat 都指向视频
        if let brand = String(bytes: b[4..<8], encoding: .ascii),
           ["ftyp", "moov", "mdat", "wide", "skip", "free", "pnot"].contains(brand) {
            return .video
        }
        // Matroska / WebM
        if b[0] == 0x1A, b[1] == 0x45, b[2] == 0xDF, b[3] == 0xA3 { return .video }
        return nil
    }

    /// ImageIO 读像素尺寸：优先单帧属性，再退回容器属性。
    static func imagePixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let read: ([CFString: Any]?) -> CGSize? = { props in
            guard let props,
                  let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                  w > 0, h > 0 else { return nil }
            return CGSize(width: w, height: h)
        }
        if let size = read(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) {
            return size
        }
        return read(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
    }

    /// 读取原始像素尺寸。视频走 AVAsset，可能较慢，所以用 async。
    static func intrinsicSize(of url: URL, kind: MediaKind) async -> CGSize {
        switch kind {
        case .video:
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize) else { return CGSize(width: 256, height: 256) }
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let rotated = abs(transform.b) > 0.5 || abs(transform.c) > 0.5
            let final = rotated ? CGSize(width: size.height, height: size.width) : size
            return final.width > 0 && final.height > 0 ? final : CGSize(width: 256, height: 256)
        default:
            // 兜底必须是正常人眼尺寸：以前返回 1×1，会让"还原原始大小"把窗口缩到看不见
            return imagePixelSize(of: url) ?? CGSize(width: 256, height: 256)
        }
    }
}

/// 素材库里的一个条目。
struct MediaItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
    let kind: MediaKind

    init(id: UUID = UUID(), url: URL, kind: MediaKind? = nil) {
        self.id = id
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.kind = kind ?? MediaProbe.kind(of: url)
    }
}
