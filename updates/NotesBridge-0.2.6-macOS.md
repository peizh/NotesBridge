<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
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
