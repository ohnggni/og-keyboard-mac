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
if [[ "${1:-}" != "--no-pull" ]]; then
  before=$(git hash-object "$0")
  git pull --ff-only
  # dev.sh 자체가 바뀌었으면 새 내용으로 다시 실행 (실행 중 파일이 바뀌면 bash가 엉뚱한 줄을 읽음)
  if [[ "$(git hash-object "$0")" != "$before" ]]; then exec "$0" --no-pull; fi
fi

echo "▶ 2/5 조합기 테스트"
swift test 2>&1 | grep -E "Executed .* tests|error:|failed" | head -5

echo "▶ 3/5 빌드"
./build.sh

echo "▶ 4/5 설치"
pkill -x "$NAME" 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$HOME/Library/Input Methods"
cp -R "$APP" "$DEST"

echo "▶ 5/5 등록"
"$DEST/Contents/MacOS/$NAME" --install

echo "✅ 끝 — 입력 메뉴에서 'OG키보드'를 고르면 새 버전으로 동작"
