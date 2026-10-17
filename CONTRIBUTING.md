# Contributing

Thanks for wanting to help! Issues and pull requests are welcome in English or Ukrainian.

## Project layout

| Path | What it is |
|---|---|
| `src/pluglight.c` | the CLI and the helper daemon: SMC access, session states, hooks |
| `app/main.swift` | the menu bar app (AppKit, no Xcode project) |
| `app/build.sh` | builds `build/PlugLight.app` |
| `hooks/claude.json` | Claude Code hooks, merged by `install-hooks.sh` |
| `install.sh` | installs the helper as a LaunchDaemon |
| `get.sh` | one-command install from GitHub Releases |
| `tests/` | logic tests and end-to-end tests |

## Develop

You need a Mac with Xcode Command Line Tools.

```sh
make                 # build the CLI
make test            # logic tests, no SMC writes, no root
make app             # build the app into build/
make install-app     # install into /Applications and launch
```

`pluglight daemon --dry-run` runs the daemon without touching the SMC and prints every LED change, which is handy for working on state logic. Point it and the CLI at a scratch directory with `PLUGLIGHT_DIR=$(mktemp -d)`.

Before opening a pull request:

- run `make test`;
- if you touched hooks or the app, run `tests/e2e-claude.sh` and `tests/e2e-app.sh` on a Mac with MagSafe and mention the result;
- keep the C code dependency-free and the hook path silent and always exiting 0 — it runs inside the agent.

## Adding another agent

1. Find which of the agent's hook events mean working, waiting, done, error and session end.
2. Add `hooks/<agent>.json` that calls `/usr/local/bin/pluglight hook <state>` and passes the event JSON on stdin.
3. Teach `install-hooks.sh` where the agent keeps its settings.
4. Document the event mapping in both READMEs.

## Releasing

1. Bump `VERSION` and move the `Unreleased` section in `CHANGELOG.md` under the new version.
2. Commit, then `git tag vX.Y.Z && git push origin main --tags`.
3. GitHub Actions builds, tests and publishes `PlugLight.zip` with its checksum; `get.sh` picks it up automatically.
