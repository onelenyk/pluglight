# Security

MagSafe Light installs a helper that runs as root, so here is exactly what it does and does not do.

## What runs as root

`/usr/local/bin/magsafe-light daemon --require-app`, started by the LaunchDaemon `com.onelenyk.magsafe-light` (`/Library/LaunchDaemons/com.onelenyk.magsafe-light.plist`). It:

- writes a single SMC key, `ACLC`, and only the values 0, 1, 3 and 4;
- reads small state files from `/tmp/magsafe-light`, opening them with `O_NOFOLLOW` and accepting only the words `busy`, `waiting`, `done`, `error`;
- deletes expired state files in that directory;
- makes no network connections and runs no other programs.

## Trust boundaries

- Any local user or process can write to `/tmp/magsafe-light` and therefore change the LED color. That is by design: agent hooks run unprivileged. Nothing beyond the LED color can be influenced this way.
- The app is ad-hoc signed, not notarized. `get.sh` verifies the release zip against the published SHA-256 before installing. Prefer building from source if you want to audit exactly what runs.
- The app re-installs the helper only when its bundled binary differs from the installed one, and always through the standard macOS administrator prompt.

## Removing everything

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/magsafe-light/main/get.sh | sh -s -- uninstall
```

## Reporting a vulnerability

Please report security issues privately through [GitHub security advisories](https://github.com/onelenyk/magsafe-light/security/advisories/new) rather than a public issue.
