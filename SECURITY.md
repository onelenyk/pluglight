# Security

PlugLight installs a helper that runs as root, so here is exactly what it does and does not do.

## What runs as root

`/usr/local/bin/pluglight daemon --require-app`, started by the LaunchDaemon `com.onelenyk.pluglight` (`/Library/LaunchDaemons/com.onelenyk.pluglight.plist`). It:

- writes a single SMC key, `ACLC`, and only the values 0, 1, 3 and 4;
- reads small state files from `/tmp/pluglight`, opening them with `O_NOFOLLOW` and accepting only the words `busy`, `waiting`, `done`, `error`;
- deletes expired state files in that directory;
- writes the current LED pattern to `/var/run/pluglight.state` (a root-only directory, so other users can't plant a link there) for the menu bar app to show;
- logs only errors, to `/var/log/pluglight.log`;
- makes no network connections and runs no other programs.

## Trust boundaries

- Any local user or process can write to `/tmp/pluglight` and therefore change the LED color. That is by design: agent hooks run unprivileged. Nothing beyond the LED color can be influenced this way.
- The app is ad-hoc signed, not notarized. `get.sh` verifies the release zip against the published SHA-256 before installing. Prefer building from source if you want to audit exactly what runs.
- The menu bar app makes one network request a day, to `api.github.com`, to check for a new release (turn it off under **Updates**). An update downloads `PlugLight.zip` from this repository's GitHub Releases, checks its SHA-256 and the bundle identifier, then replaces the app. The root helper itself never touches the network.
- The app re-installs the helper only when its bundled binary differs from the installed one, and always through the standard macOS administrator prompt.

## Removing everything

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh -s -- uninstall
```

## Reporting a vulnerability

Please report security issues privately through [GitHub security advisories](https://github.com/onelenyk/pluglight/security/advisories/new) rather than a public issue.
