import Foundation
import os

private let log = Logger(subsystem: "com.aissam.livewall", category: "lockscreen")

enum LockScreenError: LocalizedError {
    case aerialsMissing
    case storeMissing

    var errorDescription: String? {
        switch self {
        case .aerialsMissing:
            return "macOS hasn't set up its Aerials yet. Open System Settings › Wallpaper once, then try again."
        case .storeMissing:
            return "macOS's wallpaper settings weren't found. Open System Settings › Wallpaper once, then try again."
        }
    }
}

@MainActor
final class LockScreenManager: ObservableObject {
    enum State: Equatable {
        case off
        case working(String)
        case on(String)
        case failed(String)
    }

    @Published private(set) var state: State = .off {
        didSet { if state != oldValue { log.notice("Lock screen: \(String(describing: self.state), privacy: .public)") } }
    }

    private let defaults = UserDefaults.standard
    private let installedKey = "lockScreenInstalledVideoID"

    /// The video currently installed as LiveWall's Aerial, if any.
    private(set) var installedVideoID: UUID? {
        get { defaults.string(forKey: installedKey).flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: installedKey) }
    }

    var isBusy: Bool {
        if case .working = state { return true }
        return false
    }

    func refresh(library: LibraryStore) {
        if let video = library.item(installedVideoID) {
            state = .on(video.name)
        } else if !isBusy {
            state = .off
        }
    }

    /// The latest request that arrived while another was running; only the newest matters.
    private var pending: (video: VideoItem, animate: Bool)?

    func install(_ video: VideoItem, animate: Bool) async {
        if isBusy {
            pending = (video, animate)
            return
        }
        defer {
            if let next = pending {
                pending = nil
                Task { await self.install(next.video, animate: next.animate) }
            }
        }
        state = .working("Adding “\(video.name)”…")
        do {
            let previousID = installedVideoID.map(LockScreenFiles.assetID(for:))
            try await Task.detached(priority: .userInitiated) {
                try await LockScreenFiles.install(video, animate: animate, alsoOwned: previousID)
            }.value
            installedVideoID = video.id

            state = .working("Restarting macOS wallpaper…")
            await WallpaperService.restart()
            try await Task.sleep(nanoseconds: 1_500_000_000)
            let assetID = LockScreenFiles.assetID(for: video.id)
            if !WallpaperStore.selects(assetID) {
                // The wallpaper agent saved its old state while quitting; apply again now it's back.
                try WallpaperStore.select(assetID: assetID, animateOnLockScreen: animate, ownedAssetIDs: [assetID])
                await WallpaperService.restart()
            }
            state = .on(video.name)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func remove() async {
        pending = nil
        state = .working("Restoring the macOS lock screen…")
        let known = installedVideoID.map(LockScreenFiles.assetID(for:))
        do {
            try await Task.detached(priority: .userInitiated) {
                try LockScreenFiles.uninstall(alsoOwned: known)
            }.value
            installedVideoID = nil
            await WallpaperService.restart()
            state = .off
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// macOS rewrites its Aerials list when it downloads updates, which drops LiveWall's
    /// entry. This puts it back without touching the user's wallpaper choice.
    func repairIfNeeded(library: LibraryStore) async {
        guard !isBusy, let video = library.item(installedVideoID) else { return }
        let assetID = LockScreenFiles.assetID(for: video.id)
        let listed = (try? AerialsManifest.liveWallAssetIDs()) ?? []
        let fileExists = FileManager.default.fileExists(atPath: LockScreenFiles.videoURL(assetID: assetID).path)
        guard !listed.contains(assetID) || !fileExists else { return }
        do {
            try await Task.detached(priority: .utility) {
                try await LockScreenFiles.installCatalogEntry(video)
            }.value
            await WallpaperService.restart()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// File work for the lock screen, kept off the main thread.
enum LockScreenFiles {
    static func assetID(for videoID: UUID) -> String { videoID.uuidString.uppercased() }

    static func videoURL(assetID: String) -> URL {
        Paths.aerialsVideos.appendingPathComponent("\(assetID).mov")
    }

    static func previewURL(assetID: String) -> URL {
        Paths.aerialsThumbnails.appendingPathComponent("\(assetID).png")
    }

    static func install(_ video: VideoItem, animate: Bool, alsoOwned: String?) async throws {
        guard AerialsManifest.exists else { throw LockScreenError.aerialsMissing }
        guard WallpaperStore.exists else { throw LockScreenError.storeMissing }
        try backUp()

        let id = assetID(for: video.id)
        let previous = Set(try AerialsManifest.liveWallAssetIDs() + [alsoOwned].compactMap { $0 })
        try await installCatalogEntry(video)
        try WallpaperStore.select(assetID: id, animateOnLockScreen: animate, ownedAssetIDs: previous.union([id]))
        for old in previous where old != id {
            removeFiles(assetID: old)
        }
    }

    static func installCatalogEntry(_ video: VideoItem) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Paths.aerialsVideos, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: Paths.aerialsThumbnails, withIntermediateDirectories: true)

        let id = assetID(for: video.id)
        let destination = videoURL(assetID: id)
        if !fileManager.fileExists(atPath: destination.path) {
            do {
                // A hard link shares the library file's data, so the lock screen costs no extra disk space.
                try fileManager.linkItem(at: video.fileURL, to: destination)
            } catch {
                try fileManager.copyItem(at: video.fileURL, to: destination)
            }
        }

        let preview = previewURL(assetID: id)
        let image = try await VideoImporter.frame(of: video.fileURL, maxPixelSize: 1920)
        try VideoImporter.write(image, to: preview, type: .png)
        try AerialsManifest.install(assetID: id, name: video.name, video: destination, preview: preview)
    }

    static func uninstall(alsoOwned: String?) throws {
        let removed = try AerialsManifest.uninstall()
        let owned = Set(removed + [alsoOwned].compactMap { $0 })
        if WallpaperStore.exists {
            try WallpaperStore.restore(ownedAssetIDs: owned)
        }
        owned.forEach(removeFiles)
    }

    static func removeFiles(assetID: String) {
        try? FileManager.default.removeItem(at: videoURL(assetID: assetID))
        try? FileManager.default.removeItem(at: previewURL(assetID: assetID))
    }

    /// Keeps the five most recent copies of the two macOS files LiveWall edits.
    private static func backUp() throws {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileManager = FileManager.default
        let sources = [("entries", "json", Paths.aerialsManifest), ("Index", "plist", Paths.wallpaperStore)]
        for (prefix, ext, source) in sources {
            try fileManager.copyItem(at: source, to: Paths.backups.appendingPathComponent("\(prefix)-\(stamp).\(ext)"))
            let old = (try? fileManager.contentsOfDirectory(atPath: Paths.backups.path)) ?? []
            let copies = old.filter { $0.hasPrefix("\(prefix)-") && $0.hasSuffix(".\(ext)") }.sorted()
            for name in copies.dropLast(5) {
                try? fileManager.removeItem(at: Paths.backups.appendingPathComponent(name))
            }
        }
    }
}

enum WallpaperService {
    /// macOS relaunches these at once, re-reading the Aerials list and the wallpaper choice.
    static func restart() async {
        for name in ["WallpaperAgent", "WallpaperAerialsExtension"] {
            _ = try? await ProcessRunner.run("/usr/bin/killall", [name])
        }
    }
}
