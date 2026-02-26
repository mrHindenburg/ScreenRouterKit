// SRKWebContainerView.swift
// ScreenRouterKit

import SwiftUI
import Combine
import Network

// MARK: - Web Container View

struct SRKWebContainerView: View {

    @Environment(\.colorScheme) private var colorScheme

    let url: String

    @StateObject private var navState    = SRKNavigationState()
    @StateObject private var connectivity = SRKConnectivityMonitor()

    @State private var showAlert    = false
    @State private var alertMessage = ""

    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── WebView ───────────────────────────────────────────────
                SRKWebView(urlString: url, navState: navState)
                    .ignoresSafeArea(edges: .bottom)
                    .onAppear {
                        navState.lastError = nil
                        showAlert = false
                    }

                // ── Navigation Toolbar ────────────────────────────────────
                navigationToolbar
            }

            // ── Loading Spinner ───────────────────────────────────────────
            if navState.isLoading {
                ProgressView()
                    .scaleEffect(1.4)
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .onReceive(navState.$lastError) { error in
            guard let error, isSignificantError(error) else { return }
            alertMessage = humanReadable(error)
            showAlert = true
        }
        .onReceive(
            connectivity.$connected
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { connected in
            if !connected {
                alertMessage = "No Internet connection. Please check your network and try again."
                showAlert = true
            } else if navState.lastError != nil {
                navState.lastError = nil
                reloadOrLoad()
            }
        }
        .alert("Connection issue", isPresented: $showAlert) {
            Button("Try again") {
                if connectivity.connected { reloadOrLoad() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Navigation Toolbar

    private var navigationToolbar: some View {
        HStack {
            // Back
            navButton(icon: "chevron.backward", size: 20) {
                navState.navAction = .back
            }
            .disabled(!navState.canGoBack)
            .opacity(navState.canGoBack ? 1 : 0.5)

            Spacer()

            // Home
            navButton(icon: "house.fill", size: 25) {
                navState.navAction = .home
            }

            Spacer()

            // Forward
            navButton(icon: "chevron.forward", size: 20) {
                navState.navAction = .forward
            }
            .disabled(!navState.canGoForward)
            .opacity(navState.canGoForward ? 1 : 0.5)
        }
        .padding(.top, 10)
        .padding(.horizontal, 25)
        .padding(.bottom, 5)
        .background(Color(colorScheme == .dark ? .black : .white))
    }

    private func navButton(
        icon: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    // MARK: - Private

    private func reloadOrLoad() {
        guard let webView = navState.webView else { return }
        if webView.url == nil, let request = navState.homeRequest {
            webView.load(request)
        } else {
            webView.reload()
        }
    }

    private func isSignificantError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func humanReadable(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "No Internet connection."
        case .timedOut:               return "Request timed out."
        case .cannotFindHost:         return "Cannot find host."
        case .cannotConnectToHost:    return "Cannot connect to host."
        case .dnsLookupFailed:        return "DNS lookup failed."
        default:                      return error.localizedDescription
        }
    }
}

// MARK: - Connectivity Monitor

final class SRKConnectivityMonitor: ObservableObject {
    @Published private(set) var connected = true

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "srk.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.connected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
