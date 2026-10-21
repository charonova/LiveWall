# Contributing to LiveWall

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Getting started

```bash
git clone https://github.com/<your-username>/LiveWall.git
cd LiveWall
swift build          # debug build
./scripts/build.sh   # release build → build/LiveWall.app
open build/LiveWall.app
```

Only the Xcode Command Line Tools are required. Xcode works too: `open Package.swift`.

> **Heads-up:** don't use SwiftUI's `@State` (or `@Entry`). In recent SDKs they're macros whose plugin ships only with Xcode, so they break the Command Line Tools build. Keep view state in an `ObservableObject` (see `AppController`). `@EnvironmentObject`, `@Published`, `@Namespace` and `@Observable` are fine.

## Project layout

| Path | What's there |
|---|---|
| `Sources/LiveWall/App` | App entry point, `AppController` (ties everything together), settings |
| `Sources/LiveWall/Playback` | Desktop windows, shared looping players, pause conditions |
| `Sources/LiveWall/Library` | Video library and the import/conversion pipeline |
| `Sources/LiveWall/LockScreen` | Aerials catalog and wallpaper store editing |
| `Sources/LiveWall/UI` | The menu bar panel (SwiftUI) |
| `Sources/LiveWall/Support` | Paths, process runner, login item |
| `scripts/` | Build, install and icon generation |

## Guidelines

- **Performance is a feature.** Don't decode audio, don't add a second player for a video that's already playing, don't poll when a notification exists, and make sure anything new pauses when the wallpaper isn't visible.
- **Be careful with macOS's files.** The lock screen code edits files owned by macOS. Only touch entries in LiveWall's own category, back up before writing, and keep the restore path working.
- **No dependencies.** LiveWall uses only Apple frameworks.
- **Match the surrounding code:** small focused types, `@MainActor` for UI-facing classes, and comments that explain *why*.
- Keep pull requests focused, and describe how you tested them.

## Testing your change

There's no automated UI test suite yet, so please check by hand:

- [ ] `swift build -c release` passes without new warnings
- [ ] Playback starts, loops smoothly and survives sleep/wake
- [ ] It pauses when covered by a full-screen app and resumes after
- [ ] CPU stays low: `top -l 6 -s 2 -pid $(pgrep -x LiveWall) -stats pid,cpu`
- [ ] If you touched the lock screen: turning it on and off leaves `~/Library/Application Support/com.apple.wallpaper` as it was
- [ ] Light and dark mode both look right

Logs: `/usr/bin/log stream --predicate 'subsystem == "com.aissam.livewall"'`

## Regenerating the icon

The icon is drawn in code. Edit `scripts/make-icon.swift`, then run `./scripts/make-icon.sh`.

## Updating the demo media

The README uses the files in `demo/`. From a new screen recording (`recording.mov`):

```bash
# Full-quality video: 1080p, 30 fps, no audio
ffmpeg -i recording.mov -an -vf "fps=30,scale=1920:-2:flags=lanczos" \
  -c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p -movflags +faststart demo/demo.mp4

# README GIF: a short highlight, kept under ~10 MB
ffmpeg -ss 1.5 -t 11.5 -i demo/demo.mp4 -vf "fps=12,scale=800:-1:flags=lanczos,split[a][b];\
[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 demo/demo.gif
```

Panel close-ups (`panel-*.jpg`) are crops of single frames from the recording.

## Releases

1. Update `CHANGELOG.md` and the version in `Resources/Info.plist`.
2. Tag the commit (`git tag v1.1.0 && git push --tags`).
3. The **Build** workflow attaches a zipped `LiveWall.app` to the run; add it to the GitHub release.
