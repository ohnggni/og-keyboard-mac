import Cocoa

/// 한/영 전환 시 화면 아래 가운데에 잠깐 뜨는 팝업 (안드판과 같은 색: 파란 '가', 초록 'a', 주황 'A')
/// 큰 글자 아래에 작은 설명(한글·영문·대문자)을 함께 보여준다.
final class ModeIndicator {
    static let shared = ModeIndicator()

    private var panel: NSPanel?
    private var label: NSTextField?
    private var caption: NSTextField?
    private var hideWork: DispatchWorkItem?
    /// 연타 대비: 앞선 페이드아웃이 끝나며 새 팝업을 숨기지 않도록 세대 번호로 구분
    private var generation = 0
    private let size: CGFloat = 76

    static let blue = NSColor(srgbRed: 0.15, green: 0.39, blue: 0.92, alpha: 0.94)
    static let green = NSColor(srgbRed: 0.09, green: 0.55, blue: 0.33, alpha: 0.94)
    static let orange = NSColor(srgbRed: 0.92, green: 0.45, blue: 0.10, alpha: 0.94)

    func show(hangul: Bool) {
        display(hangul ? "가" : "a", caption: hangul ? "한글" : "영문",
                color: hangul ? Self.blue : Self.green)
    }

    /// 대문자 고정
    func showCaps() {
        display("A", caption: "대문자", color: Self.orange)
    }

    /// 짧은 알림 (예: 한자 후보 없음 → 漢)
    func showMark(_ text: String) {
        display(text, caption: "", color: NSColor(white: 0.3, alpha: 0.92))
    }

    private func display(_ text: String, caption sub: String, color: NSColor) {
        let panel = self.panel ?? makePanel()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size / 2, y: f.minY + 80, width: size, height: size), display: false)

        label?.stringValue = text
        caption?.stringValue = sub
        caption?.isHidden = sub.isEmpty
        panel.contentView?.layer?.backgroundColor = color.cgColor

        hideWork?.cancel()
        generation += 1
        let gen = generation
        // 진행 중인 페이드아웃을 즉시 끊고 불투명으로
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self, weak panel] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                panel?.animator().alphaValue = 0
            }, completionHandler: {
                if self?.generation == gen { panel?.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let v = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true
        v.layer?.cornerRadius = 18
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor(white: 1, alpha: 0.18).cgColor

        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 32, weight: .bold)
        l.textColor = .white
        l.alignment = .center

        let c = NSTextField(labelWithString: "")
        c.font = .systemFont(ofSize: 11, weight: .medium)
        c.textColor = NSColor(white: 1, alpha: 0.85)
        c.alignment = .center

        let stack = NSStackView(views: [l, c])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])

        p.contentView = v
        panel = p
        label = l
        caption = c
        return p
    }
}
