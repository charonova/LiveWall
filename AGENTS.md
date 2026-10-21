# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, …) working on LiveWall. Humans: see [CONTRIBUTING.md](CONTRIBUTING.md).

## What this is

LiveWall is a macOS menu bar app (Swift, SwiftUI + AppKit, no dependencies) that plays videos as the desktop wallpaper on every display and Space, and on the lock screen. Its two core promises are **smoothness** and **near-zero power use**; every change is judged against both.

## Build, run, verify

```bash
swift build -c release            # compile
./scripts/build.sh                # → build/LiveWall.app (ad-hoc signed)
open build/LiveWall.app           # run
./scripts/install.sh              # build + install to ~/Applications + launch
./scripts/make-icon.sh            # regenerate Resources/AppIcon.icns and docs/icon.png
```

To restart a running copy: `osascript -e 'tell application id "com.aissam.livewall" to quit'; open build/LiveWall.app`.

There are no automated tests. Verify behavior with:

- **Logs** (the app logs status and lock screen state changes):
  `/usr/bin/log show --last 5m --predicate 'subsystem == "com.aissam.livewall"'`
  Use the full path: in zsh, `log` is a shell builtin.
- **Control without the UI:** `open "livewall://pause"`, `play`, `toggle`, `lockscreen/<video-uuid>`, `lockscreen/off`.
- **Import without the UI:** `open -a build/LiveWall.app /path/to/video.mp4`
- **CPU:** `top -l 6 -s 2 -pid $(pgrep -x LiveWall) -stats pid,cpu` (`ps %cpu` is a decaying average and misleads).
- **Library state:** `~/Library/Application Support/LiveWall/library.json`

## Hard constraints

- **Never use SwiftUI `@State` or `@Entry`.** In current SDKs they're macros whose plugin ships only with Xcode, so they break the Command Line Tools build. Put view state in `AppController` (`@Published`) and read it through `@EnvironmentObject`. `@Namespace`, `@Published`, `@EnvironmentObject` and `@Observable` are fine.
- **macOS 14 deployment target.** Guard newer APIs with `#available(macOS 26, *)`; `UI/Glass.swift` has the Liquid Glass wrappers with material fallbacks.
- **No third-party dependencies.**
- Swift 5 language mode (`swift-tools-version:5.10`). UI-facing classes are `@MainActor`; file and conversion work runs off the main actor.

## Performance rules

- Imported videos are HEVC, ≤ 4K, `.mov`, **no audio track** (`Library/VideoImporter.swift`). Keep that invariant: playback must never decode audio.
- One `LoopingPlayer` per video, shared by every display and the panel preview (`Playback/WallpaperEngine.swift`). Never create a second player for a video that's already loaded.
- Anything that renders must pause when the wallpaper is hidden. Pause decisions flow through `AppController.updatePlayback()` → `WallpaperEngine.updatePlayback(...)`, fed by `PlaybackConditions` and window occlusion.
- Prefer system notifications to timers. The only timer is the 15-minute lock screen repair check.
- `player.preventsDisplaySleepDuringVideoPlayback` stays `false`.

## UI rules

- The menu bar panel has a **fixed size** while open (`MenuPanel.panelHeight`). A `MenuBarExtra` window that shrinks keeps its bottom edge and leaves a gap under the menu bar, so never let content change the panel's height; switch pages (`PanelPage`) or scroll instead.
- `ForEach` identities must be unique across a grid: import jobs and videos use different IDs on purpose.
- Glass belongs on controls floating over content (hero overlay, buttons); grouped settings use `Card`, not glass on glass.

## Lock screen safety (read before touching `LockScreen/`)

LiveWall edits two files that belong to macOS:

| File | Code | What LiveWall changes |
|---|---|---|
| `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` | `AerialsManifest` | Adds/removes only assets and categories in its own category (`AerialsManifest.categoryID`) |
| `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` | `WallpaperStore` | Replaces only the `AllSpacesAndDisplays` entry (`Idle` = screen saver/lock, `Desktop` = animated lock screen) |

Rules:
1. Never modify entries that aren't LiveWall's.
2. Back up before writing (`LockScreenFiles.backUp`) and keep the restore path (`WallpaperStore.restore`) working: turning the lock screen off must leave both files as they were.
3. After writing, restart `WallpaperAgent` and `WallpaperAerialsExtension` (`WallpaperService.restart`) and verify the choice stuck.
4. Lock screen videos are hard links to library files, named `<VIDEO-UUID>.mov` in `aerials/videos`.

To test, compare `AllSpacesAndDisplays` and the LiveWall entries before and after an on/off cycle (e.g. with Python's `plistlib` and `json`), and check the agent's log:

```bash
/usr/bin/log show --last 2m --predicate 'process == "WallpaperAerialsExtension" OR process == "WallpaperAgent"'
```

## Code map

| Path | Responsibility |
|---|---|
| `App/LiveWallApp.swift` | `@main`, `MenuBarExtra`, `AppDelegate` (file opening, `livewall://` links) |
| `App/AppController.swift` | Central state: wallpaper choice, playback status, panel state, lock screen actions |
| `App/AppSettings.swift` | `UserDefaults`-backed preferences |
| `Playback/WallpaperWindow.swift` | Desktop-level window per display, cross-fading `AVPlayerLayer` |
| `Playback/WallpaperEngine.swift` | Windows ↔ shared players, play/pause decisions |
| `Playback/LoopingPlayer.swift` | `AVQueuePlayer` + `AVPlayerLooper` |
| `Playback/PlaybackConditions.swift` | Sleep, lock, screen saver, power, thermal, battery |
| `Playback/DisplayInfo.swift` | Display identity (stable UUIDs for per-display choices) |
| `Library/` | Library persistence, import queue, conversion |
| `LockScreen/` | Aerials catalog, wallpaper store, install/restore/repair |
| `UI/` | Panel views, glass helpers, shared components, live preview |
| `Support/` | Paths, `ProcessRunner`, login item |
| `demo/` (repo root) | README media; see "Updating the demo media" in CONTRIBUTING.md |

## Style

Match the surrounding code: small focused types, early returns, doc comments that explain *why* rather than restating the code, and user-facing text in sentence case with plain wording. Keep commits focused and describe how a change was verified.
