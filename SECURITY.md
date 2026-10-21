# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Instead, use GitHub's private vulnerability reporting: **Security › Report a vulnerability** on the repository page.

Include what you found, how to reproduce it, and its impact. You'll get a reply within a few days.

## Scope

LiveWall makes no network connections and runs without elevated privileges. The most sensitive areas are:

- the lock screen code, which edits macOS wallpaper files in `~/Library/Application Support/com.apple.wallpaper`;
- the `livewall://` URL handler, which any app or web page can trigger;
- the import pipeline, which parses user-supplied video files and may call `ffmpeg`.
