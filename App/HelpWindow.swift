import Cocoa

/// 사용법 창과 앱 정보
final class HelpWindow: NSObject {
    static let shared = HelpWindow()

    private var window: NSWindow?

    // MARK: 사용법

    /// (제목, [(키, 설명)]) — 키가 비어 있으면 설명만 한 줄로
    private let sections: [(String, [(String, String)])] = [
        ("한/영 전환", [
            ("Caps Lock 짧게", "한글 ↔ 영문"),
            ("Caps Lock 길게", "대문자 고정 (영문 대문자). 한글이었으면 풀 때 한글로 돌아옴"),
            ("오른쪽 Command 짧게", "한글 ↔ 영문"),
            ("", "전환하면 화면 아래에 파란 '가' / 초록 'a' / 주황 'A'가 잠깐 뜹니다. 메뉴바의 OG 아이콘에도 지금 상태가 보입니다 (가 = 한글, A = 영문, 칸 안의 A = 대문자 고정)."),
            ("", "앱마다 마지막 한/영을 기억합니다 (메뉴에서 끄기·지우기)."),
        ]),
        ("잘못 친 글자 바로잡기", [
            ("오른쪽 Command 길게", "커서 앞 낱말을 반대 언어로 다시 쓰고 한/영도 전환 (dkssud → 안녕, ㅇㅁ션ㅊㄱ → jinseok)"),
            ("2초 안에 다시 길게", "한 낱말씩 더 앞으로"),
            ("드래그로 선택 후 길게", "선택한 부분 전체"),
            ("", "실제로 누른 키를 기억해 모아치기로 친 글자도 정확히 되돌립니다. 전부 대문자인 낱말은 Caps Lock이 켜진 채 친 것으로 보고 소문자 키로 바꿉니다."),
        ]),
        ("한자 · 기호 · 이모지", [
            ("낱말 뒤 오른쪽 Option", "한자 후보 (긴 낱말부터: 大韓民國 → 民國 → 國), 낱말에 맞는 이모지도 함께"),
            ("자음 하나 뒤 오른쪽 Option", "기호표 (ㄱ 문장부호, ㄷ 수학, ㅁ 도형 …)"),
            ("오른쪽 Option 두 번", "분류별 이모지 전체 창 (최근·표정·사람·동물 …)"),
            ("후보 고르기", "1–9 · ↑↓ 후 Space/Enter · ← → 쪽 넘김 · Esc 닫기 · 클릭"),
            ("이모지 창", "방향키 이동 · Tab 분류 · Space/Enter 넣기 · Esc 닫기 · 클릭"),
        ]),
        ("텍스트 단축어", [
            ("이름 + 오른쪽 Option", "후보 맨 위의 단축어를 고르면 내용으로 펼침"),
            ("기본 단축어", "날짜 · 시간 · 지금 · 오늘 · 내일 · 모레 · 어제 · 그제"),
            ("내용에 쓰는 값", "{날짜} {날짜:M월 d일} {시간} {요일} {클립보드} {커서}"),
            ("날짜 계산", "{날짜+1} {날짜-2} {요일+1} {날짜+1주} {날짜+1달} {날짜-1년}"),
            ("", "메뉴바 → 텍스트 단축어…에서 추가·수정·삭제. 맥 순정 '텍스트 대치'와는 따로 동작합니다(이름만 겹치지 않게)."),
        ]),
        ("클립보드 기록", [
            ("Ctrl + Option + V", "최근 복사한 것 20개에서 골라 넣기"),
            ("", "비밀번호 칸에서 복사한 것, 비밀번호 관리자가 '민감'으로 표시한 복사는 기록하지 않습니다. 기록은 이 맥 안에만 있고, 보관 시간은 메뉴에서 정합니다."),
        ]),
        ("앱별 설정 (메뉴바 메뉴)", [
            ("지금 앱을 터미널처럼 다루기", "한자·바로잡기가 글자를 엉뚱하게 바꾸는 앱에서 켜기 (iTerm2·터미널·Termix 등은 기본으로 켜져 있음)"),
            ("지금 앱에서는 순정 입력기 쓰기", "OG키보드와 맞지 않는 앱은 그 앱에 있을 때만 순정 입력기로 자동 전환, 벗어나면 OG키보드로 복귀"),
        ]),
        ("필요한 권한 (시스템 설정 → 개인정보 보호 및 보안)", [
            ("손쉬운 사용", "터미널에서 한자·바로잡기, 단축어의 {커서} 이동"),
            ("입력 모니터링", "Caps Lock 한/영 (누른 시간을 재기 위해)"),
            ("", "시스템 설정 → 키보드 → 입력 소스의 'Caps Lock으로 라틴 입력 소스 전환'은 꺼 두세요."),
        ]),
        ("문제가 생기면", [
            ("", "입력 메뉴에서 순정 ABC로 바꾸면 언제든 일반 입력으로 돌아갑니다."),
            ("", "특정 앱에서만 입력이 안 되면: 입력 소스에서 OG키보드 제거 → 다시 설치 → 로그아웃·로그인 → 다시 추가."),
        ]),
    ]

    func show() {
        let w = window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "OG키보드 사용법"
        w.isReleasedWhenClosed = false
        w.center()

        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 18, height: 16)
        tv.textStorage?.setAttributedString(content())
        w.contentView = scroll
        window = w
        return w
    }

    private func content() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let title = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let keyFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let body = NSFont.systemFont(ofSize: 13)

        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 4
        para.headIndent = 180
        para.tabStops = [NSTextTab(textAlignment: .left, location: 180)]
        let note = NSMutableParagraphStyle()
        note.paragraphSpacing = 4
        let head = NSMutableParagraphStyle()
        head.paragraphSpacingBefore = 14
        head.paragraphSpacing = 6

        for (i, (name, rows)) in sections.enumerated() {
            out.append(NSAttributedString(string: (i == 0 ? "" : "\n") + name + "\n",
                attributes: [.font: title, .foregroundColor: NSColor.labelColor, .paragraphStyle: head]))
            for (key, desc) in rows {
                if key.isEmpty {
                    out.append(NSAttributedString(string: desc + "\n",
                        attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: note]))
                } else {
                    out.append(NSAttributedString(string: key,
                        attributes: [.font: keyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]))
                    out.append(NSAttributedString(string: "\t" + desc + "\n",
                        attributes: [.font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]))
                }
            }
        }
        return out
    }

    // MARK: 정보

    func showAbout() {
        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "OG키보드 \(ver) (빌드 \(build))"
        alert.informativeText = """
        맥용 한글 입력기 — 세벌식 390·391·순아래, 두벌식

        개발자: JSLee
        문의: og.app.developer@gmail.com

        개인정보: 입력한 글자·클립보드 기록·설정은 이 맥 안에만 저장되며 어디로도 보내지 않습니다.

        포함한 오픈소스: libhangul 자판(LGPL-2.1), libhangul 한자 사전(BSD-3-Clause), Unicode CLDR(Unicode-3.0), emojibase(MIT)
        """
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "라이선스 보기")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let dir = Bundle.main.resourceURL?.appendingPathComponent("licenses") {
            NSWorkspace.shared.open(dir)
        }
    }
}
