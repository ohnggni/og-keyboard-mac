import Cocoa
import WebKit

/// 사용법 창과 정보 창 (Resources의 help.html / about.html을 웹 보기로 띄움, 다크 모드 자동)
final class HelpWindow: NSObject, WKNavigationDelegate {
    static let shared = HelpWindow()

    private var helpWindow: NSWindow?
    private var aboutWindow: NSWindow?

    func show() {
        let w = helpWindow ?? makeWindow(page: "help", title: "OG키보드 사용법", size: NSSize(width: 680, height: 760))
        helpWindow = w
        present(w)
    }

    func showAbout() {
        let w = aboutWindow ?? makeWindow(page: "about", title: "OG키보드 정보", size: NSSize(width: 420, height: 600))
        aboutWindow = w
        present(w)
    }

    private func present(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(page: String, title: String, size: NSSize) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = title
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.center()

        let web = WKWebView(frame: NSRect(origin: .zero, size: size))
        web.navigationDelegate = self
        web.loadHTMLString(html(page), baseURL: nil)
        w.contentView = web
        return w
    }

    /// html 파일을 읽고 {{VERSION}} {{BUILD}} {{ICON}}을 채운다
    private func html(_ page: String) -> String {
        guard let url = Bundle.main.url(forResource: page, withExtension: "html"),
              var s = try? String(contentsOf: url, encoding: .utf8) else {
            return "<p style='font-family:-apple-system;padding:20px'>\(page).html을 찾지 못했습니다.</p>"
        }
        let info = Bundle.main.infoDictionary
        s = s.replacingOccurrences(of: "{{VERSION}}", with: info?["CFBundleShortVersionString"] as? String ?? "?")
        s = s.replacingOccurrences(of: "{{BUILD}}", with: info?["CFBundleVersion"] as? String ?? "?")
        var icon = ""
        if let iu = Bundle.main.url(forResource: "help-icon", withExtension: "png"),
           let data = try? Data(contentsOf: iu) {
            icon = "data:image/png;base64," + data.base64EncodedString()
        }
        return s.replacingOccurrences(of: "{{ICON}}", with: icon)
    }

    /// 링크: og://licenses → 라이선스 폴더 열기, 그 밖의 링크(메일 등)는 기본 앱으로
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if url.scheme == "og" {
            if url.host == "licenses", let dir = Bundle.main.resourceURL?.appendingPathComponent("licenses") {
                NSWorkspace.shared.open(dir)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
