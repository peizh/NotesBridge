# Changelog

All notable user-visible changes to NotesBridge should be documented here.

This file is the source of truth for GitHub Release notes and Sparkle update notes.

## [0.2.3] - 2026-03-23

### Fixed

- Fixed Apple Notes code blocks where the first character could render outside the Markdown code fence after sync.
- Fixed fragmented `mailto:` links and adjacent strikethrough text in synced note bodies.

### Distribution

- Direct-download build.
- Ad-hoc signed.
- Not notarized yet.

## [0.2.2] - 2026-03-23

### Added

- Added Sparkle-based in-app updates for direct-download builds, including version display, manual update checks, and automatic update preferences in Settings.

### Changed

- Grouped build and update controls into a single Version section in Settings.
- Updated the direct-download packaging and release workflow to publish a signed Sparkle appcast and Markdown release notes via GitHub Pages.

### Distribution

- Direct-download build.
- Ad-hoc signed.
- Not notarized yet.

## [0.2.1] - 2026-03-20

### Added

- Added inline toolbar customization in Settings, including per-tool visibility toggles and drag-handle reordering.
- Added strikethrough as a configurable inline formatting action.

### Changed

- Made the inline toolbar popup more compact for a tighter editing experience.

## [0.2.0] - 2026-03-17

### Added

- Added app UI localization support with `System`, `English`, `简体中文`, and `Français` language options.
- Localized the settings window, menu bar popover, sync progress text, and slash command menu titles.

### Changed

- Stabilized slash command interactions and followed up on recent review fixes for localization and slash UI behavior.

## [0.1.0] - 2026-03-13

### Added

- Shipped the first direct-download macOS preview release.
- Added install notes for downloading, unzipping, moving `NotesBridge.app` into `/Applications`, and granting the required macOS permissions.

### Distribution

- Direct-download build.
- Ad-hoc signed.
- Not notarized yet.
