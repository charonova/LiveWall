import AppKit
import AVFoundation

/// A borderless window covering one display at desktop level: above the system
/// wallpaper, below the desktop icons, on every Space, and never clickable.
final class WallpaperWindow: NSWindow {
    let displayID: CGDirectDisplayID
    private(set) var player: LoopingPlayer?
    private var visibleLayer: AVPlayerLayer?
    private var incomingLayer: AVPlayerLayer?
    private var readyObservation: NSKeyValueObservation?

    init(display: DisplayInfo) {
        displayID = display.id
        super.init(contentRect: display.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        canHide = false
        isRestorable = false

        let view = NSView(frame: NSRect(origin: .zero, size: display.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        contentView = view
        setFrame(display.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// False when a fullscreen app, a covering window or a different Space hides the wallpaper.
    var isOnScreenVisible: Bool { occlusionState.contains(.visible) }

    func fit(to display: DisplayInfo) {
        if frame != display.frame { setFrame(display.frame, display: true) }
    }

    /// Switches to another player. The new video fades in once its first frame
    /// is decoded, so a change never flashes black.
    func show(_ newPlayer: LoopingPlayer?) {
        guard newPlayer !== player else { return }
        player = newPlayer
        readyObservation = nil
        incomingLayer?.removeFromSuperlayer()
        incomingLayer = nil
        guard let root = contentView?.layer else { return }

        guard let newPlayer else {
            visibleLayer?.removeFromSuperlayer()
            visibleLayer = nil
            return
        }

        let layer = AVPlayerLayer(player: newPlayer.player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = root.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        root.addSublayer(layer)
        CATransaction.commit()
        incomingLayer = layer

        readyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] observed, _ in
            guard observed.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.reveal(observed) }
        }
    }

    private func reveal(_ layer: AVPlayerLayer) {
        guard layer === incomingLayer else { return }
        readyObservation = nil
        incomingLayer = nil
        let previous = visibleLayer
        visibleLayer = layer
        CATransaction.begin()
        CATransaction.setAnimationDuration(previous == nil ? 0.35 : 0.6)
        CATransaction.setCompletionBlock { previous?.removeFromSuperlayer() }
        layer.opacity = 1
        CATransaction.commit()
    }
}
