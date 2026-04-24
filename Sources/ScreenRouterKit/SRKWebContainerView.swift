import SwiftUI
import Combine
import Network
internal import WebKit

struct SRKWebContainerView: View {

    @Environment(\.colorScheme) private var colorScheme

    let url: String

    @StateObject private var navState     = SRKNavigationState()
    @StateObject private var connectivity = RTSConnectivityMonitor()

    @State private var showAlert    = false
    @State private var alertMessage = ""

    var body: some View {
        ZStack(alignment: .center) {
            VStack {
                SRKWebView(urlString: url, navState: navState)
                    .ignoresSafeArea()
                    .onAppear {
                        navState.lastError = nil
                        showAlert = false
                    }

                navigationToolbar
            }

            if navState.isLoading {
                ProgressView()
                    .scaleEffect(1.4)
                    .padding(16)
                    .background(.regularMaterial)
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

    private var navigationToolbar: some View {
        HStack {
            arrowButton(icon: "chevron.backward", isActive: navState.canGoBack) {
                navState.navAction = .back
            }

            Spacer()

            homeButton {
                navState.navAction = .home
            }

            Spacer()

            arrowButton(icon: "chevron.forward", isActive: navState.canGoForward) {
                navState.navAction = .forward
            }
        }
        .padding(.horizontal, 25)
        .padding(.bottom, 5)
    }

    private func arrowButton(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isActive
                    ? (colorScheme == .dark ? .white : .black)
                    : .gray)
        }
        .disabled(!isActive)
        .buttonStyle(RTSScaleButtonStyle())
    }

    private func homeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.title2)
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
        .buttonStyle(RTSScaleButtonStyle())
    }

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

struct RTSScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.18 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

final class RTSConnectivityMonitor: ObservableObject {
    @Published private(set) var connected = true

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "wbc.connectivity")

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
