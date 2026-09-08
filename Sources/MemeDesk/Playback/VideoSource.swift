import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// 视频 / MOV / MP4 / M4V 播放器封装。
///
/// 低占用的两个具体做法：
/// - `AVQueuePlayer + AVPlayerLooper` 做**无缝**循环（不是播完 seek 回 0，
///   那样每轮都会有一次解码重启的尖峰）。
/// - 静音时把音轨从素材里**彻底剥离**（合成一条只有视频轨的 AVMutableComposition），
///   系统调用为零，音频解码器完全不会被拉起来。
final class VideoSource {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper?
    private let templateItem: AVPlayerItem

    /// 视频原始尺寸（已应用 preferredTransform），可能异步到达。
    private(set) var naturalSize: CGSize = .zero
    private(set) var duration: TimeInterval = 0
    /// 找得到视频轨才算可播。不可播时调用方会降级成首帧静图或给出提示。
    private(set) var isPlayable = true

    init(url: URL, stripAudio: Bool) async {
        let asset = AVURLAsset(url: url)
        // 只查一次轨道，后面 naturalSize 与"剥音轨"都复用这个结果
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        self.isPlayable = !videoTracks.isEmpty

        let composition = await Self.videoOnlyComposition(for: asset,
                                                          videoTrack: videoTracks.first,
                                                          stripAudio: stripAudio)
        let item = AVPlayerItem(asset: composition)
        let queue = AVQueuePlayer()
        queue.automaticallyWaitsToMinimizeStalling = true
        self.templateItem = item
        self.player = queue
        self.looper = AVPlayerLooper(player: queue, templateItem: item)

        if let videoTrack = videoTracks.first {
            let size = try? await videoTrack.load(.naturalSize)
            let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
            if let size {
                // 拍摄角度 90° 的视频需要交换宽高
                let rotated = abs(transform.b) > 0.5 || abs(transform.c) > 0.5
                naturalSize = rotated ? CGSize(width: size.height, height: size.width) : size
            }
        }
        duration = (try? await asset.load(.duration).seconds) ?? 0
    }

    func play() { player.play() }

    func pause() { player.pause() }

    var isPlaying: Bool { player.timeControlStatus == .playing || player.rate != 0 }

    /// 播放器是否真的起来了。延迟调用：给解码器一点时间，避免误报。
    var hasFailed: Bool {
        player.currentItem?.status == .failed
    }

    var failureReason: String? {
        (player.currentItem?.error as NSError?)?.localizedDescription
    }

    func setRate(_ rate: Float) {
        guard rate > 0 else {
            player.pause()
            return
        }
        player.rate = rate
    }

    func setMuted(_ muted: Bool) {
        player.volume = muted ? 0 : 1
    }

    func seekToBeginning() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    deinit {
        looper?.disableLooping()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// 剥掉音轨，得到一个只有视频的可播放素材。失败时回退到原始 asset。
    private static func videoOnlyComposition(for asset: AVURLAsset,
                                             videoTrack: AVAssetTrack?,
                                             stripAudio: Bool) async -> AVAsset {
        guard stripAudio, let videoTrack else { return asset }
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if audioTracks.isEmpty { return asset } // 本来就没声音，不必折腾

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return asset }
        guard let total = try? await asset.load(.duration) else { return asset }
        do {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: total),
                                      of: videoTrack,
                                      at: .zero)
        } catch {
            return asset
        }
        return composition
    }
}
