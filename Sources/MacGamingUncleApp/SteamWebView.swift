import AppKit
import SwiftUI
import WebKit

@MainActor
final class SteamWebSession: ObservableObject {
    let homeURL: URL
    let webView: WKWebView
    @Published private(set) var title = "Steam"
    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false

    init(homeURL: URL) {
        self.homeURL = homeURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "MacGamingUncle/0.1 SteamShell"
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        load(homeURL)
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goHome() { load(homeURL) }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }

    fileprivate func update() {
        title = webView.title ?? "Steam"
        currentURL = webView.url
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }
}

struct SteamBrowserView: View {
    @EnvironmentObject private var model: MacGamingUncleAppModel
    @ObservedObject var session: SteamWebSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: session.goBack) { Image(systemName: "chevron.left") }
                    .disabled(!session.canGoBack)
                Button(action: session.goForward) { Image(systemName: "chevron.right") }
                    .disabled(!session.canGoForward)
                Button(action: session.goHome) { Image(systemName: "house") }
                Button(action: session.reload) { Image(systemName: "arrow.clockwise") }
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(IndiePalette.green)
                    Text(session.currentURL?.host ?? "store.steampowered.com")
                        .lineLimit(1).font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                if session.isLoading { ProgressView().controlSize(.small) }
                Button("在浏览器打开", systemImage: "safari") {
                    if let url = session.currentURL { NSWorkspace.shared.open(url) }
                }
                .labelStyle(.iconOnly).help("在默认浏览器打开")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).frame(height: 48)
            .background(IndiePalette.sidebar.opacity(0.96))
            Divider().overlay(IndiePalette.border)
            SteamWebRepresentable(session: session) { model.handleSteamWebURL($0) }
        }
    }
}

private struct SteamWebRepresentable: NSViewRepresentable {
    let session: SteamWebSession
    let onSteamURL: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(session: session, onSteamURL: onSteamURL) }

    func makeNSView(context: Context) -> WKWebView {
        session.webView.navigationDelegate = context.coordinator
        session.webView.uiDelegate = context.coordinator
        return session.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onSteamURL = onSteamURL
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var session: SteamWebSession?
        var onSteamURL: (URL) -> Void

        init(session: SteamWebSession, onSteamURL: @escaping (URL) -> Void) {
            self.session = session
            self.onSteamURL = onSteamURL
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { session?.update() }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { session?.update() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { session?.update() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { session?.update() }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme?.lowercased() == "steam" {
                onSteamURL(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}
