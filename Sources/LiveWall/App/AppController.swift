import AppKit
import AVFoundation
import Combine
import os

enum PanelPage {
    case library
    case settings
}

struct PlaybackStatus: Equatable {
    var text: String
    var isPlaying: Bool
}

@MainActor
final class AppController: ObservableObject {
    let settings = AppSettings()
    let library = LibraryStore()
    let lockScreen = LockScreenManager()
    let updater = Updater()

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var status = PlaybackStatus(text: "Starting…", isPlaying: false) {
        didSet {
            if status != oldValue { log.notice("Status: \(self.status.text, privacy: .public)") }
        }
    }
    @Published var isPausedByUser = false { didSet { updatePlayback() } }
    @Published private(set) var launchAtLogin = LoginItem.isEnabled
    @Published private(set) var lastError: String?

    // Panel state lives here because SwiftUI's @State macro needs Xcode's plugins to build.
    /// The display the library grid applies to; nil means every display.
    @Published var targetDisplayID: CGDirectDisplayID? { didSet { updatePlayback() } }
    @Published var isDropTargeted = false
    @Published var hoveredVideoID: UUID?
    @Published var page: PanelPage = .library
    /// While the panel is open its preview plays, even if the desktop itself is covered.
    @Published private(set) var isPanelOpen = false

    private let log = Logger(subsystem: "com.aissam.livewall", category: "playback")
    private let engine = WallpaperEngine()
    private let conditions = PlaybackConditions()
    private var cancellables = Set<AnyCancellable>()
    private var screenChangeWork: DispatchWorkItem?
    private var repairTimer: Timer?
    private var playbackActivity: NSObjectProtocol?

