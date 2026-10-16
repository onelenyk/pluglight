#!/bin/sh
# Збирає magsafe-light, кладе його в /usr/local/bin і запускає демон як LaunchDaemon.
#   ./install.sh            встановити або оновити
#   ./install.sh uninstall  прибрати демон і бінарник, повернути світлодіод macOS
# Привілейовані кроки йдуть через sudo, тож скрипт попросить пароль.
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

[ -x build/magsafe-light ] && [ build/magsafe-light -nt src/magsafe-light.c ] || make
$SUDO launchctl bootout system/$LABEL 2>/dev/null || true
$SUDO mkdir -p /usr/local/bin
$SUDO install -m 755 build/magsafe-light "$BIN"
$SUDO install -m 644 launchd/$LABEL.plist "$PLIST"
$SUDO launchctl bootstrap system "$PLIST"
echo "Демон запущено. Перевірка: magsafe-light set busy; magsafe-light status"
