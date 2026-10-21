import AVFoundation

/// Plays one video in a gapless loop. Every display showing the same video
/// shares one of these, so the video is decoded once no matter how many screens show it.
final class LoopingPlayer {
    let videoID: UUID
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(video: VideoItem) {
        videoID = video.id
        let asset = AVURLAsset(url: video.fileURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1

        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    var isPlaying: Bool { player.rate != 0 }

    func play() {
        if player.rate == 0 { player.play() }
    }

    func pause() {
        if player.rate != 0 { player.pause() }
    }

    func invalidate() {
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
    }
}
