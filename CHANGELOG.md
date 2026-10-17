# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- English README with animated LED previews and an architecture diagram; Ukrainian version in `README.uk.md`.
- `CONTRIBUTING.md`, `SECURITY.md`, issue and pull request templates.

## [0.2.0] — 2026-10-17

### Added
- **MagSafe Light.app**, a menu bar app: state icon, session list, enable switch, LED test, Claude Code hooks toggle, helper management, launch at login, About window.
- One-command install from GitHub Releases (`get.sh`) with checksum verification; works without an Apple Developer ID.
- First-launch setup: installs the helper, then offers to connect Claude Code.
- `daemon --require-app`: the helper drives the LED only while the app sends its heartbeat.
- GitHub Actions: build and test on every push, publish a release on `v*` tags.
- End-to-end tests against real Claude Code (`tests/e2e-claude.sh`) and real menu clicks (`tests/e2e-app.sh`).

## [0.1.0] — 2026-10-17

### Added
- `magsafe-light` CLI: read and write the `ACLC` SMC key, per-session agent states, priority and expiry, root LaunchDaemon.
- Claude Code hooks and an installer that merges them into `~/.claude/settings.json`.

[Unreleased]: https://github.com/onelenyk/magsafe-light/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/onelenyk/magsafe-light/releases/tag/v0.2.0
[0.1.0]: https://github.com/onelenyk/magsafe-light/commit/aeafb95
