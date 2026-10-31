#!/bin/bash
# OG키보드 설치 / 업데이트
#   curl -fsSL https://raw.githubusercontent.com/ohnggni/og-keyboard-mac/main/install.sh | bash
set -euo pipefail

REPO="ohnggni/og-keyboard-mac"
URL="https://github.com/$REPO/releases/latest/download/OGKeyboard.zip"
DEST_DIR="$HOME/Library/Input Methods"
APP="$DEST_DIR/OGKeyboard.app"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "❌ 애플 실리콘(M 시리즈) 맥에서만 설치할 수 있습니다."; exit 1
fi
major=$(sw_vers -productVersion | cut -d. -f1)
if (( major < 13 )); then
  echo "❌ macOS 13 이상이 필요합니다 (지금: $(sw_vers -productVersion))."; exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "▶ 1/3 내려받는 중…"
curl -fL --progress-bar "$URL" -o "$TMP/OGKeyboard.zip"
ditto -x -k "$TMP/OGKeyboard.zip" "$TMP"
[[ -d "$TMP/OGKeyboard.app" ]] || { echo "❌ 내려받은 파일에 OGKeyboard.app 이 없습니다."; exit 1; }

echo "▶ 2/3 설치하는 중…"
pkill -x OGKeyboard 2>/dev/null || true
mkdir -p "$DEST_DIR"
[[ -d "$APP" ]] && rm -rf "$APP"
ditto "$TMP/OGKeyboard.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "▶ 3/3 입력 소스에 등록하는 중…"
"$APP/Contents/MacOS/OGKeyboard" --install || true

ver=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "?")
cat <<MSG

✅ OG키보드 $ver 설치를 마쳤습니다.

다음 순서로 설정을 마무리하십시오 (자세한 내용은 README 참고):
  1. 시스템 설정 → 키보드 → 입력 소스 → 편집 → + → 한국어 → OG키보드 추가
     (목록에 없으면 로그아웃 후 다시 로그인)
  2. 같은 화면에서 'Caps Lock으로 라틴 입력 소스 전환' 끄기
  3. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 · 입력 모니터링에서 OGKeyboard 켜기
     (업데이트한 경우: 목록의 OGKeyboard를 -로 지우고 다시 추가)
MSG
