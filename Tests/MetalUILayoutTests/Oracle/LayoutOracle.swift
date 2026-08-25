import Foundation
import WebKit

/// One element's border box, as the browser reports it.
public struct NodeBox: Sendable, Equatable, Codable {
    public let id: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Lays out fixture HTML in WebKit and reads back every `[data-id]` box.
///
/// Runs headless inside `swift test` — no app bundle, no window, no run-loop
/// pumping. The navigation continuation is what makes that work.
@MainActor
public final class LayoutOracle: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    public init(viewport: CGSize) {
        webView = WKWebView(frame: CGRect(origin: .zero, size: viewport),
                            configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    public func measure(html: String) async throws -> [NodeBox] {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loaded = c
            webView.loadHTMLString(html, baseURL: nil)
        }

        let js = """
        (() => Array.from(document.querySelectorAll('[data-id]')).map(el => {
            const r = el.getBoundingClientRect();
            return { id: el.dataset.id, x: r.x, y: r.y, width: r.width, height: r.height };
        }))()
        """
        let raw = try await webView.evaluateJavaScript(js)
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.map { row in
            NodeBox(id: row["id"] as? String ?? "?",
                    x: row["x"] as? Double ?? .nan,
                    y: row["y"] as? Double ?? .nan,
                    width: row["width"] as? Double ?? .nan,
                    height: row["height"] as? Double ?? .nan)
        }
    }
}
