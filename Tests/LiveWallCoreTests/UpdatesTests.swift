import Foundation
import Testing
@testable import LiveWallCore

/// GitHub's `releases/latest` answer, trimmed to the fields LiveWall reads.
private func releaseJSON(tag: String = "v1.3.0", draft: Bool = false, prerelease: Bool = false,
                         assets: [String] = ["LiveWall.zip", "LiveWall.zip.sha256"]) -> Data {
    let list = assets.map { name in
        #"{"name":"\#(name)","size":3456789,"browser_download_url":"https://github.com/charonova/LiveWall/releases/download/\#(tag)/\#(name)"}"#
    }.joined(separator: ",")
    let body = #"## LiveWall 1.3.0\r\n\r\n**New**\r\n- **Something**: it's nice.\r\n\r\n**Install** (macOS 14+):\r\n\r\n```bash\r\ncurl …\r\n```"#
    return Data(#"{"tag_name":"\#(tag)","name":"LiveWall 1.3.0","draft":\#(draft),"prerelease":\#(prerelease),"html_url":"https://github.com/charonova/LiveWall/releases/tag/\#(tag)","body":"\#(body)","assets":[\#(list)]}"#.utf8)
}

@Suite("Software updates")
struct UpdatesTests {
    @Test func comparesVersionsNumberByNumber() {
        #expect(AppVersion("1.10.0")! > AppVersion("1.9.3")!)
        #expect(AppVersion("v1.2.0")! == AppVersion("1.2")!)
        #expect(AppVersion("1.2.1")! > AppVersion("1.2")!)
        #expect(AppVersion("2")! > AppVersion("1.99.99")!)
        #expect(!(AppVersion("1.2.0")! < AppVersion("1.2.0")!))
        #expect(AppVersion("1.3.0-beta")! == AppVersion("1.3.0")!)
        #expect(AppVersion("v1.2.0")!.description == "1.2.0")
    }

    @Test func rejectsWhatIsntAVersion() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("1.-2") == nil)
    }

    @Test func readsTheLatestRelease() throws {
        let release = try #require(ReleaseFeed.release(from: releaseJSON()))
        #expect(release.version == AppVersion("1.3.0")!)
        #expect(release.title == "LiveWall 1.3.0")
        #expect(release.archive.absoluteString == "https://github.com/charonova/LiveWall/releases/download/v1.3.0/LiveWall.zip")
        #expect(release.checksum?.lastPathComponent == "LiveWall.zip.sha256")
        #expect(release.size == 3_456_789)
        #expect(release.page.absoluteString.hasSuffix("/releases/tag/v1.3.0"))
    }

    @Test func keepsOnlyWhatsNewInTheNotes() throws {
        let release = try #require(ReleaseFeed.release(from: releaseJSON()))
        #expect(release.notes.hasPrefix("**New**"))
        #expect(release.notes.contains("Something"))
        #expect(!release.notes.contains("curl"), "the install instructions are left out")
        #expect(!release.notes.contains("## LiveWall"), "and so is the heading")
    }

    @Test func skipsReleasesItCantInstall() {
        #expect(ReleaseFeed.release(from: releaseJSON(draft: true)) == nil)
        #expect(ReleaseFeed.release(from: releaseJSON(prerelease: true)) == nil)
        #expect(ReleaseFeed.release(from: releaseJSON(assets: ["LiveWall.app.zip"])) == nil, "no zip under the expected name")
        #expect(ReleaseFeed.release(from: releaseJSON(tag: "v1.0.0", assets: ["LiveWall-1.0.0.zip"])) == nil,
                "1.0.0's zip had the version in its name")
        #expect(ReleaseFeed.release(from: releaseJSON(tag: "nightly")) == nil)
        #expect(ReleaseFeed.release(from: Data("{\"message\":\"Not Found\"}".utf8)) == nil)
        #expect(ReleaseFeed.release(from: Data("nope".utf8)) == nil)
    }

    @Test func offersOnlyNewerVersions() throws {
        let release = try #require(ReleaseFeed.release(from: releaseJSON()))
        #expect(ReleaseFeed.isUpdate(release, over: "1.2.0"))
        #expect(!ReleaseFeed.isUpdate(release, over: "1.3.0"))
        #expect(!ReleaseFeed.isUpdate(release, over: "1.4"))
    }

    @Test func readsTheChecksumFile() {
        let hash = String(repeating: "ab", count: 32)
        #expect(ReleaseFeed.checksum(in: "\(hash)  LiveWall.zip\n") == hash)
        #expect(ReleaseFeed.checksum(in: "\(hash.uppercased()) *LiveWall.zip") == hash, "binary-mode marker, any case")
        #expect(ReleaseFeed.checksum(in: "\(hash)  Other.zip") == nil)
        #expect(ReleaseFeed.checksum(in: "1234  LiveWall.zip") == nil)
    }
}
