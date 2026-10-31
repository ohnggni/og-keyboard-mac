#!/bin/bash
# OG키보드 제거
#   curl -fsSL https://raw.githubusercontent.com/ohnggni/og-keyboard-mac/main/uninstall.sh | bash
set -euo pipefail
APP="$HOME/Library/Input Methods/OGKeyboard.app"

pkill -x OGKeyboard 2>/dev/null || true
if [[ -d "$APP" ]]; then
  rm -rf "$APP"
  echo "✅ $APP 를 지웠습니다."
else
  echo "설치된 OG키보드가 없습니다 ($APP)."
fi
cat <<MSG

남은 정리 (필요하면):
  • 시스템 설정 → 키보드 → 입력 소스에서 OG키보드 제거
  • 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 · 입력 모니터링에서 OGKeyboard 제거
  • 설정·단축어·클립보드 기록까지 지우려면:  defaults delete kr.ogapp.inputmethod.OGKeyboard
MSG
