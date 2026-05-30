import SwiftUI

// MARK: - Preview Wrapper

struct SRKWebView_Preview: View {

    @State private var selectedURL = PreviewURL.google
    @State private var id = UUID()

    var body: some View {
        VStack(spacing: 0) {
            Picker("URL", selection: $selectedURL) {
                ForEach(PreviewURL.allCases) { url in
                    Text(url.label).tag(url)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            Divider()

            SRKWebContainerView(url: selectedURL.rawValue)
                .id(id)
        }
        .onChange(of: selectedURL) { _, _ in
            id = UUID()
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Preview URLs

enum PreviewURL: String, CaseIterable, Identifiable {
    case google   = "https://google.com"
    case apple    = "https://apple.com"
    case github   = "https://github.com"
    case youtube  = "https://youtube.com"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .google:  return "Google"
        case .apple:   return "Apple"
        case .github:  return "GitHub"
        case .youtube: return "YouTube"
        }
    }
}

// MARK: - Navigation State Preview

struct SRKNavigationDebugView: View {

    @StateObject private var navState = SRKNavigationState()

    var body: some View {
        VStack(spacing: 0) {

            // State badge row
            HStack(spacing: 16) {
                badge("canGoBack",    value: navState.canGoBack,    color: .blue)
                badge("canGoForward", value: navState.canGoForward, color: .blue)
                badge("isLoading",    value: navState.isLoading,    color: .orange)
                if navState.lastError != nil {
                    Text("error")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))

            Divider()

            // WebView
            SRKWebView(urlString: "https://google.com", navState: navState)
                .ignoresSafeArea(edges: .bottom)

            HStack(spacing: 32) {
                navBtn("chevron.backward") { navState.navAction = .back }
                    .disabled(!navState.canGoBack)
                navBtn("house.fill") { navState.navAction = .home }
                navBtn("arrow.clockwise") { navState.navAction = .reload }
                navBtn("chevron.forward") { navState.navAction = .forward }
                    .disabled(!navState.canGoForward)
            }
            .padding(.top)
            .background(Color(.systemBackground))
        }
    }

    private func badge(_ label: String, value: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(value ? color : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(value ? color : .secondary)
        }
    }

    private func navBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Previews

#Preview("WebView + Navigation Toolbar") {
    SRKWebView_Preview()
}

#Preview("Navigation State Debug") {
    SRKNavigationDebugView()
}

#Preview("WebView — Google OAuth flow") {
    // Tests that Google sign-in stays inside WebView (not Safari)
    SRKWebContainerView(url: "https://accounts.google.com")
}

#Preview("WebView — YouTube") {
    SRKWebContainerView(url: "https://youtube.com")
}
