import Foundation
import WebKit

/// MainActor registry of live web views. It gives privacy/profile-cycle code
/// one safe place to halt every WebKit surface before data-store removal starts.
@MainActor
final class WebViewLifecycleRegistry {
    static let shared = WebViewLifecycleRegistry()

    private let webViews = NSHashTable<WKWebView>.weakObjects()

    private init() {}

    func register(_ webView: WKWebView) {
        webViews.add(webView)
    }

    func unregister(_ webView: WKWebView) {
        webViews.remove(webView)
    }

    func stopAllForProfileCycle() {
        for case let webView as WKWebView in webViews.allObjects {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        webViews.removeAllObjects()
    }
}

/// Avoids WKUserContentController strongly retaining SwiftUI coordinators.
/// Without this proxy, each web view can keep its coordinator, model, and tab
/// alive after a tab is closed.
final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
