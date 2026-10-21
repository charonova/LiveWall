import Foundation

/// Edits the macOS Aerials catalog (entries.json) so LiveWall's video is listed as an Aerial.
/// Only entries in LiveWall's own category are ever added or removed.
enum AerialsManifest {
    static let categoryID = "1F5E0A11-1111-4000-8000-000000000001"
    static let subcategoryID = "1F5E0A11-1111-4000-8000-000000000002"

    static var exists: Bool { FileManager.default.fileExists(atPath: Paths.aerialsManifest.path) }

    static func liveWallAssetIDs() throws -> [String] {
        try read().assets.filter(isLiveWall).compactMap { $0["id"] as? String }
    }

    static func install(assetID: String, name: String, video: URL, preview: URL) throws {
        var catalog = try read()
        catalog.assets.removeAll(where: isLiveWall)
        catalog.categories.removeAll { $0["id"] as? String == categoryID }

        let previewImage = preview.absoluteString
        let group: [String: Any] = [
            "localizedNameKey": "LiveWall",
            "localizedDescriptionKey": "Videos from LiveWall",
            "preferredOrder": 0,
            "previewImage": previewImage,
            "representativeAssetID": assetID,
        ]
        var category = group
        category["id"] = categoryID
        var subcategory = group
        subcategory["id"] = subcategoryID
        category["subcategories"] = [subcategory]
        catalog.categories.append(category)

        let shotID = "LIVEWALL_\(assetID.prefix(8))"
        catalog.assets.append([
            "id": assetID,
            "accessibilityLabel": name,
            "localizedNameKey": name,
            "categories": [categoryID],
            "subcategories": [subcategoryID],
            "includeInShuffle": false,
            "showInTopLevel": true,
            "preferredOrder": 0,
            "pointsOfInterest": ["0": shotID],
            "shotID": shotID,
            "previewImage": previewImage,
            "url-4K-SDR-240FPS": video.absoluteString,
        ])
        try write(catalog)
    }

    /// Removes LiveWall's category and assets, returning the removed asset IDs.
    @discardableResult
    static func uninstall() throws -> [String] {
        guard exists else { return [] }
        var catalog = try read()
        let removed = catalog.assets.filter(isLiveWall).compactMap { $0["id"] as? String }
        catalog.assets.removeAll(where: isLiveWall)
        catalog.categories.removeAll { $0["id"] as? String == categoryID }
        try write(catalog)
        return removed
    }

    private struct Catalog {
        var root: [String: Any]
        var assets: [[String: Any]]
        var categories: [[String: Any]]
    }

    private static func isLiveWall(_ asset: [String: Any]) -> Bool {
        (asset["categories"] as? [String])?.contains(categoryID) == true
    }

    private static func read() throws -> Catalog {
        let data = try Data(contentsOf: Paths.aerialsManifest)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Catalog(
            root: root,
            assets: root["assets"] as? [[String: Any]] ?? [],
            categories: root["categories"] as? [[String: Any]] ?? [])
    }

    private static func write(_ catalog: Catalog) throws {
        var root = catalog.root
        root["assets"] = catalog.assets
        root["categories"] = catalog.categories
        let data = try JSONSerialization.data(withJSONObject: root)
        try data.write(to: Paths.aerialsManifest, options: .atomic)
    }
}
