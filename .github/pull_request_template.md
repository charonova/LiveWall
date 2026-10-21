## What this changes

## Why

## How I tested it
- [ ] `swift build -c release` passes without new warnings
- [ ] Playback, sleep/wake and pausing when covered still work
- [ ] CPU usage is unchanged (`top -l 6 -s 2 -pid $(pgrep -x LiveWall) -stats pid,cpu`)
- [ ] Lock screen on/off leaves the macOS wallpaper files as they were (if touched)
- [ ] Checked in light and dark mode (if the UI changed)

## Screenshots
<!-- For UI changes -->
