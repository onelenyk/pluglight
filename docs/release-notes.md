## What's new

- **Updates.** PlugLight checks GitHub once a day and offers to install a new version: it verifies the checksum, replaces itself and restarts. Menu → **Updates** has **Check now** and a switch for the daily check.
- If an update changes the helper, the app asks for your password once to update it.

Coming from 0.3.0 or earlier? Run the install command below once; after that, updates arrive by themselves.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Or download `PlugLight.zip`, unzip it and move it to Applications. The app is not signed with an Apple Developer ID, so on first launch macOS blocks it: go to **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Requires a Mac with MagSafe 3 (Apple Silicon) and macOS 13 or later. See [CHANGELOG.md](https://github.com/onelenyk/pluglight/blob/main/CHANGELOG.md) for what's new.

---

## Що нового

- **Оновлення.** PlugLight раз на добу перевіряє GitHub і пропонує встановити нову версію: перевіряє контрольну суму, замінює себе й перезапускається. Меню → **Оновлення**: «Перевірити зараз» і перемикач щоденної перевірки.
- Якщо оновлення змінює помічника, програма один раз попросить пароль, щоб його оновити.

Маєш 0.3.0 або старішу? Один раз запусти команду встановлення нижче, далі оновлення приходитимуть самі.

## Встановлення

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Або завантаж `PlugLight.zip`, розпакуй і перенеси в «Програми». Програма не підписана сертифікатом Apple Developer ID, тому під час першого запуску macOS її заблокує: **Системні параметри → Конфіденційність і безпека → Все одно відкрити**, або `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Потрібен Mac з MagSafe 3 (Apple Silicon) і macOS 13 або новіша.
