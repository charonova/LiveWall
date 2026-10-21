import Foundation

enum Paths {
    // LiveWall's own data.
    static let appSupport = directory(
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveWall", isDirectory: true))
    static let videos = directory(appSupport.appendingPathComponent("Videos", isDirectory: true))
    static let thumbnails = directory(appSupport.appendingPathComponent("Thumbnails", isDirectory: true))
    static let backups = directory(appSupport.appendingPathComponent("Backups", isDirectory: true))
    static let libraryFile = appSupport.appendingPathComponent("library.json")

    // macOS wallpaper data, used for the lock screen.
    static let wallpaperRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper", isDirectory: true)
    static let aerialsManifest = wallpaperRoot.appendingPathComponent("aerials/manifest/entries.json")
    static let aerialsVideos = wallpaperRoot.appendingPathComponent("aerials/videos", isDirectory: true)
    static let aerialsThumbnails = wallpaperRoot.appendingPathComponent("aerials/thumbnails", isDirectory: true)
    static let wallpaperStore = wallpaperRoot.appendingPathComponent("Store/Index.plist")

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
