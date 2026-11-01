import AVFoundation
import LiveWallCore
import SwiftUI
import UniformTypeIdentifiers

private let tileHeight: CGFloat = 82
private let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)

struct MenuPanel: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var library: LibraryStore

    /// The panel never changes size while open: a menu bar window that shrinks
    /// keeps its bottom edge and leaves a gap under the menu bar.
    private var panelHeight: CGFloat { app.displays.count > 1 ? 646 : 604 }

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                if app.page == .library {
                    LibraryPage(onAdd: chooseVideos)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    SettingsPage()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            Footer()
        }
        .padding(16)
        .frame(width: 440, height: panelHeight)
        .onAppear { app.panelDidOpen() }
        .onDisappear { app.panelDidClose() }
        .onDrop(of: [.fileURL], isTargeted: $app.isDropTargeted, perform: importDropped)
        .overlay { if app.isDropTargeted { DropOverlay() } }
        .animation(spring, value: app.isDropTargeted)
    }

    private func chooseVideos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose videos to use as wallpapers"
        panel.allowedContentTypes = [.movie, .video, .gif]
            + ["webm", "mkv"].compactMap { UTType(filenameExtension: $0) }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { return }
            library.importVideos(panel.urls)
        }
    }

    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in library.importVideos([url]) }
            }
        }
        return true
    }
}

// MARK: - Pages

private struct LibraryPage: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var library: LibraryStore
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeroCard(onAdd: onAdd)
            if app.displays.count > 1 { DisplayChips() }
            if !library.items.isEmpty || !library.jobs.isEmpty {
                LibrarySection(onAdd: onAdd)
            }
            LockScreenRow()
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsPage: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(spring) { app.page = .library }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .glassButton()
                .buttonBorderShape(.circle)
                .help("Back")
                Text("Settings").font(.title3.weight(.semibold))
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Playback")
                    Card {
                        SettingRow(
                            symbol: "eye.slash.fill", color: .blue,
                            title: "Pause When Covered",
                            subtitle: "Rests behind windows and full-screen apps"
                        ) { RowSwitch(isOn: $settings.pauseWhenHidden) }
                        CardDivider()
                        SettingRow(symbol: "battery.50percent", color: .green, title: "Pause on Battery") {
                            RowSwitch(isOn: $settings.pauseOnBattery)
                        }
                        CardDivider()
                        SettingRow(symbol: "leaf.fill", color: .orange, title: "Pause in Low Power Mode") {
                            RowSwitch(isOn: $settings.pauseInLowPower)
                        }
                    }

                    SectionLabel("Lock Screen")
                    Card {
                        SettingRow(
                            symbol: "arrow.triangle.2.circlepath", color: .teal,
                            title: "Follow Wallpaper",
                            subtitle: "Changes along with your desktop"
                        ) { RowSwitch(isOn: $settings.lockScreenFollowsWallpaper) }
                        CardDivider()
                        SettingRow(
                            symbol: "sparkles", color: .indigo,
                            title: "Animate on Lock Screen",
                            subtitle: "Moves when you lock your Mac"
                        ) { RowSwitch(isOn: $settings.lockScreenAnimates) }
                    }

                    SectionLabel("General")
                    Card {
                        SettingRow(symbol: "power", color: .gray, title: "Open at Login") {
                            RowSwitch(isOn: Binding(get: { app.launchAtLogin }, set: app.setLaunchAtLogin))
                        }
                        CardDivider()
                        SettingRow(
                            symbol: "film.stack", color: .pink,
                            title: "Library",
                            subtitle: library.storageSummary
                        ) {
                            Button("Show") { NSWorkspace.shared.open(Paths.videos) }
                                .glassButton()
                                .controlSize(.small)
                        }
                    }

                    SectionLabel("Software Update")
                    SoftwareUpdateCard()

                    if let error = app.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
        }
    }
}

