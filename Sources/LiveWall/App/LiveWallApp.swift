import SwiftUI
import os

@main
struct LiveWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(appDelegate.controller)
                .environmentObject(appDelegate.controller.settings)
                .environmentObject(appDelegate.controller.library)
                .environmentObject(appDelegate.controller.lockScreen)
                .environmentObject(appDelegate.controller.updater)
        } label: {
            Image(systemName: "play.rectangle.on.rectangle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    /// Videos opened with LiveWall (Finder › Open With) are added to the library;
    /// livewall:// links control playback and updates, e.g. from Shortcuts.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { controller.library.importVideos(files) }
        for url in urls where url.scheme == "livewall" {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        Logger(subsystem: "com.aissam.livewall", category: "url").notice("Open \(url.absoluteString, privacy: .public)")
        let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }).map { $0.lowercased() }
        switch parts.first {
        case "pause": controller.isPausedByUser = true
        case "play": controller.isPausedByUser = false
        case "toggle": controller.isPausedByUser.toggle()
        case "lockscreen":
            if parts.dropFirst().first == "off" {
                controller.restoreLockScreen()
            } else if let id = parts.dropFirst().first.flatMap(UUID.init(uuidString:)),
                      let video = controller.library.item(id) {
                controller.useOnLockScreen(video)
            }
        case "update":
            // update: check now; update/install also installs what it finds.
            let install = parts.dropFirst().first == "install"
            Task {
                await controller.updater.check()
                if install { await controller.updater.install() }
            }
        default:
            break
        }
    }
}
