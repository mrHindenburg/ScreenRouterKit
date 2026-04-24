import SwiftUI
internal import WebKit
import Combine

enum SRKNavAction {
    case none
    case home
    case back
    case forward
    case reload
}

final class SRKNavigationState: ObservableObject {

    @Published var canGoBack    = false
    @Published var canGoForward = false
    @Published var isLoading    = false
    @Published var lastError: URLError?
    @Published var navAction: SRKNavAction = .none

    weak var webView: WKWebView?
    var homeRequest: URLRequest?
}
