// WebView — az Arena chat motorja natív házban.
// A böngészőlap ellentétben itt az app kezeli az életciklust: előtérbe
// kerüléskor újracsatlakozik, nem dobja el a munkamenetet a rendszer.
import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // a bejelentkezés megmarad
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.071, alpha: 1)
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        // Újracsatlakozás, ha a lap elszállt volna (pl. memórianyomás után).
        if wv.url == nil { wv.load(URLRequest(url: url)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()   // a "böngésző egy idő múlva elhal" probléma ellenszere
        }
    }
}
