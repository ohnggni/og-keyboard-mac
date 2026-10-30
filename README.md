# OG키보드 (macOS)

애플 실리콘 맥용 한글 입력기. 안드로이드판 OG외장키보드(`sebeol390-ime`)의 기능을 맥으로 옮기는 중.

## 지금 되는 것 (0.2)
- 세벌식 390·391·순아래, 두벌식 (모아치기, 자모 단위 Backspace) — 메뉴바에서 자판 선택
- 한/영: Caps Lock 짧게(길게 = 대문자 고정, 풀면 원래대로), 오른쪽 Command 짧게. 앱별 한/영 기억
- 메뉴바 아이콘: 작은 OG + 가/A (대문자 고정은 칸 안의 A)
- 오른쪽 Command 길게 → 바로잡기 (dkssud ↔ 안녕, 2초 안에 다시 길게 = 한 낱말 더, 선택 영역 변환)
- 오른쪽 Option → 한자·기호·이모지 후보, 두 번 → 이모지 전체 창
- 텍스트 단축어: 이름 + 오른쪽 Option (메뉴바 → 텍스트 단축어…에서 관리)
- Ctrl+Option+V → 클립보드 기록 (최근 20개, 민감 표시·비밀번호 칸 복사는 제외)
- 앱별: 터미널처럼 다루기, 순정 입력기 쓰기(그 앱에서만 자동 전환)
- 메뉴바 → 사용법…, OG키보드 정보…

## 빌드·설치
```
./dev.sh        # 받아오기 → 테스트 → 빌드 → ~/Library/Input Methods 설치 → 등록
./dev.sh log    # 입력기 로그 보기
```
처음 한 번: 시스템 설정 → 키보드 → 입력 소스 → 편집 → + → 한국어 → **OG키보드** 추가.
권한: 손쉬운 사용(터미널 한자·바로잡기), 입력 모니터링(Caps Lock). 서명용 키체인 인증서 `OGKeyboard Dev`가 있으면 권한이 빌드마다 유지됨.

## 구조
| 경로 | 역할 |
|---|---|
| `Sources/HangulCore/` | 조합기·자판 표 (안드판에서 옮김, 맥 의존성 없음) |
| `Tests/HangulCoreTests/` | 조합기 테스트 (`swift test`) |
| `App/` | 입력기 본체 (InputMethodKit), Info.plist, 아이콘 |

자판 표 출처: libhangul (LGPL-2.1). 한자 사전: libhangul hanja (BSD-3), 이모지: Unicode CLDR·emojibase — `licenses/` 참고.
