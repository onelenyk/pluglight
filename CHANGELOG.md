# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.5.1] — 2026-10-17

### Changed
- Even lighter on the CPU: the app reads session files with `lstat` instead of `FileManager`, and redraws the menu bar icon only when it changes.

## [0.5.0] — 2026-10-17

### Added
- English interface. The app follows the system language: English, or Ukrainian when it comes first.
- Macs without the MagSafe LED are detected: `pluglight probe`, a clear message in the installer and the app, and the helper no longer restarts in a loop there.
- The menu shows what the LED actually displays, read from `/var/run/pluglight.state`.

### Changed
- The app reads session files itself instead of running `pluglight status` every second, so it uses almost no CPU.
- The helper logs only errors, so `/var/log/pluglight.log` no longer grows with every color change.
- Command-line output and installer messages are in English; `get.sh` speaks Ukrainian when the system does.

## [0.4.0] — 2026-10-17

### Added
- Updates: the app checks GitHub Releases once a day and offers to install a new version. It verifies the checksum, replaces itself and restarts; the menu has **Updates → Check now** and a switch for the daily check. `open -a PlugLight --args --update` updates without asking.
- After an update that changes the helper, the app asks to update the helper rather than install it.

## [0.3.0] — 2026-10-17

### Changed
- **Renamed to PlugLight** (was MagSafe Light): the repository, the app, the `pluglight` command, the `com.onelenyk.pluglight` helper and `/tmp/pluglight`. MagSafe is Apple's trademark, so it stays only in the description of what the app works with.

### Added
- Automatic migration from MagSafe Light: installing PlugLight removes the old app, helper and hooks, and swaps in the new hooks.
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

[Unreleased]: https://github.com/onelenyk/pluglight/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/onelenyk/pluglight/releases/tag/v0.5.1
[0.5.0]: https://github.com/onelenyk/pluglight/releases/tag/v0.5.0
[0.4.0]: https://github.com/onelenyk/pluglight/releases/tag/v0.4.0
[0.3.0]: https://github.com/onelenyk/pluglight/releases/tag/v0.3.0
[0.2.0]: https://github.com/onelenyk/pluglight/releases/tag/v0.2.0
[0.1.0]: https://github.com/onelenyk/pluglight/commit/aeafb95
