import Foundation

/// A video in the library, already converted to a wallpaper-ready file.
struct VideoItem: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var fileName: String
    var duration: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var frameRate: Double
    var addedAt: Date

    var fileURL: URL { Paths.videos.appendingPathComponent(fileName) }
    var thumbnailURL: URL { Paths.thumbnails.appendingPathComponent("\(id.uuidString).jpg") }

    var detailText: String {
        let shortSide = min(pixelWidth, pixelHeight)
        let resolution = shortSide >= 2000 ? "4K" : "\(shortSide)p"
        return "\(resolution) · \(Int(frameRate.rounded())) fps · \(Self.format(duration))"
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60)m \(total % 60)s" : "\(total)s"
    }
}
