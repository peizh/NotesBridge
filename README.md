# NotesBridge

[![CI](https://img.shields.io/github/actions/workflow/status/peizh/NoteBridge/ci.yml?branch=master&label=CI)](https://github.com/peizh/NoteBridge/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/peizh/NoteBridge?style=social)](https://github.com/peizh/NoteBridge/network/members)

NotesBridge is a native macOS companion for Apple Notes. It runs as a menu bar app, adds inline editing enhancements on top of Apple Notes, and exports notes into an Obsidian vault.

## What this prototype does

- Runs as a menu bar companion with a lightweight settings window.
- Watches Apple Notes when it is frontmost and the editor is focused.
- Shows a floating formatting bar above selected text in supported builds.
- Converts line-start markdown/list triggers into native Apple Notes formatting commands.
- Supports slash commands with inline exact-match execution and a floating suggestions menu.
- Syncs Apple Notes into an Obsidian vault with front matter metadata and native attachment export.

## Product constraints

Apple Notes does not expose a public plugin or extension API. NotesBridge therefore behaves as a companion app rather than a true in-app Notes extension.

The current implementation is intentionally conservative:

- Inline enhancements rely on Accessibility and event synthesis, so the direct-download build is the primary vehicle for the full experience.
- The App Store flavor can be simulated by launching with `NOTESBRIDGE_APPSTORE=1`, which disables inline Apple Notes enhancements and leaves settings/sync features active.
- Apple Notes -> Obsidian is still the primary sync direction.
- Slash command keyboard navigation may require Input Monitoring; if interception is unavailable, exact commands plus space and mouse-click selection still work.
- Full-note sync prompts for the macOS `group.com.apple.notes` data folder so NotesBridge can read the Apple Notes database and attachment files directly.

## Build and run

```bash
./scripts/run-bundled-app.sh
```

This is the recommended development entrypoint. It builds the SwiftPM executable, wraps it into a signed `NotesBridge.app`, and launches the bundled app from `~/Library/Application Support/NotesBridge/NotesBridge.app`.

The bundled app now uses a stable designated requirement so Accessibility and Input Monitoring can stay attached across rebuilds. If you previously granted an older NotesBridge build and the app still shows `Required`, remove the old entry in System Settings once and add the current bundled app again.

For quick non-bundled runs you can still use:

```bash
swift run
```

But `swift run` launches a bare executable, so macOS permission flows that depend on a real app bundle, especially Input Monitoring for slash menu keyboard navigation, will not behave correctly there.

If you only want to rebuild the `.app` without launching it:

```bash
./scripts/run-bundled-app.sh --build-only
```

On first bundled launch, macOS may ask for Accessibility and Automation permissions so NotesBridge can watch Apple Notes and sync its content. The first full sync also asks you to choose `~/Library/Group Containers/group.com.apple.notes` so the app can read NoteStore.sqlite and binary attachments.

## Suggested next steps

1. Harden selection anchoring and formatting-bar placement across multiple displays and fullscreen spaces.
2. Add a richer sync index and incremental note change tracking.
3. Package separate direct-download and App Store deliverables from the same codebase.
