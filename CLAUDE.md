@AGENTS.md

## Claude Code notes

- Build with `swift build -c release` and check the result yourself; SourceKit's "Cannot find … in scope" diagnostics on single files are expected noise, so trust the compiler.
- Terminal usually lacks Screen Recording permission, so `screencapture` fails. Ask the user for a screenshot to check the UI, and use the logs and `livewall://` links to check behavior.
- Lock screen changes alter the user's real system settings. Say what you're about to change, and run an on/off cycle when testing so their setup ends where it started.
