## What's new

- PlugLight now works with Codex CLI, Qwen Code, Gemini CLI, Cursor, Antigravity, Copilot CLI and OpenCode, not just Claude Code. The menu has an **Agent hooks** submenu with every agent, a ✓ next to the connected ones and one click to connect or disconnect; agents this Mac doesn't have are listed greyed out. The first-run offer now covers all detected agents.
- Even lighter on the battery: PlugLight reads agent states more cheaply and redraws its menu bar icon only when it changes.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Or download `PlugLight.zip`, unzip it and move it to Applications. The app is not signed with an Apple Developer ID, so on first launch macOS blocks it: go to **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Requires a Mac with MagSafe 3 (Apple Silicon) and macOS 13 or later. See [CHANGELOG.md](https://github.com/onelenyk/pluglight/blob/main/CHANGELOG.md) for what's new.

---

## Що нового

- PlugLight тепер працює не лише з Claude Code, а й з Codex CLI, Qwen Code, Gemini CLI, Cursor, Antigravity, Copilot CLI та OpenCode. У меню з'явилось підменю **Хуки агентів**: усі агенти, ✓ біля підключених, один клік щоб підключити чи відключити; тих, кого на макі немає, видно сірим. Перший запуск тепер пропонує всіх знайдених агентів.
- Ще менше навантаження на батарею: PlugLight дешевше читає стани агентів і перемальовує іконку в рядку меню, лише коли вона змінюється.

## Встановлення

```sh
curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
```

Або завантаж `PlugLight.zip`, розпакуй і перенеси в «Програми». Програма не підписана сертифікатом Apple Developer ID, тому під час першого запуску macOS її заблокує: **Системні параметри → Конфіденційність і безпека → Все одно відкрити**, або `xattr -dr com.apple.quarantine "/Applications/PlugLight.app"`.

Потрібен Mac з MagSafe 3 (Apple Silicon) і macOS 13 або новіша.