/// Software Update, like the one in System Settings: the version running, whether a newer one
/// is out and what's in it, and the button that installs it.
private struct SoftwareUpdateCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Card {
            SettingRow(symbol: symbol, color: color, title: title, subtitle: subtitle,
                       subtitleColor: isFailed ? .red : .secondary) { accessory }
            if let release = updater.availableRelease {
                VStack(alignment: .leading, spacing: 6) {
                    if !release.notes.isEmpty {
                        Text(notes(release.notes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Link("Release Notes", destination: release.page).font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 48)
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }
            CardDivider()
            SettingRow(
                symbol: "clock.arrow.circlepath", color: .gray,
                title: "Check Automatically",
                subtitle: "Once a day, from GitHub. Never installs without you"
            ) { RowSwitch(isOn: $settings.checkForUpdates) }
        }
        .animation(.smooth, value: updater.state)
    }

    @ViewBuilder private var accessory: some View {
        if updater.isBusy {
            ProgressView().controlSize(.small)
        } else if updater.availableRelease != nil {
            Button("Update Now") { Task { await updater.install() } }
                .glassButton(prominent: true)
                .controlSize(.small)
        } else {
            Button("Check Now") { Task { await updater.check() } }
                .glassButton()
                .controlSize(.small)
        }
    }

    private var isFailed: Bool {
        if case .failed = updater.state { return true }
        return false
    }

    private var symbol: String {
        switch updater.state {
        case .available: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .upToDate: return "checkmark.seal.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch updater.state {
        case .failed: return .orange
        case .upToDate: return .green
        default: return .teal
        }
    }

    private var title: String {
        switch updater.state {
        case .available(let release): return "LiveWall \(release.version.description) is available"
        case .upToDate: return "LiveWall is up to date"
        default: return "LiveWall \(updater.currentVersion)"
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .checking: return "Checking for updates…"
        case .downloading(let release): return "Downloading LiveWall \(release.version.description)…"
        case .installing(let release): return "Installing LiveWall \(release.version.description). It reopens in a moment."
        case .available(let release):
            let size = release.size > 0 ? " · " + ByteCountFormatter.string(fromByteCount: Int64(release.size), countStyle: .file) : ""
            return "You have version \(updater.currentVersion)\(size)"
        case .failed(let message): return message
        case .upToDate, .idle: return checkedLine
        }
    }

    private var checkedLine: String {
        guard let checked = updater.lastChecked else { return "Version \(updater.currentVersion)" }
        let ago = Date().timeIntervalSince(checked) < 60
            ? "just now" : RelativeDateTimeFormatter().localizedString(for: checked, relativeTo: Date())
        return "Version \(updater.currentVersion) · checked \(ago)"
    }

    /// The release notes' Markdown, shown with its bold and code; lines stay lines.
    private func notes(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.bottom, -6)
    }
}

// MARK: - Hero

/// The current wallpaper, playing live, with glass controls floating over it.
private struct HeroCard: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var library: LibraryStore
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            if let video = app.previewVideo {
                Color.black
                if let image = library.thumbnail(for: video) {
                    Color.clear.overlay {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    }
                }
                PlayerPreview(player: app.previewPlayer)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.55),
                        .init(color: .black.opacity(0.72), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
                overlay(for: video)
            } else {
                EmptyHero(onAdd: onAdd)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 212)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .contextMenu {
            if let video = app.previewVideo { VideoMenu(video: video, target: nil) }
        }
    }

    private func overlay(for video: VideoItem) -> some View {
        VStack(alignment: .leading) {
            GlassGroup(spacing: 10) {
                HStack(alignment: .center) {
                    StatusPill()
                    Spacer()
                    PlayPauseButton()
                }
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(video.detailText)
                        .font(.caption.weight(.medium))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6)
                Spacer()
                if app.isOnLockScreen(video) {
                    Label("Lock Screen", systemImage: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .liquidGlass(in: Capsule())
                }
            }
        }
        .padding(12)
    }
}

private struct StatusPill: View {
    @EnvironmentObject private var app: AppController

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(app.status.isPlaying ? Color.green : Color.orange)
                .symbolEffect(.pulse, options: .repeating, isActive: app.status.isPlaying)
            Text(app.status.text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .liquidGlass(in: Capsule())
        .animation(.smooth, value: app.status)
    }
}

private struct PlayPauseButton: View {
    @EnvironmentObject private var app: AppController

    var body: some View {
        Button {
            app.isPausedByUser.toggle()
        } label: {
            Image(systemName: app.isPausedByUser ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 22, height: 22)
                .contentTransition(.symbolEffect(.replace))
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .help(app.isPausedByUser ? "Resume" : "Pause")
    }
}

private struct EmptyHero: View {
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.45), Color.purple.opacity(0.35), Color.pink.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 36, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                Text("Bring your desktop to life").font(.headline)
                Text("Drop a video here, or add one from your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onAdd) {
                    Label("Add Video", systemImage: "plus")
                        .padding(.horizontal, 6)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Displays

private struct DisplayChips: View {
    @EnvironmentObject private var app: AppController

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                chip("All Displays", symbol: "display.2", id: nil)
                ForEach(app.displays) { display in
                    chip(display.name, symbol: "display", id: display.id)
                }
            }
        }
    }

    private func chip(_ title: String, symbol: String, id: CGDirectDisplayID?) -> some View {
        Button {
            withAnimation(spring) { app.targetDisplayID = id }
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .glassButton(prominent: app.targetDisplayID == id)
        .controlSize(.small)
    }
}

// MARK: - Library

private struct LibrarySection: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var library: LibraryStore
    let onAdd: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var target: DisplayInfo? {
        app.displays.first { $0.id == app.targetDisplayID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Library").font(.headline)
                Text("\(library.items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus").font(.caption.weight(.semibold))
                }
                .glassButton()
                .controlSize(.small)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(library.jobs) { job in ImportTile(job: job) }
                    ForEach(library.items) { video in
                        VideoTile(video: video, target: target)
                    }
                }
                .padding(5)
            }
            .scrollIndicators(.never)
            .frame(height: gridHeight)
            .padding(-5)
        }
    }

    /// Grows with the library up to two rows, then scrolls.
    private var gridHeight: CGFloat {
        let count = library.items.count + library.jobs.count
        let rows = CGFloat(min(2, max(1, (count + 2) / 3)))
        return rows * tileHeight + (rows - 1) * 10 + 10
    }
}

