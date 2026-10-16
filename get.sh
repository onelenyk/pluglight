#!/bin/sh
# Встановлює MagSafe Light з останнього релізу на GitHub:
#   curl -fsSL https://raw.githubusercontent.com/onelenyk/magsafe-light/main/get.sh | sh
# Завантажує зібрану програму, перевіряє контрольну суму, кладе в /Applications і запускає.
# Далі програма сама запропонує встановити помічника (потрібен пароль) і підключити Claude Code.
# Видалити: те саме з `-s -- uninstall`.
set -e
REPO=onelenyk/magsafe-light
APP="/Applications/MagSafe Light.app"
BASE="https://github.com/$REPO/releases/latest/download"

if [ "$1" = uninstall ]; then
  osascript -e 'quit app "MagSafe Light"' 2>/dev/null || true
  if [ -x "$APP/Contents/Resources/install.sh" ]; then
    sh "$APP/Contents/Resources/install-hooks.sh" claude remove || true
    echo "Видаляю помічника (попросить пароль)…"
    sudo sh "$APP/Contents/Resources/install.sh" uninstall
  fi
  rm -rf "$APP"
  echo "MagSafe Light видалено."
  exit 0
fi

[ "$(uname -s)" = Darwin ] || { echo "Потрібен macOS." >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo "Потрібен Mac з Apple Silicon і MagSafe 3." >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Завантажую MagSafe Light…"
curl -fsSL "$BASE/MagSafe-Light.zip" -o "$TMP/app.zip"
curl -fsSL "$BASE/MagSafe-Light.zip.sha256" -o "$TMP/app.zip.sha256"
want=$(cut -d' ' -f1 "$TMP/app.zip.sha256")
got=$(shasum -a 256 "$TMP/app.zip" | cut -d' ' -f1)
[ "$want" = "$got" ] || { echo "Контрольна сума не збігається, нічого не встановлено." >&2; exit 1; }

osascript -e 'quit app "MagSafe Light"' 2>/dev/null || true
ditto -x -k "$TMP/app.zip" "$TMP"
rm -rf "$APP"
ditto "$TMP/MagSafe Light.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
echo "Готово: іконка MagSafe Light з'явилась у рядку меню вгорі."
