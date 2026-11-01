import AppKit
import CryptoKit
import LiveWallCore
import os

private let log = Logger(subsystem: "com.aissam.livewall", category: "updates")

/// Software updates from LiveWall's GitHub releases, like macOS's own: it checks once a day
/// (unless turned off) and says what's new. Only when the person asks does it download the
/// new version, check it, put it in place of this one and relaunch.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease)
        case installing(AppRelease)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    var checksAutomatically = false {
        didSet { if checksAutomatically != oldValue { schedule() } }
    }

    /// The repository whose releases LiveWall updates from.
    static let feed = URL(string: "https://api.github.com/repos/charonova/LiveWall/releases/latest")!
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var availableRelease: AppRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var timer: Timer?
    private var firstCheck: DispatchWorkItem?
    private let defaults = UserDefaults.standard
    private static let lastCheckKey = "lastUpdateCheck"

    func start() {
        lastChecked = defaults.object(forKey: Self.lastCheckKey) as? Date
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firstCheck?.cancel()
    }

    /// A minute after launch, then every few hours, it checks if a day has passed since the last time.
    private func schedule() {
        stop()
        guard checksAutomatically else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.checkIfDue() } }
        firstCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
        let timer = Timer(timeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfDue() {
        guard checksAutomatically, !isBusy, availableRelease == nil,
              Date().timeIntervalSince(lastChecked ?? .distantPast) > 23 * 3600
        else { return }
        Task { await check() }
    }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            var request = URLRequest(url: Self.feed, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("LiveWall/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw Failure("GitHub answered with error \(status). Try again later.") }
            lastChecked = Date()
            defaults.set(lastChecked, forKey: Self.lastCheckKey)
            if let release = ReleaseFeed.release(from: data), ReleaseFeed.isUpdate(release, over: currentVersion) {
                log.notice("LiveWall \(release.version.description, privacy: .public) is available")
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(Self.describe(error))
        }
    }

    /// Downloads the release, makes sure it's the one promised, and relaunches into it.
    func install() async {
        guard let release = availableRelease else { return }
        state = .downloading(release)
        do {
            let target = Bundle.main.bundleURL
            let parent = target.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: parent.path) else {
                throw Failure("LiveWall can't replace itself in \(parent.path). Download the new version from its release page instead.")
            }
            // A folder on the same disk as the app, so the final move is quick.
            let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                     appropriateFor: target, create: true)
            let zip = folder.appendingPathComponent(ReleaseFeed.archiveName)
            let (downloaded, response) = try await URLSession.shared.download(from: release.archive)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("The download didn't finish. Try again.") }
            try FileManager.default.moveItem(at: downloaded, to: zip)

            if let checksumURL = release.checksum {
                let (data, _) = try await URLSession.shared.data(from: checksumURL)
                guard let expected = ReleaseFeed.checksum(in: String(decoding: data, as: UTF8.self)) else {
                    throw Failure("The release's checksum couldn't be read.")
                }
                let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw Failure("The download doesn't match its checksum, so it wasn't installed.") }
            }

            state = .installing(release)
            let unpacked = folder.appendingPathComponent("unpacked")
            guard try await ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]).status == 0 else {
                throw Failure("The download couldn't be unpacked.")
            }
            let app = unpacked.appendingPathComponent("LiveWall.app")
            // It must be LiveWall, the version promised, with an intact signature.
            guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init),
                  version == release.version
            else { throw Failure("The download isn't LiveWall \(release.version), so it wasn't installed.") }
            guard try await ProcessRunner.run("/usr/bin/codesign", ["--verify", "--strict", "--deep", app.path]).status == 0 else {
                throw Failure("The new version's signature is broken, so it wasn't installed.")
            }
            log.notice("Installing LiveWall \(release.version.description, privacy: .public)")
            try relaunch(replacing: target, with: app, leftovers: folder)
        } catch {
            log.error("Update failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(Self.describe(error))
        }
    }

    /// A few lines of shell, left running after LiveWall quits: they wait for it to end, swap
    /// the apps (the old one stays until the new one is in place, and comes back if the move
    /// fails), and open whichever is there.
    private func relaunch(replacing target: URL, with app: URL, leftovers: URL) throws {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        previous="$2.previous"
        rm -rf "$previous"
        if mv "$2" "$previous"; then
            if mv "$3" "$2"; then rm -rf "$previous"; else mv "$previous" "$2"; fi
        fi
        rm -rf "$4"
        open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "livewall-update", String(getpid()), target.path, app.path, leftovers.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        NSApp.terminate(nil)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? Failure { return failure.message }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline. Connect to the internet and try again." }
        return error.localizedDescription
    }
}