private struct VideoTile: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var library: LibraryStore
    let video: VideoItem
    let target: DisplayInfo?

    private var isHovered: Bool { app.hoveredVideoID == video.id }
    private var isActive: Bool { app.isShowing(video, on: target) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let image = library.thumbnail(for: video) {
                Color.clear.overlay {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(isHovered ? 0.75 : 0.6)], startPoint: .center, endPoint: .bottom)
            Text(video.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.bottom, 5)
        }
        .frame(height: tileHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isActive ? Color.accentColor : Color.white.opacity(isHovered ? 0.4 : 0.1),
                    lineWidth: isActive ? 2.5 : 1))
        .overlay(alignment: .topTrailing) { badges }
        .scaleEffect(isHovered ? 1.045 : 1)
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 10 : 4, y: isHovered ? 6 : 2)
        .zIndex(isHovered ? 1 : 0)
        .animation(spring, value: isHovered)
        .animation(spring, value: isActive)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                app.hoveredVideoID = video.id
            } else if app.hoveredVideoID == video.id {
                app.hoveredVideoID = nil
            }
        }
        .onTapGesture { app.setWallpaper(video, on: target) }
        .contextMenu { VideoMenu(video: video, target: target) }
        .help("\(video.name)\n\(video.detailText)")
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if app.isOnLockScreen(video) {
                badge("lock.fill", color: .purple)
            }
            if isActive {
                badge("checkmark", color: .accentColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(6)
    }

    private func badge(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color.gradient, in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

private struct ImportTile: View {
    @EnvironmentObject private var library: LibraryStore
    let job: ImportJob

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 7) {
                if job.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                } else if let progress = job.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(job.error == nil ? "Optimizing…" : "Couldn't add")
                    .font(.caption2.weight(.medium))
                Text(job.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4])))

            if job.error != nil {
                Button { library.dismiss(job) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .help(job.error ?? "Converting to an efficient HEVC wallpaper…")
    }
}

private struct VideoMenu: View {
    @EnvironmentObject private var app: AppController
    let video: VideoItem
    let target: DisplayInfo?

    var body: some View {
        Button(target.map { "Set on \($0.name)" } ?? "Set on All Displays") {
            app.setWallpaper(video, on: target)
        }
        Button("Use on Lock Screen") { app.useOnLockScreen(video) }
        Divider()
        Button("Rename…") { app.rename(video) }
        Button("Show in Finder") { app.revealInFinder(video) }
        Divider()
        Button("Remove from Library", role: .destructive) { app.remove(video) }
    }
}

// MARK: - Lock screen

private struct LockScreenRow: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lockScreen: LockScreenManager

    var body: some View {
        Card {
            SettingRow(
                symbol: "lock.fill", color: .purple,
                title: "Lock Screen",
                subtitle: subtitle,
                subtitleColor: isFailed ? .red : .secondary
            ) {
                HStack(spacing: 8) {
                    if lockScreen.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        if showsUpdate {
                            Button("Update") { app.useCurrentOnLockScreen() }
                                .glassButton(prominent: true)
                                .controlSize(.small)
                        }
                        RowSwitch(isOn: Binding(get: { app.isLockScreenOn }, set: app.setLockScreen))
                            .disabled(app.previewVideo == nil && !app.isLockScreenOn)
                    }
                }
            }
        }
        .animation(.smooth, value: lockScreen.state)
    }

    /// Offered only when the lock screen doesn't follow the wallpaper on its own.
    private var showsUpdate: Bool {
        guard app.isLockScreenOn, !settings.lockScreenFollowsWallpaper, let current = app.previewVideo else { return false }
        return !app.isOnLockScreen(current)
    }

    private var isFailed: Bool {
        if case .failed = lockScreen.state { return true }
        return false
    }

    private var subtitle: String {
        switch lockScreen.state {
        case .off: return "Show your wallpaper when the Mac is locked"
        case .working(let message): return message
        case .on(let name): return "Showing “\(name)”"
        case .failed(let message): return message
        }
    }
}

// MARK: - Footer & drop

private struct Footer: View {
    @EnvironmentObject private var app: AppController
    @EnvironmentObject private var updater: Updater

    var body: some View {
        HStack(spacing: 8) {
            Button { NSWorkspace.shared.open(Paths.videos) } label: {
                Label("Videos", systemImage: "folder")
            }
            Button {
                withAnimation(spring) { app.page = app.page == .settings ? .library : .settings }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .glassButton(prominent: app.page == .settings)
            // A dot, like System Settings' badge, when a new version is out.
            .overlay(alignment: .topTrailing) {
                if updater.availableRelease != nil {
                    Circle().fill(.red).frame(width: 8, height: 8).offset(x: 2, y: -2)
                }
            }
            .help(updater.availableRelease.map { "LiveWall \($0.version.description) is available" } ?? "Settings")
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .font(.caption.weight(.medium))
        .glassButton()
        .controlSize(.small)
    }
}

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
            Label("Drop to add to LiveWall", systemImage: "square.and.arrow.down.on.square")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .liquidGlass(in: Capsule())
        }
        .padding(6)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
