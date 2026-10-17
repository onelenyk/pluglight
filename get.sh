#!/bin/sh
# Встановлює PlugLight з останнього релізу на GitHub:
#   curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
# Завантажує зібрану програму, перевіряє контрольну суму, кладе в /Applications і запускає.
# Далі програма сама запропонує встановити помічника (потрібен пароль) і підключити Claude Code.
# Видалити: те саме з `-s -- uninstall`. PLUGLIGHT_FORCE=1 ставить і на мак без MagSafe 3.
set -e
REPO=onelenyk/pluglight
APP="/Applications/PlugLight.app"
LEGACY="/Applications/MagSafe Light.app"   # стара назва проєкту, до 0.3.0
BASE="https://github.com/$REPO/releases/latest/download"

# Повідомлення мовою системи: українською, якщо вона перша в списку мов, інакше англійською.
case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p)" in *uk*) UK=1 ;; *) UK= ;; esac
say() { if [ -n "$UK" ]; then echo "$2"; else echo "$1"; fi; }
die() { say "$1" "$2" >&2; exit 1; }

if [ "$1" = uninstall ]; then
  osascript -e 'quit app "PlugLight"' 2>/dev/null || true
  osascript -e 'quit app "MagSafe Light"' 2>/dev/null || true
  for a in "$APP" "$LEGACY"; do
    [ -x "$a/Contents/Resources/install.sh" ] || continue
    sh "$a/Contents/Resources/install-hooks.sh" claude remove || true
    say "Removing the helper (asks for your password)…" "Видаляю помічника (попросить пароль)…"
    sudo sh "$a/Contents/Resources/install.sh" uninstall
    break
  done
  rm -rf "$APP" "$LEGACY"
  say "PlugLight removed." "PlugLight видалено."
  exit 0
fi

[ "$(uname -s)" = Darwin ] || die "PlugLight needs macOS." "Потрібен macOS."
[ "$(uname -m)" = arm64 ] || die "PlugLight needs a Mac with Apple Silicon and MagSafe 3." "Потрібен Mac з Apple Silicon і MagSafe 3."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
say "Downloading PlugLight…" "Завантажую PlugLight…"
curl -fsSL "$BASE/PlugLight.zip" -o "$TMP/app.zip"
curl -fsSL "$BASE/PlugLight.zip.sha256" -o "$TMP/app.zip.sha256"
want=$(cut -d' ' -f1 "$TMP/app.zip.sha256")
got=$(shasum -a 256 "$TMP/app.zip" | cut -d' ' -f1)
[ "$want" = "$got" ] || die "Checksum mismatch, nothing was installed." "Контрольна сума не збігається, нічого не встановлено."
ditto -x -k "$TMP/app.zip" "$TMP"

if [ -z "$PLUGLIGHT_FORCE" ] && ! "$TMP/PlugLight.app/Contents/Resources/pluglight" probe >/dev/null 2>&1; then
  die "This Mac has no MagSafe 3 LED, so PlugLight has nothing to light up. It needs a MacBook Air M2 or later, or a MacBook Pro 14\"/16\" from 2021 onward. Nothing was installed." \
      "На цьому маку немає світлодіода MagSafe 3, тож PlugLight нічого не покаже. Потрібен MacBook Air M2 і новіші або MacBook Pro 14\"/16\" з 2021 року. Нічого не встановлено."
fi

osascript -e 'quit app "PlugLight"' 2>/dev/null || true
osascript -e 'quit app "MagSafe Light"' 2>/dev/null || true
rm -rf "$LEGACY" "$APP"
ditto "$TMP/PlugLight.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
say "Done: the PlugLight icon is now in the menu bar." "Готово: іконка PlugLight з'явилась у рядку меню вгорі."
