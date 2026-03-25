# NotesBridge

[English](./README.md) | [简体中文](./README.zh-CN.md) | [Français](./README.fr.md)

[![CI](https://img.shields.io/github/actions/workflow/status/peizh/NotesBridge/ci.yml?branch=main&label=CI)](https://github.com/peizh/NotesBridge/actions/workflows/ci.yml)
[![GitHub stars](https://img.shields.io/github/stars/peizh/NotesBridge?style=social)](https://github.com/peizh/NotesBridge/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/peizh/NotesBridge?style=social)](https://github.com/peizh/NotesBridge/network/members)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

![NotesBridge social banner](./images/notesbridge-social.svg)

Website: [peizh.github.io/NotesBridge](https://peizh.github.io/NotesBridge/)

NotesBridge is a native macOS companion for Apple Notes. It runs as a menu bar app, adds inline editing enhancements on top of Apple Notes, and exports notes into local Markdown files and folders you can keep, search, version, and use with AI agents.

## Status

NotesBridge is an actively developed macOS companion app for people who receive or organize notes in Apple Notes, but want the long-term trusted version of their notes to live as local Markdown files and folders.

The current version focuses on two jobs:

- improve the editing experience of the macOS version of Apple Notes with enhanced inline tools such as slash commands and markdown-style triggers
- sync Apple Notes into local-first, Obsidian-style local folders while preserving folder structure, attachments, front matter, internal links, and related elements

Apple Notes is great for easy editing on the Phone or shared notes with family and friends. NotesBridge turns that shared input into a Markdown workspace that is easier to organize, automate, version, and collaborate on with AI agents.

If you already use Apple Notes for capture and Obsidian or other local first note apps for long-term organization, NotesBridge is built for that workflow.

## Why try it

- Use slash commands and inline formatting tools directly on top of Apple Notes.
- Run as a lightweight macOS menu bar app instead of replacing your note-taking workflow.
- Preserve Apple Notes structure as real Markdown files and folders.
- Keep native attachments, scan exports, tables, and internal note links.
- Make synced notes easier to search, version, and process with AI agents.

## Quick start

1. Download the latest direct-download build from [Releases](https://github.com/peizh/NotesBridge/releases).
2. Move `NotesBridge.app` into `/Applications`.
3. Launch the app and grant the requested macOS permissions.
4. Choose your Apple Notes data folder on first full sync.
5. Start syncing into your Obsidian vault.

## What it does today

- Runs as a menu bar companion with a lightweight settings window.
- Shows a floating formatting toolbar after text selection, with quick actions for headings, bold, italic, strikethrough, and related formatting operations.
- Converts line-start markdown/list triggers into native Apple Notes formatting commands.
- Supports slash commands with inline exact-match execution and a floating suggestions menu.
- Syncs Apple Notes into local folders with front matter metadata and native attachment export.

## Product constraints

Apple Notes does not expose a public plugin or extension API. NotesBridge therefore behaves as a companion app rather than a true in-app Notes extension.

The current implementation is intentionally conservative:

- Inline enhancements rely on Accessibility and event synthesis, so the direct-download build is the primary vehicle for the full experience.
- The primary sync direction today is Apple Notes -> local folders, with no reverse sync.
- Slash commands currently support exact command + space and mouse-driven suggestion selection without requiring Input Monitoring.
- Full-note sync prompts for the macOS `group.com.apple.notes` data folder so NotesBridge can read the Apple Notes database and attachment files directly.

## Funding

If NotesBridge is useful in your workflow, you can support ongoing maintenance and release costs via the GitHub Sponsor button.

Sponsorship helps cover time spent on bug fixes, releases, signing/notarization, and general project upkeep. It does not create a support SLA or guarantee feature priority.

## License

MIT. See [LICENSE](./LICENSE).
