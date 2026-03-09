# NotesBridge

NotesBridge is a native macOS companion for Apple Notes. It runs as a menu bar app, adds inline editing enhancements on top of Apple Notes, and exports notes into an Obsidian vault.

## What this prototype does

- Runs as a menu bar companion with a lightweight settings window.
- Watches Apple Notes when it is frontmost and the editor is focused.
- Shows a floating formatting bar above selected text in supported builds.
- Converts line-start markdown/list triggers into native Apple Notes formatting commands.
- Supports slash commands with inline exact-match execution and a floating suggestions menu.
- Syncs Apple Notes into an Obsidian vault with front matter metadata.

## Product constraints

Apple Notes does not expose a public plugin or extension API. NotesBridge therefore behaves as a companion app rather than a true in-app Notes extension.

The current implementation is intentionally conservative:

- Inline enhancements rely on Accessibility and event synthesis, so the direct-download build is the primary vehicle for the full experience.
- The App Store flavor can be simulated by launching with `NOTESBRIDGE_APPSTORE=1`, which disables inline Apple Notes enhancements and leaves settings/sync features active.
- Apple Notes -> Obsidian is still the primary sync direction.
- Slash command keyboard navigation may require Input Monitoring; if interception is unavailable, exact commands plus space and mouse-click selection still work.

## Build and run

```bash
swift build
swift run
```

On first launch, macOS may ask for Accessibility and Automation permissions so NotesBridge can watch Apple Notes and sync its content.

## Suggested next steps

1. Harden selection anchoring and formatting-bar placement across multiple displays and fullscreen spaces.
2. Add a richer sync index and incremental note change tracking.
3. Package separate direct-download and App Store deliverables from the same codebase.