    func start() {
        library.load()
        library.onImported = { [weak self] video in self?.didImport(video) }
        engine.onVisibilityChange = { [weak self] in self?.updatePlayback() }
        conditions.onChange = { [weak self] in self?.updatePlayback() }
        conditions.onWake = { [weak self] in self?.handleWake() }
        conditions.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleLayout() }
        }

        // Re-evaluate playback whenever a pause setting changes (after the new value is stored).
        Publishers.MergeMany(settings.$pauseWhenHidden, settings.$pauseOnBattery, settings.$pauseInLowPower)
            .dropFirst(3)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePlayback() }
            .store(in: &cancellables)
        settings.$lockScreenAnimates
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reinstallLockScreen() }
            .store(in: &cancellables)
        // Starts the daily update check, now and whenever the setting is turned on.
        updater.start()
        settings.$checkForUpdates
            .sink { [weak self] in self?.updater.checksAutomatically = $0 }
            .store(in: &cancellables)

        layoutWallpapers()
        lockScreen.refresh(library: library)
        Task { await lockScreen.repairIfNeeded(library: library) }
        repairTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.lockScreen.repairIfNeeded(library: self.library) }
            }
        }
    }

    func stop() {
        repairTimer?.invalidate()
        updater.stop()
        conditions.stop()
        engine.tearDown()
    }

    // MARK: - Wallpaper

    func video(for display: DisplayInfo) -> VideoItem? {
        library.item(settings.displayOverrides[display.uuid]) ?? library.item(settings.wallpaperID)
    }

    /// True when the video is what the given target shows (nil = every display).
    func isShowing(_ video: VideoItem, on display: DisplayInfo?) -> Bool {
        guard let display else { return settings.wallpaperID == video.id }
        return self.video(for: display)?.id == video.id
    }

    func setWallpaper(_ video: VideoItem, on display: DisplayInfo?) {
        if let display {
            settings.displayOverrides[display.uuid] = video.id
            if settings.wallpaperID == nil { settings.wallpaperID = video.id }
        } else {
            settings.wallpaperID = video.id
            settings.displayOverrides.removeAll()
        }
        layoutWallpapers()

        // Keep the lock screen in step, but only once the user has turned it on.
        let isMainChoice = display == nil || display?.id == CGMainDisplayID()
        if isMainChoice, settings.lockScreenFollowsWallpaper,
           lockScreen.installedVideoID != nil, lockScreen.installedVideoID != video.id {
            useOnLockScreen(video)
        }
    }

    func remove(_ video: VideoItem) {
        if lockScreen.installedVideoID == video.id {
            settings.lockScreenVideoID = nil
            Task { await lockScreen.remove() }
        }
        if settings.wallpaperID == video.id {
            settings.wallpaperID = library.items.first { $0.id != video.id }?.id
        }
        settings.displayOverrides = settings.displayOverrides.filter { $0.value != video.id }
        library.remove(video)
        layoutWallpapers()
    }

    func revealInFinder(_ video: VideoItem) {
        NSWorkspace.shared.activateFileViewerSelecting([video.fileURL])
    }

    func rename(_ video: VideoItem) {
        let alert = NSAlert()
        alert.messageText = "Rename Wallpaper"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: video.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != video.name else { return }
        library.rename(video, to: name)
    }

    // MARK: - Panel

    /// The video the panel's hero previews: the chosen display's, or the main wallpaper.
    var previewVideo: VideoItem? {
        if let display = displays.first(where: { $0.id == targetDisplayID }) {
            return video(for: display)
        }
        return library.item(settings.wallpaperID) ?? displays.lazy.compactMap(video(for:)).first
    }

    var previewPlayer: AVPlayer? {
        previewVideo.flatMap { engine.player(for: $0.id) }
    }

    func panelDidOpen() {
        isPanelOpen = true
        updatePlayback()
    }

    func panelDidClose() {
        isPanelOpen = false
        hoveredVideoID = nil
        page = .library
        updatePlayback()
    }

    // MARK: - Lock screen

    func useOnLockScreen(_ video: VideoItem) {
        settings.lockScreenVideoID = video.id
        Task { await lockScreen.install(video, animate: settings.lockScreenAnimates) }
    }

    func useCurrentOnLockScreen() {
        if let video = previewVideo { useOnLockScreen(video) }
    }

    func restoreLockScreen() {
        settings.lockScreenVideoID = nil
        Task { await lockScreen.remove() }
    }

    func isOnLockScreen(_ video: VideoItem) -> Bool {
        lockScreen.installedVideoID == video.id
    }

    var isLockScreenOn: Bool { lockScreen.installedVideoID != nil }

    func setLockScreen(_ on: Bool) {
        if on {
            useCurrentOnLockScreen()
        } else {
            restoreLockScreen()
        }
    }

    private func reinstallLockScreen() {
        guard let video = library.item(lockScreen.installedVideoID) else { return }
        Task { await lockScreen.install(video, animate: settings.lockScreenAnimates) }
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            lastError = nil
        } catch {
            lastError = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: - Playback

    private func didImport(_ video: VideoItem) {
        if library.item(settings.wallpaperID) == nil {
            setWallpaper(video, on: nil)
        }
    }

    private func scheduleLayout() {
        // Display changes arrive in bursts; lay out once they settle.
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.layoutWallpapers() }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func layoutWallpapers() {
        displays = DisplayInfo.current()
        engine.configure(displays: displays) { [unowned self] in self.video(for: $0) }
        updatePlayback()
    }

    private func handleWake() {
        displays = DisplayInfo.current()
        engine.reloadPlayers(displays: displays) { [unowned self] in self.video(for: $0) }
        updatePlayback()
        Task { await lockScreen.repairIfNeeded(library: library) }
    }

    private func updatePlayback() {
        let reason = isPausedByUser
            ? "Paused"
            : conditions.blockReason(pauseOnBattery: settings.pauseOnBattery, pauseInLowPower: settings.pauseInLowPower)
        let summary = engine.updatePlayback(
            allowed: reason == nil,
            pauseWhenHidden: settings.pauseWhenHidden,
            previewing: isPanelOpen ? previewVideo?.id : nil)

        if library.item(settings.wallpaperID) == nil && settings.displayOverrides.isEmpty {
            status = PlaybackStatus(text: "Add a video to begin", isPlaying: false)
        } else if let reason {
            status = PlaybackStatus(text: reason == "Paused" ? "Paused" : "Paused · \(reason)", isPlaying: false)
        } else if summary.playing > 0 {
            let screens = displays.count == 1 ? "1 display" : "\(displays.count) displays"
            status = PlaybackStatus(text: "Playing on \(screens)", isPlaying: true)
        } else {
            status = PlaybackStatus(text: "Resting · desktop covered", isPlaying: false)
        }
        updateAppNap(playing: summary.playing > 0 || summary.previewing)
    }

    /// Keeps App Nap from throttling playback, only while something is actually playing.
    private func updateAppNap(playing: Bool) {
        if playing, playbackActivity == nil {
            playbackActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep], reason: "Playing a live wallpaper")
        } else if !playing, let activity = playbackActivity {
            ProcessInfo.processInfo.endActivity(activity)
            playbackActivity = nil
        }
    }
}
