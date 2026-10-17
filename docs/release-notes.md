## Install

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/magsafe-light/main/get.sh | sh
```

Or download `MagSafe-Light.zip`, unzip it and move it to Applications. The app is not signed with an Apple Developer ID, so on first launch macOS blocks it: go to **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine "/Applications/MagSafe Light.app"`.

Requires a Mac with MagSafe 3 (Apple Silicon) and macOS 13 or later. See [CHANGELOG.md](https://github.com/onelenyk/magsafe-light/blob/main/CHANGELOG.md) for what's new.

---

## Встановлення

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/magsafe-light/main/get.sh | sh
```

Або завантаж `MagSafe-Light.zip`, розпакуй і перенеси в «Програми». Програма не підписана сертифікатом Apple Developer ID, тому під час першого запуску macOS її заблокує: **Системні параметри → Конфіденційність і безпека → Все одно відкрити**, або `xattr -dr com.apple.quarantine "/Applications/MagSafe Light.app"`.

Потрібен Mac з MagSafe 3 (Apple Silicon) і macOS 13 або новіша.
