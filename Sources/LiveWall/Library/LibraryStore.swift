import AppKit
import Foundation

struct ImportJob: Identifiable, Equatable {
    /// Distinct from `videoID` so a finished video never inherits its job's view in the grid.
    let id = UUID()
    let videoID: UUID
    let name: String
    var progress: Double?  // nil while the progress is unknown
    var error: String?
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [VideoItem] = []
    @Published private(set) var jobs: [ImportJob] = []

    var onImported: ((VideoItem) -> Void)?

    private var thumbnailCache: [UUID: NSImage] = [:]
    private var queue: [(url: URL, job: ImportJob)] = []
    private var worker: Task<Void, Never>?

    func load() {
        guard let data = try? Data(contentsOf: Paths.libraryFile),
              let decoded = try? Self.decoder.decode([VideoItem].self, from: data)
        else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        renameGeneratedNames()
    }

    func item(_ id: UUID?) -> VideoItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    func thumbnail(for item: VideoItem) -> NSImage? {
        if let cached = thumbnailCache[item.id] { return cached }
        let image = NSImage(contentsOf: item.thumbnailURL)
        thumbnailCache[item.id] = image
        return image
    }

    /// Queues videos for conversion. They're converted one at a time so the
    /// hardware encoder isn't shared and the Mac stays responsive.
    func importVideos(_ urls: [URL]) {
        for url in urls {
            let job = ImportJob(videoID: UUID(), name: displayName(for: url), progress: 0)
            jobs.append(job)
            queue.append((url, job))
        }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                await self.runImport(next.url, job: next.job)
            }
            self?.worker = nil
        }
    }

    func dismiss(_ job: ImportJob) {
        jobs.removeAll { $0.id == job.id }
    }

    func rename(_ item: VideoItem, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].name = name
        save()
    }

    func remove(_ item: VideoItem) {
        try? FileManager.default.removeItem(at: item.fileURL)
        try? FileManager.default.removeItem(at: item.thumbnailURL)
        thumbnailCache[item.id] = nil
        items.removeAll { $0.id == item.id }
        save()
    }

    private func runImport(_ url: URL, job: ImportJob) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let item = try await VideoImporter.makeWallpaper(from: url, id: job.videoID, name: job.name) { [weak self] value in
                Task { @MainActor in self?.updateJob(job.id) { $0.progress = value } }
            }
            items.insert(item, at: 0)
            save()
            jobs.removeAll { $0.id == job.id }
            onImported?(item)
        } catch {
            updateJob(job.id) {
                $0.progress = nil
                $0.error = error.localizedDescription
            }
        }
    }

    /// "3 videos · 106 MB"
    var storageSummary: String {
        let bytes = items.reduce(Int64(0)) { total, item in
            let size = (try? item.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
        let count = items.count == 1 ? "1 video" : "\(items.count) videos"
        return "\(count) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    // MARK: - Names

    /// Downloaded files are often named with random IDs; those get "Wallpaper 3" instead.
    private func displayName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return Self.looksGenerated(base) ? nextGenericName() : base
    }

    private func renameGeneratedNames() {
        var changed = false
        for index in items.indices.sorted(by: { items[$0].addedAt < items[$1].addedAt })
        where Self.looksGenerated(items[index].name) {
            items[index].name = nextGenericName()
            changed = true
        }
        if changed { save() }
    }

    private func nextGenericName() -> String {
        let used = Set(items.map(\.name) + jobs.map(\.name))
        var number = 1
        while used.contains("Wallpaper \(number)") { number += 1 }
        return "Wallpaper \(number)"
    }

    /// UUIDs, long hex hashes, and the like.
    private static func looksGenerated(_ name: String) -> Bool {
        name.range(of: "[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}", options: .regularExpression) != nil
            || name.range(of: "[0-9a-fA-F]{16,}", options: .regularExpression) != nil
    }

    private func updateJob(_ id: UUID, _ change: (inout ImportJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func save() {
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: Paths.libraryFile, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
