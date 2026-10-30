#!/bin/bash
# OG키보드(맥) 개발용: 받아오기 → 테스트 → 빌드 → 설치 → 재시작을 한 번에.
#   ./dev.sh          전체
#   ./dev.sh log      입력기 로그 실시간 보기 (Ctrl+C로 끝)
set -euo pipefail
cd "$(dirname "$0")"

NAME=OGKeyboard
APP="build/$NAME.app"
DEST="$HOME/Library/Input Methods/$NAME.app"

if [[ "${1:-}" == "log" ]]; then
  exec log stream --style compact --level info --predicate "subsystem == \"kr.ogapp.inputmethod.OGKeyboard\""
fi

echo "▶ 1/5 받아오기"
git pull --ff-only

echo "▶ 2/5 조합기 테스트"
swift test 2>&1 | grep -E "Executed .* tests|error:|failed" | head -5

echo "▶ 3/5 빌드"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -module-name $NAME \
  Sources/HangulCore/*.swift App/*.swift \
  -framework Cocoa -framework InputMethodKit -framework Carbon \
  -o "$APP/Contents/MacOS/$NAME"
cp App/Info.plist "$APP/Contents/"
tiffutil -cathidpicheck App/Resources/icon.png App/Resources/icon@2x.png \
  -out "$APP/Contents/Resources/icon.tiff" >/dev/null 2>&1
codesign --force --sign - "$APP"

echo "▶ 4/5 설치"
pkill -x "$NAME" 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$HOME/Library/Input Methods"
cp -R "$APP" "$DEST"

echo "▶ 5/5 등록"
"$DEST/Contents/MacOS/$NAME" --install

echo "✅ 끝 — 입력 메뉴에서 'OG키보드'를 고르면 새 버전으로 동작"
