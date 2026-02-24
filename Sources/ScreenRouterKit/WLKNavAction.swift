// WLKNavigationState.swift
// ScreenRouterKit

import SwiftUI
@preconcurrency import WebKit
import Combine

// MARK: - Navigation Action

enum WLKNavAction {
    case none
    case home
    case back
    case forward
    case reload
}

// MARK: - Navigation State

/// Stores WKWebView state and navigation commands.
/// Acts as a bridge between SwiftUI and WKWebView.
final class WLKNavigationState: ObservableObject {

    // Navigation buttons
    @Published var canGoBack    = false
    @Published var canGoForward = false

    // Show spinner over WebView while loading
    @Published var isLoading    = false

    // Last URL error
    @Published var lastError: URLError?

    // Navigation command — WKWebView observes via Combine
    @Published var navAction: WLKNavAction = .none

    // Weak ref to WKWebView (set from WLKWebView.makeUIView)
    weak var webView: WKWebView?

    // Saved home request for returning to the initial URL
    var homeRequest: URLRequest?
}
