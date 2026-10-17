#!/bin/sh
# Збирає pluglight, кладе його в /usr/local/bin і запускає демон як LaunchDaemon.
#   ./install.sh                встановити або оновити
#   ./install.sh --require-app  те саме, але демон керує світлодіодом лише поки працює PlugLight.app
#   ./install.sh uninstall      прибрати демон і бінарник, повернути світлодіод macOS
# Привілейовані кроки йдуть через sudo, тож скрипт попросить пароль.
# PLUGLIGHT_SRC — готовий бінарник замість збирання (так ставить помічника програма).
set -e
cd "$(dirname "$0")"
LABEL=com.onelenyk.pluglight
BIN=/usr/local/bin/pluglight
PLIST=/Library/LaunchDaemons/$LABEL.plist
[ "$(id -u)" = 0 ] && SUDO= || SUDO=sudo

# До версії 0.3.0 проєкт називався MagSafe Light: прибираємо його службу й бінарник.
remove_legacy() {
  $SUDO launchctl bootout system/com.onelenyk.magsafe-light 2>/dev/null || true
  $SUDO rm -f /Library/LaunchDaemons/com.onelenyk.magsafe-light.plist /usr/local/bin/magsafe-light
  $SUDO rm -rf /tmp/magsafe-light
}

if [ "$1" = uninstall ]; then
  remove_legacy
  $SUDO launchctl bootout system/$LABEL 2>/dev/null || true
  [ -x "$BIN" ] && $SUDO "$BIN" led 0 || true
  $SUDO rm -f "$PLIST" "$BIN" /var/run/pluglight.state /var/log/pluglight.log
  echo "Removed. To remove the agent hooks: ./install-hooks.sh claude remove"
  exit 0
fi

SRC="${PLUGLIGHT_SRC:-build/pluglight}"
if [ -z "$PLUGLIGHT_SRC" ]; then
  [ -x "$SRC" ] && [ "$SRC" -nt src/pluglight.c ] || make
fi
EXTRA=
[ "$1" = --require-app ] && EXTRA='<string>--require-app</string>'

remove_legacy
$SUDO launchctl bootout system/$LABEL 2>/dev/null || true
$SUDO mkdir -p /usr/local/bin
$SUDO install -m 755 "$SRC" "$BIN"
sed "s|<string>daemon</string>|<string>daemon</string>$EXTRA|" launchd/$LABEL.plist > "${TMPDIR:-/tmp}/$LABEL.plist"
$SUDO install -m 644 "${TMPDIR:-/tmp}/$LABEL.plist" "$PLIST"
rm -f "${TMPDIR:-/tmp}/$LABEL.plist"
# До 0.5.0 демон писав у лог кожну зміну кольору; тепер там лише помилки.
$SUDO rm -f /var/log/pluglight.log
$SUDO launchctl bootstrap system "$PLIST"
echo "Helper started. Try: pluglight set busy; pluglight status"
