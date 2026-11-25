## What's new

- PlugLight now supports **18 AI coding harnesses**: added **Windsurf (Cascade)**, **Kiro (CLI & IDE)**, **Crush**, **Factory Droid**, **Auggie (Augment Code)**, **Goose**, **Kilo Code**, **Pi Coding Agent**, **Oh My Pi**, and **Cline (CLI & VS Code)**, plus improved **Antigravity (CLI & IDE)** (`waiting` state and IDE/CLI/App auto-detection).
- Cleaner **Agent hooks** menu: shows how many detected agents are connected, adds **Connect all detected** / **Disconnect all** actions, path tooltips, and groups undetected agents into an **Other supported agents** submenu where any of them can be installed with one click.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Or download `PlugLight.zip`, unzip it and move it to Applications. The app is not signed with an Apple Developer ID, so on first launch macOS blocks it: go to **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Requires a Mac with MagSafe 3 (Apple Silicon) and macOS 13 or later. See [CHANGELOG.md](https://github.com/onelenyk/pluglight/blob/main/CHANGELOG.md) for what's new.

---

## Що нового

- PlugLight тепер підтримує **18 AI-агентів та harness'ів**: додано **Windsurf (Cascade)**, **Kiro (CLI & IDE)**, **Crush**, **Factory Droid**, **Auggie (Augment Code)**, **Goose**, **Kilo Code**, **Pi Coding Agent**, **Oh My Pi** та **Cline (CLI & VS Code)**, а також покращено **Antigravity (CLI & IDE)** (стан `waiting` і автовиявлення IDE/CLI/App).
- Зручніше меню **Хуки агентів**: показує кількість підключених агентів, додає кнопки **Підключити всі знайдені** / **Відключити всі**, підказки зі шляхами та вкладене підменю **Інші підтримувані агенти** для ручного підключення в один клік.

## Встановлення

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Або завантаж `PlugLight.zip`, розпакуй і перенеси в «Програми». Програма не підписана сертифікатом Apple Developer ID, тому під час першого запуску macOS її заблокує: **Системні параметри → Конфіденційність і безпека → Все одно відкрити**, або `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Потрібен Mac з MagSafe 3 (Apple Silicon) і macOS 13 або новіша.
