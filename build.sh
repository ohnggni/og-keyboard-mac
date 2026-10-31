#!/bin/bash
# OG키보드 빌드: build/OGKeyboard.app 을 만든다 (dev.sh와 GitHub 릴리스가 함께 씀)
#   서명: 키체인에 'OGKeyboard Dev' 인증서가 있으면 그것으로, 없으면 임시(ad-hoc) 서명
set -euo pipefail
cd "$(dirname "$0")"

NAME=OGKeyboard
APP="build/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -module-name $NAME \
  Sources/HangulCore/*.swift App/*.swift \
  -framework Cocoa -framework InputMethodKit -framework Carbon -framework IOKit -framework WebKit \
  -o "$APP/Contents/MacOS/$NAME"
cp App/Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
cp App/Resources/*.dat "$APP/Contents/Resources/"
cp App/Resources/emoji_groups.txt "$APP/Contents/Resources/"
cp App/Resources/*.html App/Resources/help-icon.png "$APP/Contents/Resources/"
iconutil -c icns App/Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/licenses" && cp licenses/*.txt LICENSE "$APP/Contents/Resources/licenses/"
cp -R App/Resources/*.lproj "$APP/Contents/Resources/"
tiffutil -cathidpicheck App/Resources/icon.png App/Resources/icon@2x.png \
  -out "$APP/Contents/Resources/icon.tiff" >/dev/null 2>&1

IDENTITY="OGKeyboard Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
  echo "  (임시 서명)"
fi
