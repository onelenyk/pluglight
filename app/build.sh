#!/bin/sh
# Збирає build/PlugLight.app: програма в рядку меню з вкладеними pluglight, встановлювачами й хуками.
set -e
cd "$(dirname "$0")/.."
VERSION=${VERSION:-$(cat VERSION)}  # VERSION=0.0.1 sh app/build.sh — для перевірки оновлень
APP="build/PlugLight.app"

make build/pluglight
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos13 app/main.swift app/Updater.swift -o "$APP/Contents/MacOS/PlugLight"

swift app/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cp build/pluglight install.sh install-hooks.sh "$APP/Contents/Resources/"
cp -R launchd hooks app/en.lproj app/uk.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>uk</string></array>
  <key>CFBundleIdentifier</key><string>com.onelenyk.pluglight.app</string>
  <key>CFBundleName</key><string>PlugLight</string>
  <key>CFBundleDisplayName</key><string>PlugLight</string>
  <key>CFBundleExecutable</key><string>PlugLight</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>onelenyk</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP/Contents/Resources/pluglight"
codesign --force --sign - "$APP"
echo "Зібрано: $APP"
