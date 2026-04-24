import SwiftUI
import Combine
internal import WebKit

struct SRKWebView: UIViewRepresentable {

    let urlString: String
    @ObservedObject var navState: SRKNavigationState

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate         = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = RTSConstants.userAgent

        navState.webView = webView

        subscribeToNavActions(webView: webView, context: context)

        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            context.coordinator.homeRequest = request
            navState.homeRequest = request
            webView.load(request)
            SRKLogger.log(.debug, "WebView: load \(urlString)")
        } else {
            SRKLogger.log(.error, "WebView: invalid URL — \(urlString)")
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        config.userContentController.addUserScript(
            WKUserScript(
                source: RTSConstants.injectedScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        config.websiteDataStore = WKWebsiteDataStore.default()

        return config
    }

    private func subscribeToNavActions(webView: WKWebView, context: Context) {
        navState.$navAction
            .receive(on: RunLoop.main)
            .sink { [weak webView] action in
                guard let webView else { return }
                switch action {
                case .back:
                    if webView.canGoBack { webView.goBack() }
                case .forward:
                    if webView.canGoForward { webView.goForward() }
                case .home:
                    if let request = context.coordinator.homeRequest {
                        webView.load(request)
                    }
                case .reload:
                    webView.reload()
                case .none:
                    break
                }
            }
            .store(in: &context.coordinator.cancellables)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        var parent: SRKWebView
        var cancellables = Set<AnyCancellable>()
        var homeRequest: URLRequest?

        private var suppressSpinner = false

        init(_ parent: SRKWebView) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            suppressSpinner = (navigationAction.navigationType == .backForward)

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let urlString = url.absoluteString
            if urlString.contains("accounts.google.com")
                || urlString.contains("oauth2")
                || urlString.contains("google.com/signin") {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }

            let urlString = url.absoluteString
            if urlString.contains("accounts.google.com") || urlString.contains("oauth2") {
                webView.load(URLRequest(url: url))
            } else {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            completionHandler(defaultText)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if !suppressSpinner {
                DispatchQueue.main.async {
                    self.parent.navState.isLoading = true
                    self.parent.navState.lastError = nil
                }
            }
            updateNavButtons(webView)
            SRKLogger.log(.debug, "WebView: didStart — \(webView.url?.absoluteString ?? "")")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateNavButtons(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.navState.isLoading = false
                self.parent.navState.lastError = nil
            }
            suppressSpinner = false
            updateNavButtons(webView)
            SRKLogger.log(.debug, "WebView: didFinish — \(webView.url?.absoluteString ?? "")")
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handleError(error, webView: webView)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            handleError(error, webView: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            SRKLogger.log(.warning, "WebView: process terminated — reload")
            if webView.url != nil { webView.reload() }
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }

        private func handleError(_ error: Error, webView: WKWebView) {
            let ns = error as NSError

            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }

            if let failURL = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
               failURL.host?.contains("onesignal.com") == true { return }

            SRKLogger.log(.error, "WebView: error — \(error.localizedDescription)")

            DispatchQueue.main.async {
                self.parent.navState.isLoading = false
                self.parent.navState.lastError = error as? URLError
            }
            suppressSpinner = false
            updateNavButtons(webView)
        }

        private func updateNavButtons(_ webView: WKWebView) {
            DispatchQueue.main.async {
                self.parent.navState.canGoBack    = webView.canGoBack
                self.parent.navState.canGoForward = webView.canGoForward
            }
        }
    }
}

enum RTSConstants {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static let injectedScript = """
    Object.defineProperty(navigator, 'userAgent', {
        get: function () { return '\(userAgent)'; }
    });

    window.chrome = { runtime: {} };

    window.open = function(url, name, specs) {
        window.location.href = url;
        return window;
    };

    document.createElement = (function() {
        var original = document.createElement.bind(document);
        return function(tag) {
            var el = original(tag);
            if (tag === 'iframe') {
                el.setAttribute('sandbox',
                    'allow-same-origin allow-scripts allow-forms allow-popups allow-modals');
            }
            return el;
        };
    })();
    """
}
