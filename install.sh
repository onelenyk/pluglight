#!/bin/sh
# Збирає magsafe-light, кладе його в /usr/local/bin і запускає демон як LaunchDaemon.
#   ./install.sh                встановити або оновити
#   ./install.sh --require-app  те саме, але демон керує світлодіодом лише поки працює MagSafe Light.app
#   ./install.sh uninstall      прибрати демон і бінарник, повернути світлодіод macOS
# Привілейовані кроки йдуть через sudo, тож скрипт попросить пароль.
# MAGSAFE_LIGHT_SRC — готовий бінарник замість збирання (так ставить помічника програма).
set -e
cd "$(dirname "$0")"
LABEL=com.onelenyk.magsafe-light
BIN=/usr/local/bin/magsafe-light
PLIST=/Library/LaunchDaemons/$LABEL.plist
[ "$(id -u)" = 0 ] && SUDO= || SUDO=sudo

if [ "$1" = uninstall ]; then
  $SUDO launchctl bootout system/$LABEL 2>/dev/null || true
  [ -x "$BIN" ] && $SUDO "$BIN" led 0 || true
  $SUDO rm -f "$PLIST" "$BIN"
  echo "Прибрано. Хуки агентів знімає: ./install-hooks.sh claude remove"
  exit 0
fi

SRC="${MAGSAFE_LIGHT_SRC:-build/magsafe-light}"
if [ -z "$MAGSAFE_LIGHT_SRC" ]; then
  [ -x "$SRC" ] && [ "$SRC" -nt src/magsafe-light.c ] || make
fi
EXTRA=
[ "$1" = --require-app ] && EXTRA='<string>--require-app</string>'

$SUDO launchctl bootout system/$LABEL 2>/dev/null || true
$SUDO mkdir -p /usr/local/bin
$SUDO install -m 755 "$SRC" "$BIN"
sed "s|<string>daemon</string>|<string>daemon</string>$EXTRA|" launchd/$LABEL.plist > "${TMPDIR:-/tmp}/$LABEL.plist"
$SUDO install -m 644 "${TMPDIR:-/tmp}/$LABEL.plist" "$PLIST"
rm -f "${TMPDIR:-/tmp}/$LABEL.plist"
$SUDO launchctl bootstrap system "$PLIST"
echo "Демон запущено. Перевірка: magsafe-light set busy; magsafe-light status"
