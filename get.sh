#!/bin/sh
# Встановлює PlugLight з останнього релізу на GitHub:
#   curl -fsSL https://raw.githubusercontent.com/onelenyk/pluglight/main/get.sh | sh
# Завантажує зібрану програму, перевіряє контрольну суму, кладе в /Applications і запускає.
# Далі програма сама запропонує встановити помічника (потрібен пароль) і підключити Claude Code.
# Видалити: те саме з `-s -- uninstall`.
set -e
REPO=onelenyk/pluglight
APP="/Applications/PlugLight.app"
LEGACY="/Applications/MagSafe Light.app"   # стара назва проєкту, до 0.3.0
BASE="https://github.com/$REPO/releases/latest/download"

if [ "$1" = uninstall ]; then
  osascript -e 'quit app "PlugLight"' 2>/dev/null || true
  osascript -e 'quit app "MagSafe Light"' 2>/dev/null || true
  for a in "$APP" "$LEGACY"; do
    [ -x "$a/Contents/Resources/install.sh" ] || continue
    sh "$a/Contents/Resources/install-hooks.sh" claude remove || true
    echo "Видаляю помічника (попросить пароль)…"
    sudo sh "$a/Contents/Resources/install.sh" uninstall
    break
  done
  rm -rf "$APP" "$LEGACY"
  echo "PlugLight видалено."
  exit 0
fi

[ "$(uname -s)" = Darwin ] || { echo "Потрібен macOS." >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo "Потрібен Mac з Apple Silicon і MagSafe 3." >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Завантажую PlugLight…"
curl -fsSL "$BASE/PlugLight.zip" -o "$TMP/app.zip"
curl -fsSL "$BASE/PlugLight.zip.sha256" -o "$TMP/app.zip.sha256"
want=$(cut -d' ' -f1 "$TMP/app.zip.sha256")
got=$(shasum -a 256 "$TMP/app.zip" | cut -d' ' -f1)
[ "$want" = "$got" ] || { echo "Контрольна сума не збігається, нічого не встановлено." >&2; exit 1; }

osascript -e 'quit app "PlugLight"' 2>/dev/null || true
osascript -e 'quit app "MagSafe Light"' 2>/dev/null || true
rm -rf "$LEGACY"
ditto -x -k "$TMP/app.zip" "$TMP"
rm -rf "$APP"
ditto "$TMP/PlugLight.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
echo "Готово: іконка PlugLight з'явилась у рядку меню вгорі."
