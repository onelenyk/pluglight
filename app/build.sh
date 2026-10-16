#!/bin/sh
# Збирає build/MagSafe Light.app: програма в рядку меню з вкладеними magsafe-light, встановлювачами й хуками.
set -e
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
APP="build/MagSafe Light.app"

make build/magsafe-light
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos13 app/main.swift -o "$APP/Contents/MacOS/MagSafeLight"

swift app/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cp build/magsafe-light install.sh install-hooks.sh "$APP/Contents/Resources/"
cp -R launchd hooks "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.onelenyk.magsafe-light.app</string>
  <key>CFBundleName</key><string>MagSafe Light</string>
  <key>CFBundleDisplayName</key><string>MagSafe Light</string>
  <key>CFBundleExecutable</key><string>MagSafeLight</string>
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

codesign --force --sign - "$APP/Contents/Resources/magsafe-light"
codesign --force --sign - "$APP"
echo "Зібрано: $APP"
