import Foundation

/// A version like "1.2.0", or a tag like "v1.2.0", compared number by number, so 1.10 comes
/// after 1.9 and 1.2 is the same as 1.2.0.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]
    public let description: String

    public init?(_ text: String) {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.first == "v" || string.first == "V" { string.removeFirst() }
        // A pre-release suffix ("1.3.0-beta") isn't compared: those releases aren't offered.
        let numbers = (string.split(separator: "-", maxSplits: 1).first ?? "").split(separator: ".", omittingEmptySubsequences: false)
        let parsed = numbers.map { Int($0) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        var parts = parsed.map { $0! }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        self.parts = parts
        description = string
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.parts == rhs.parts }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

/// A release on GitHub that LiveWall can update to.
public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    public let title: String
    /// What's new, from the release notes, without the install instructions.
    public let notes: String
    public let page: URL
    public let archive: URL
    public let checksum: URL?
    public let size: Int
}

/// Reads GitHub's answer for a repository's latest release.
public enum ReleaseFeed {
    /// The app's zip, attached to every release under exactly this name.
    public static let archiveName = "LiveWall.zip"

    /// The release in a `releases/latest` answer, if it's a published version with the app's zip.
    public static func release(from json: Data) -> AppRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              let tag = object["tag_name"] as? String, let version = AppVersion(tag),
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = object["assets"] as? [[String: Any]]
        else { return nil }
        func asset(_ name: String) -> (url: URL, size: Int)? {
            guard let asset = assets.first(where: { $0["name"] as? String == name }),
                  let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)),
                  url.scheme == "https"
            else { return nil }
            return (url, asset["size"] as? Int ?? 0)
        }
        guard let archive = asset(archiveName) else { return nil }
        let title = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "LiveWall \(version)"
        return AppRelease(version: version, title: title, notes: summary(of: object["body"] as? String ?? ""),
                          page: page, archive: archive.url, checksum: asset(archiveName + ".sha256")?.url, size: archive.size)
    }

    /// Whether the release is newer than the version running now.
    public static func isUpdate(_ release: AppRelease, over current: String) -> Bool {
        guard let current = AppVersion(current) else { return true }
        return release.version > current
    }

    /// The SHA-256 in a `shasum -a 256` line for the archive, lowercased.
    public static func checksum(in text: String, for name: String = archiveName) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name else { continue }
            let hash = fields[0].lowercased()
            if hash.count == 64, hash.allSatisfy(\.isHexDigit) { return hash }
        }
        return nil
    }

    /// The notes worth showing in Settings: the release's own heading and everything from its
    /// install instructions on are left out.
    static func summary(of body: String) -> String {
        var lines: [Substring] = []
        // GitHub keeps notes with \r\n, which Swift counts as one character: split on any newline.
        for line in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**Install**") || trimmed.lowercased().hasPrefix("## install") { break }
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
