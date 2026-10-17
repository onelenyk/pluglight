## What's new

- **English interface.** PlugLight follows your system language: English, or Ukrainian.
- **Macs without MagSafe 3** get a clear message from the installer and the app instead of a light that never turns on.
- **Lighter on the battery:** the app reads agent states directly and no longer starts a process every second. The helper's log no longer grows with every color change.
- The menu shows what the LED actually displays.

This update replaces the helper, so PlugLight asks for your password once.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Or download `PlugLight.zip`, unzip it and move it to Applications. The app is not signed with an Apple Developer ID, so on first launch macOS blocks it: go to **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Requires a Mac with MagSafe 3 (Apple Silicon) and macOS 13 or later. See [CHANGELOG.md](https://github.com/onelenyk/pluglight/blob/main/CHANGELOG.md) for what's new.

---

## Що нового

- **Англійський інтерфейс.** PlugLight говорить мовою системи: українською або англійською.
- **Маки без MagSafe 3** отримують зрозуміле повідомлення від інсталятора й програми, а не світлодіод, який ніколи не засвітиться.
- **Менше навантаження на батарею:** програма читає стани агентів сама й більше не запускає процес щосекунди. Лог помічника більше не росте з кожною зміною кольору.
- Меню показує, що насправді світиться на кабелі.

Це оновлення замінює помічника, тож PlugLight один раз попросить пароль.

## Встановлення

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Або завантаж `PlugLight.zip`, розпакуй і перенеси в «Програми». Програма не підписана сертифікатом Apple Developer ID, тому під час першого запуску macOS її заблокує: **Системні параметри → Конфіденційність і безпека → Все одно відкрити**, або `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Потрібен Mac з MagSafe 3 (Apple Silicon) і macOS 13 або новіша.
