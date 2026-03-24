# Changelog

All notable user-visible changes to NotesBridge should be documented here.

This file is the source of truth for GitHub Release notes and Sparkle update notes.

## [0.2.6] - 2026-03-24

### Added

- Added an `App Management` section in Settings > Permissions so direct-download users can open the system permission panel before automatic app replacement updates run.

### Changed

- Unified local build, run, release, notarization, appcast, and changelog extraction workflows behind `./scripts/notesbridge.sh`.
- Aligned bundled-app version metadata with the repository version source so local builds no longer report stale release numbers.

### Distribution

- Direct-download build.
- Ad-hoc signed.
- Not notarized yet.

## [0.2.5] - 2026-03-24

### Fixed

- Fixed the direct-download update pipeline by rotating the Sparkle signing key and restoring GitHub Pages appcast publishing.
- Fixed release automation so Sparkle framework lookup and release-note extraction succeed on clean CI runners.

### Important

- NotesBridge `0.2.2` to `0.2.4` were built with the previous Sparkle public key and cannot automatically upgrade to this release.
- Users on those versions need to manually install `0.2.5` once. After that, in-app updates can work again.

### Distribution

- Direct-download build.
- Ad-hoc signed.
- Not notarized yet.

## [0.2.4] - 2026-03-24

### Added

- Added incremental sync controls in Settings, with manual `Sync Changed Notes`, explicit `Run Full Sync`, and automatic sync intervals for 30 minutes, 1 hour, 6 hours, or daily.
- Added a `_Removed` flow for source notes deleted from Apple Notes, so synced exports are moved aside instead of being hard-deleted.

### Fixed

- Fixed incremental sync repeatedly falling back to full sync because Apple Notes cloud-placeholder records without local body data were being treated as changed notes.
- Fixed incremental sync status reporting to distinguish processed, added, updated, and unchanged notes more accurately.
- Fixed sync change counts so `updated` reflects real file changes instead of housekeeping-only attachment directory cleanup.
- Improved fallback messaging when incremental sync must switch to a full sync, so the reason is explicit.

### Distribution

- Direct-download build.
- Ad-hoc signed.
- Not notarized yet.

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
