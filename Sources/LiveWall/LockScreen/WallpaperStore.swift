import Foundation

/// Edits the macOS wallpaper choice store (Store/Index.plist).
///
/// The `AllSpacesAndDisplays` entry overrides every Space and display. Its `Idle` slot is
/// the screen saver and lock screen; its `Desktop` slot is the wallpaper that animates on
/// the lock screen. LiveWall saves the entry it replaces and puts it back on restore.
enum WallpaperStore {
    private static let allDisplaysKey = "AllSpacesAndDisplays"
    private static let aerialsProvider = "com.apple.wallpaper.choice.aerials"
    private static let savedChoiceURL = Paths.backups.appendingPathComponent("previous-AllSpacesAndDisplays.plist")

    static var exists: Bool { FileManager.default.fileExists(atPath: Paths.wallpaperStore.path) }

    static func select(assetID: String, animateOnLockScreen: Bool, ownedAssetIDs: Set<String>) throws {
        var (root, format) = try read()
        let current = root[allDisplaysKey]
        let isOurs = !assetIDs(in: current).isDisjoint(with: ownedAssetIDs.union([assetID]))
        if !isOurs {
            try saveChoice(current)
        }

        let now = Date()
        let idleOptions = try encode(["values": [String: Any]()])
        var choice: [String: Any] = ["Idle": try slot(assetID: assetID, options: idleOptions, now: now)]
        if animateOnLockScreen {
            choice["Type"] = "individual"
            choice["Desktop"] = try slot(assetID: assetID, options: "$null", now: now)
        } else {
            choice["Type"] = "idle"
        }
        root[allDisplaysKey] = choice
        try write(root, format: format)
    }

    static func selects(_ assetID: String) -> Bool {
        guard let (root, _) = try? read() else { return false }
        return assetIDs(in: root[allDisplaysKey]).contains(assetID)
    }

    /// Puts back the choice LiveWall replaced, but only while LiveWall's choice is still active;
    /// if the user has picked something else since, that choice is left alone.
    static func restore(ownedAssetIDs: Set<String>) throws {
        defer { try? FileManager.default.removeItem(at: savedChoiceURL) }
        var (root, format) = try read()
        guard !assetIDs(in: root[allDisplaysKey]).isDisjoint(with: ownedAssetIDs) else { return }
        if let saved = loadSavedChoice() {
            root[allDisplaysKey] = saved
        } else {
            root.removeValue(forKey: allDisplaysKey)
        }
        try write(root, format: format)
    }

    // MARK: - Helpers

    private static func slot(assetID: String, options: Any, now: Date) throws -> [String: Any] {
        let choice: [String: Any] = [
            "Provider": aerialsProvider,
            "Files": [Any](),
            "Configuration": try encode(["assetID": assetID]),
        ]
        return [
            "LastSet": now,
            "LastUse": now,
            "Content": [
                "Choices": [choice],
                "Shuffle": "$null",
                "EncodedOptionValues": options,
            ] as [String: Any],
        ]
    }

    /// Every `assetID` referenced by a store entry, including inside embedded binary plists.
    private static func assetIDs(in value: Any?) -> Set<String> {
        switch value {
        case let dictionary as [String: Any]:
            var ids = Set<String>()
            if let id = dictionary["assetID"] as? String { ids.insert(id) }
            for nested in dictionary.values { ids.formUnion(assetIDs(in: nested)) }
            return ids
        case let array as [Any]:
            return array.reduce(into: Set<String>()) { $0.formUnion(assetIDs(in: $1)) }
        case let data as Data:
            guard data.starts(with: Array("bplist".utf8)),
                  let nested = try? PropertyListSerialization.propertyList(from: data, format: nil)
            else { return [] }
            return assetIDs(in: nested)
        default:
            return []
        }
    }

    private static func encode(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private static func read() throws -> ([String: Any], PropertyListSerialization.PropertyListFormat) {
        let data = try Data(contentsOf: Paths.wallpaperStore)
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (root, format)
    }

    private static func write(_ root: [String: Any], format: PropertyListSerialization.PropertyListFormat) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
        try data.write(to: Paths.wallpaperStore, options: .atomic)
    }

    private static func saveChoice(_ choice: Any?) throws {
        let record: [String: Any] = choice.map { ["value": $0] } ?? [:]
        try encode(record).write(to: savedChoiceURL, options: .atomic)
    }

    private static func loadSavedChoice() -> Any? {
        guard let data = try? Data(contentsOf: savedChoiceURL),
              let record = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return record["value"]
    }
}
