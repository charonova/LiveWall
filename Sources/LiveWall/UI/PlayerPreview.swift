import AVFoundation
import SwiftUI

/// Shows an existing player. Pointing it at the wallpaper's own player means the
/// preview costs no extra decoding: it's the same frames the desktop shows.
struct PlayerPreview: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> PlayerPreviewView {
        PlayerPreviewView()
    }

    func updateNSView(_ view: PlayerPreviewView, context: Context) {
        view.player = player
    }
}

final class PlayerPreviewView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { if playerLayer.player !== newValue { playerLayer.player = newValue } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
