import Cocoa

/// 한/영 전환 시 화면 아래 가운데에 잠깐 뜨는 팝업 (안드판과 같은 색: 파란 '가', 초록 'a')
final class ModeIndicator {
    static let shared = ModeIndicator()

    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideWork: DispatchWorkItem?
    /// 연타 대비: 앞선 페이드아웃이 끝나며 새 팝업을 숨기지 않도록 세대 번호로 구분
    private var generation = 0
    private let size: CGFloat = 64

    func show(hangul: Bool) {
        display(hangul ? "가" : "a", color: hangul
            ? NSColor(srgbRed: 0.10, green: 0.45, blue: 0.91, alpha: 0.92)
            : NSColor(srgbRed: 0.13, green: 0.59, blue: 0.33, alpha: 0.92))
    }

    /// 대문자 고정 (안드판과 같은 주황 'A')
    func showCaps() {
        display("A", color: NSColor(srgbRed: 0.93, green: 0.49, blue: 0.13, alpha: 0.92))
    }

    /// 짧은 알림 (예: 한자 후보 없음 → 漢)
    func showMark(_ text: String) {
        display(text, color: NSColor(white: 0.35, alpha: 0.92))
    }

    private func display(_ text: String, color: NSColor) {
        let panel = self.panel ?? makePanel()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size / 2, y: f.minY + 80, width: size, height: size), display: false)

        label?.stringValue = text
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
        v.layer?.cornerRadius = 14

        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 32, weight: .bold)
        l.textColor = .white
        l.alignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])

        p.contentView = v
        panel = p
        label = l
        return p
    }
}
