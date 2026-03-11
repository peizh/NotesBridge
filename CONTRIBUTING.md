# Contributing to NotesBridge

This repository uses GitHub Issues and Pull Requests as the default workflow for planning, implementation, review, and release preparation.

## Workflow

1. Create or triage an issue before starting work.
2. Keep one issue focused on one user-visible problem or feature.
3. Create a branch for the issue.
4. Implement the change with tests.
5. Open a pull request that links the issue and includes validation results.
6. Merge only after review and CI pass.

Recommended branch naming:

- `agent/<issue-number>-short-slug`
- `feature/<short-slug>`
- `fix/<short-slug>`

Examples:

- `agent/42-fix-scan-gallery-export`
- `fix-slash-menu-anchor`

## Issue Guidelines

Use the provided issue forms whenever possible.

Bug reports should include:

- What is broken now
- What should happen instead
- Minimal reproduction steps
- Acceptance criteria
- Logs, screenshots, or sample exported files when available

Feature requests should include:

- The user or workflow problem
- The desired capability
- Clear acceptance criteria
- Explicit non-goals
- References to upstream behavior or prior issues when relevant

Issue writing rules:

- Do not combine multiple unrelated problems in one issue
- Prefer concrete symptoms over vague reports
- Include exact file paths, status text, or log snippets when available
- Define done in observable terms

## Suggested Labels

Use a small, consistent label set.

Core type labels:

- `bug`
- `feature`
- `refactor`
- `docs`
- `test`
- `good first issue`
- `help wanted`

State / triage labels:

- `needs-triage`
- `needs-repro`
- `agent-ready`
- `blocked`

Area labels:

- `area:sync`
- `area:apple-notes`
- `area:obsidian-export`
- `area:inline-tools`
- `area:permissions`
- `area:ui`
- `area:ci`

Priority labels:

- `priority:high`
- `priority:medium`
- `priority:low`

Recommended usage:

- Add exactly one core type label
- Add one or more area labels
- Add a priority label for actionable issues
- Remove `needs-triage` once scope and acceptance are clear
- Add `agent-ready` only when the issue contains enough detail to implement without discovery from the reporter

## Pull Request Guidelines

Every PR should:

- Link the source issue
- Explain the behavior change
- Describe how it was validated
- Call out risks, regressions checked, and follow-up work

Preferred PR structure:

1. Summary
2. Linked issue
3. Validation
4. Risks / regressions checked
5. Reviewer notes

PR rules:

- Keep PRs focused; avoid mixing refactors with product changes unless necessary
- Include tests for bug fixes and new behavior
- Update docs or templates when workflow behavior changes
- Use `Closes #<issue>` when the PR fully resolves the issue

## Validation

Before opening or merging a PR, run:

```bash
swift test
xcodebuild -scheme NotesBridge -workspace .swiftpm/xcode/package.xcworkspace -destination 'platform=macOS' test
```

If the change affects runtime behavior, also do the relevant manual validation, for example:

- Apple Notes -> Obsidian sync
- slash commands and inline formatting
- permissions and bundled app launch flow
- attachment export and internal note links

## Commit Guidelines

Prefer commit messages that describe the actual shipped behavior, not the implementation mechanics alone.

Good examples:

- `Convert Apple Notes tables and scan galleries natively`
- `Fix Apple Notes sync diagnostics and export deep links`
- `Add GitHub issue forms, PR template, and CI`

## Notes for AI-Assisted Development

When driving work through issues for an AI coding agent:

- Put acceptance criteria directly in the issue
- Include exact logs, screenshots, sample notes, or exported markdown when possible
- Mark issues as `agent-ready` only after repro and scope are clear
- Ask for a plan first when the change is architectural or touches multiple subsystems

Good prompts:

- `Implement #42 and open a PR`
- `Read #57 and produce an implementation plan`
- `Review PR #18 for regressions and testing gaps`

## Repository Settings Checklist

Keep Discussions disabled for this repository.

Recommended repository settings:

- Set the default branch to `main`
- Protect `main` and require passing CI before merge
- Enable Dependabot alerts
- Enable secret scanning
- Enable code scanning if available on the repository plan
