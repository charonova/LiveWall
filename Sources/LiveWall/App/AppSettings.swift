import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    /// The video shown on every display without its own choice.
    @Published var wallpaperID: UUID? { didSet { defaults.set(wallpaperID?.uuidString, forKey: Key.wallpaper) } }
    /// Display UUID → video, for displays that show something else.
    @Published var displayOverrides: [String: UUID] {
        didSet { defaults.set(displayOverrides.mapValues(\.uuidString), forKey: Key.overrides) }
    }
    @Published var pauseWhenHidden: Bool { didSet { defaults.set(pauseWhenHidden, forKey: Key.pauseWhenHidden) } }
    @Published var pauseOnBattery: Bool { didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery) } }
    @Published var pauseInLowPower: Bool { didSet { defaults.set(pauseInLowPower, forKey: Key.pauseInLowPower) } }
    @Published var lockScreenVideoID: UUID? { didSet { defaults.set(lockScreenVideoID?.uuidString, forKey: Key.lockScreenVideo) } }
    /// When the lock screen is in use, it switches along with the main wallpaper.
    @Published var lockScreenFollowsWallpaper: Bool {
        didSet { defaults.set(lockScreenFollowsWallpaper, forKey: Key.lockScreenFollows) }
    }
    /// Also puts the video in the macOS desktop slot, which is what animates on the lock screen.
    @Published var lockScreenAnimates: Bool { didSet { defaults.set(lockScreenAnimates, forKey: Key.lockScreenAnimates) } }

    init() {
        defaults.register(defaults: [
            Key.pauseWhenHidden: true,
            Key.pauseOnBattery: false,
            Key.pauseInLowPower: true,
            Key.lockScreenAnimates: true,
            Key.lockScreenFollows: true,
        ])
        wallpaperID = defaults.string(forKey: Key.wallpaper).flatMap(UUID.init)
        displayOverrides = (defaults.dictionary(forKey: Key.overrides) as? [String: String] ?? [:])
            .compactMapValues(UUID.init)
        pauseWhenHidden = defaults.bool(forKey: Key.pauseWhenHidden)
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        pauseInLowPower = defaults.bool(forKey: Key.pauseInLowPower)
        lockScreenVideoID = defaults.string(forKey: Key.lockScreenVideo).flatMap(UUID.init)
        lockScreenAnimates = defaults.bool(forKey: Key.lockScreenAnimates)
        lockScreenFollowsWallpaper = defaults.bool(forKey: Key.lockScreenFollows)
    }

    private enum Key {
        static let wallpaper = "wallpaperID"
        static let overrides = "displayOverrides"
        static let pauseWhenHidden = "pauseWhenHidden"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseInLowPower = "pauseInLowPower"
        static let lockScreenVideo = "lockScreenVideoID"
        static let lockScreenAnimates = "lockScreenAnimates"
        static let lockScreenFollows = "lockScreenFollowsWallpaper"
    }
}
