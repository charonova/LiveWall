import AppKit
import AVFoundation

/// Owns the wallpaper windows (one per display) and the players behind them.
@MainActor
final class WallpaperEngine {
    struct Summary {
        /// Videos playing on the desktop.
        var playing = 0
        var shown = 0
        /// The panel's preview is playing.
        var previewing = false
    }

    /// Called when a wallpaper becomes covered or uncovered.
    var onVisibilityChange: (() -> Void)?

    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var players: [UUID: LoopingPlayer] = [:]
    private var occlusionObservers: [CGDirectDisplayID: NSObjectProtocol] = [:]

    /// Lays out a window on every display and attaches the shared player for its video.
    func configure(displays: [DisplayInfo], videoFor: (DisplayInfo) -> VideoItem?) {
        let plan = displays.map { (display: $0, video: videoFor($0)) }
        let liveIDs = Set(displays.map(\.id))

        for (id, window) in windows where !liveIDs.contains(id) {
            close(window)
        }

        var wanted: [UUID: VideoItem] = [:]
        for entry in plan {
            if let video = entry.video { wanted[video.id] = video }
        }
        for (id, video) in wanted where players[id] == nil {
            players[id] = LoopingPlayer(video: video)
        }

        for entry in plan {
            let window = windows[entry.display.id] ?? makeWindow(for: entry.display)
            window.fit(to: entry.display)
            if let video = entry.video {
                window.show(players[video.id])
                window.orderFrontRegardless()
            } else {
                window.show(nil)
                window.orderOut(nil)
            }
        }

        let unused = players.filter { wanted[$0.key] == nil }
        retire(Array(unused.values))
        for id in unused.keys { players[id] = nil }
    }

    /// Replaces every player with a fresh one, e.g. after sleep, when a decoder
    /// can come back stuck on a black frame.
    func reloadPlayers(displays: [DisplayInfo], videoFor: (DisplayInfo) -> VideoItem?) {
        let old = Array(players.values)
        players.removeAll()
        configure(displays: displays, videoFor: videoFor)
        retire(old)
    }

    func player(for videoID: UUID) -> AVPlayer? {
        players[videoID]?.player
    }

    /// Plays each video only while it's allowed and visible on at least one display,
    /// or while the panel is previewing it.
    @discardableResult
    func updatePlayback(allowed: Bool, pauseWhenHidden: Bool, previewing: UUID?) -> Summary {
        var summary = Summary()
        for (id, player) in players {
            let showing = windows.values.filter { $0.player?.videoID == id && $0.isVisible }
            summary.shown += showing.count
            let onDesktop = !showing.isEmpty && (!pauseWhenHidden || showing.contains { $0.isOnScreenVisible })
            let inPreview = previewing == id
            if allowed && (onDesktop || inPreview) {
                player.play()
                if onDesktop { summary.playing += 1 }
                if inPreview { summary.previewing = true }
            } else {
                player.pause()
            }
        }
        return summary
    }

    func tearDown() {
        windows.values.forEach(close)
        players.values.forEach { $0.invalidate() }
        players.removeAll()
    }

    private func makeWindow(for display: DisplayInfo) -> WallpaperWindow {
        let window = WallpaperWindow(display: display)
        windows[display.id] = window
        occlusionObservers[display.id] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onVisibilityChange?() }
        }
        return window
    }

    private func close(_ window: WallpaperWindow) {
        if let observer = occlusionObservers.removeValue(forKey: window.displayID) {
            NotificationCenter.default.removeObserver(observer)
        }
        window.show(nil)
        window.orderOut(nil)
        windows[window.displayID] = nil
    }

    /// Keeps old players alive through the cross-fade, then frees their decoders.
    private func retire(_ old: [LoopingPlayer]) {
        guard !old.isEmpty else { return }
        old.forEach { $0.pause() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            old.forEach { $0.invalidate() }
        }
    }
}
