# Changelog

All notable changes to LiveWall are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-01

### Added
- Software Update in Settings: a once-a-day check for new versions on GitHub (can be turned off), release notes, and Update Now, which verifies the download, replaces LiveWall and reopens it. A dot on Settings shows when an update is out.
- `livewall://update` and `livewall://update/install` links.
- One-command install from the README.

### Fixed
- Release builds run on Intel Macs too (universal binary).
- The release zip is always named `LiveWall.zip`, so `releases/latest/download/LiveWall.zip` works, and it no longer carries `._` files that broke the app's signature when unzipped with `unzip` and other tools.

## [1.0.0] - 2026-10-21

### Added
- Live video wallpapers on every display and Space, with per-display choices.
- Import of any video, optimized to HEVC with no audio; lossless remux for HEVC sources; `ffmpeg` fallback for WebM, MKV and GIF.
- Automatic pausing when covered, locked, asleep, in Low Power Mode, overheating or (optionally) on battery.
- Lock screen and screen saver support through a custom Aerial, with automatic repair, backups and restore.
- Lock screen that follows the desktop wallpaper.
- Liquid Glass menu bar panel with a live preview, library grid, drag and drop, and a Settings page.
- `livewall://` links for automation, and Open at Login.
