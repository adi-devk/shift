import SwiftUI
import WebKit

public struct BrowserView: View {
    @ObservedObject public var engine: ShiftDownloadEngine
    @StateObject public var tabManager = BrowserTabManager.shared
    @StateObject public var sniffer = ShiftMediaSniffer()

    @State private var addressBarText: String = ""
    @FocusState private var isAddressBarFocused: Bool
    @State private var isShowingTabOverview = false
    @State private var isShowingPageMenu = false
    @State private var isShowingBookmarks = false
    @State private var isShowingFindOnPage = false
    @State private var isShowingShareSheet = false
    @State private var shareURL: URL?

    public init(engine: ShiftDownloadEngine) {
        self.engine = engine
    }

    private var activeTab: BrowserTab {
        tabManager.activeTab ?? BrowserTab()
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // MARK: - Safari Address Bar
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            // aA Page Options Button
                            Button {
                                HapticManager.triggerImpact(.light)
                                isShowingPageMenu = true
                            } label: {
                                Image(systemName: "textformat.size")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 30, height: 30)
                            }

                            // Lock icon / Search
                            Image(systemName: activeTab.url.scheme == "https" ? "lock.fill" : "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            // Editable Address / Search Field
                            TextField("Search or enter website name", text: $addressBarText)
                                .shiftNoAutocapitalization()
                                .autocorrectionDisabled()
                                .focused($isAddressBarFocused)
                                .font(.system(size: 15))
                                .onSubmit {
                                    loadSubmittedURL()
                                }

                            if activeTab.isLoading {
                                Button {
                                    NotificationCenter.default.post(name: NSNotification.Name("SHIFT_WEB_STOP"), object: nil)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(4)
                                }
                            } else if isAddressBarFocused && !addressBarText.isEmpty {
                                Button {
                                    addressBarText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Button {
                                    NotificationCenter.default.post(name: NSNotification.Name("SHIFT_WEB_RELOAD"), object: nil)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .padding(4)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(tabManager.isPrivateMode ? Color.gray.opacity(0.3) : Color.tertiarySystemFillColor)
                        .cornerRadius(12)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)

                        // Safari Animated Loading Progress Bar
                        if activeTab.isLoading {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.clear)
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: tabManager.isPrivateMode ? [.purple, .indigo] : [.blue, .cyan],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(12, geometry.size.width * CGFloat(activeTab.estimatedProgress)))
                                        .animation(.easeInOut(duration: 0.2), value: activeTab.estimatedProgress)
                                }
                            }
                            .frame(height: 2.5)
                        } else {
                            Divider()
                        }
                    }
                    .background(.ultraThinMaterial)

                    // MARK: - Multi-Tab WebKit Container
                    WebViewWrapper(
                        tab: activeTab,
                        sniffer: sniffer,
                        tabManager: tabManager,
                        onURLChange: { newURL in
                            self.addressBarText = newURL.absoluteString
                        }
                    )

                    Divider()

                    // MARK: - Safari Bottom Toolbar
                    HStack(spacing: 0) {
                        // Back Button
                        Button {
                            HapticManager.triggerImpact(.light)
                            NotificationCenter.default.post(name: NSNotification.Name("SHIFT_WEB_BACK"), object: nil)
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 18, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!activeTab.canGoBack)

                        // Forward Button
                        Button {
                            HapticManager.triggerImpact(.light)
                            NotificationCenter.default.post(name: NSNotification.Name("SHIFT_WEB_FORWARD"), object: nil)
                        } label: {
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 18, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!activeTab.canGoForward)

                        // Share Button
                        Button {
                            HapticManager.triggerImpact(.light)
                            self.shareURL = activeTab.url
                            self.isShowingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity)
                        }

                        // Bookmarks Button
                        Button {
                            HapticManager.triggerImpact(.light)
                            self.isShowingBookmarks = true
                        } label: {
                            Image(systemName: "book")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity)
                        }

                        // Safari Tab Switcher Button [ N ]
                        Button {
                            HapticManager.triggerImpact(.medium)
                            self.isShowingTabOverview = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(tabManager.isPrivateMode ? Color.purple : Color.blue, lineWidth: 1.8)
                                    .frame(width: 22, height: 22)

                                Text("\(tabManager.currentTabs.count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(tabManager.isPrivateMode ? .purple : .blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .contextMenu {
                            Button {
                                tabManager.createNewTab(isPrivate: false, makeActive: true)
                            } label: {
                                Label("New Tab", systemImage: "plus")
                            }

                            Button {
                                tabManager.createNewTab(isPrivate: true, makeActive: true)
                            } label: {
                                Label("New Private Tab", systemImage: "lock.shield")
                            }

                            Button(role: .destructive) {
                                tabManager.closeTab(id: activeTab.id)
                            } label: {
                                Label("Close This Tab", systemImage: "xmark")
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(tabManager.isPrivateMode ? Color.black.opacity(0.85) : Color.secondaryGroupedBg)
                }

                // MARK: - In-Page Search Overlay
                if isShowingFindOnPage {
                    FindOnPageView(
                        isPresented: $isShowingFindOnPage,
                        onFindText: { query, forward in
                            NotificationCenter.default.post(
                                name: NSNotification.Name("SHIFT_WEB_FIND"),
                                object: nil,
                                userInfo: ["query": query, "forward": forward]
                            )
                        },
                        onDismiss: {
                            NotificationCenter.default.post(name: NSNotification.Name("SHIFT_WEB_FIND_DISMISS"), object: nil)
                        }
                    )
                }

                // Floating Media Sniffer HUD
                SnifferHUDView(sniffer: sniffer, engine: engine)
                    .padding(.bottom, isShowingFindOnPage ? 110 : 64)
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .sheet(isPresented: $isShowingTabOverview) {
                BrowserTabOverviewView(
                    tabManager: tabManager,
                    onSelectTab: { tabId in
                        tabManager.selectTab(id: tabId)
                        self.addressBarText = tabManager.activeTab?.url.absoluteString ?? ""
                    },
                    onNewTab: {
                        tabManager.createNewTab(makeActive: true)
                        self.addressBarText = tabManager.activeTab?.url.absoluteString ?? ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.isAddressBarFocused = true
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingPageMenu) {
                BrowserPageMenuView(
                    tabManager: tabManager,
                    tab: activeTab,
                    onFindOnPage: {
                        self.isShowingFindOnPage = true
                    },
                    onReload: {
                        NotificationCenter.default.post(name: NSNotification.Name("SHIFT_WEB_RELOAD"), object: nil)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingBookmarks) {
                BookmarksHistoryView(tabManager: tabManager) { selectedURL in
                    tabManager.updateTabState(id: activeTab.id, url: selectedURL, urlString: selectedURL.absoluteString)
                    self.addressBarText = selectedURL.absoluteString
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let url = shareURL {
                    #if canImport(UIKit)
                    ShareSheet(activityItems: [url])
                    #else
                    Text("Share \(url.absoluteString)")
                    #endif
                }
            }
            .onAppear {
                if addressBarText.isEmpty {
                    addressBarText = activeTab.url.absoluteString
                }
            }
            .onChange(of: tabManager.currentActiveTabId) { _ in
                addressBarText = activeTab.url.absoluteString
            }
        }
    }

    private func loadSubmittedURL() {
        isAddressBarFocused = false
        let trimmed = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL: URL
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            targetURL = URL(string: trimmed) ?? URL(string: "https://duckduckgo.com")!
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            targetURL = URL(string: "https://" + trimmed) ?? URL(string: "https://duckduckgo.com")!
        } else {
            targetURL = engine.settings.defaultSearchEngine.searchURL(for: trimmed) ?? URL(string: "https://duckduckgo.com/?q=\(trimmed)")!
        }

        tabManager.updateTabState(id: activeTab.id, url: targetURL, urlString: targetURL.absoluteString)
        NotificationCenter.default.post(
            name: NSNotification.Name("SHIFT_WEB_LOAD_URL"),
            object: nil,
            userInfo: ["url": targetURL]
        )
    }
}

// MARK: - Multi-Platform WKWebView Wrapper

#if canImport(UIKit)
public struct WebViewWrapper: UIViewRepresentable {
    public let tab: BrowserTab
    public let sniffer: ShiftMediaSniffer
    @ObservedObject public var tabManager: BrowserTabManager
    public let onURLChange: (URL) -> Void

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Sniffer user script
        let userScript = WKUserScript(
            source: ShiftMediaSniffer.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)
        contentController.add(sniffer, name: ShiftMediaSniffer.messageHandlerName)

        // Ad & Tracker blocker
        ContentBlocker.shared.compileRuleList { ruleList in
            if let list = ruleList { contentController.add(list) }
        }

        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Private browsing isolation
        if tab.isPrivate {
            config.websiteDataStore = .nonPersistent()
        } else {
            config.websiteDataStore = .default()
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.setup(webView: webView)

        let request = URLRequest(url: tab.url)
        webView.load(request)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self

        // Apply custom desktop / mobile User Agent
        if tab.isDesktopMode {
            uiView.customUserAgent = UserAgentPreset.desktopMac.userAgentString
        } else {
            uiView.customUserAgent = nil
        }

        // Apply page zoom
        uiView.pageZoom = CGFloat(tab.pageZoom)

        // If active tab URL changed externally (e.g. from Bookmark or Address Bar)
        if let current = uiView.url, current != tab.url && !tab.isLoading {
            let request = URLRequest(url: tab.url)
            uiView.load(request)
        }
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewWrapper
        weak var webView: WKWebView?
        private var progressObservation: NSKeyValueObservation?

        init(_ parent: WebViewWrapper) { self.parent = parent }

        func setup(webView: WKWebView) {
            self.webView = webView

            // Track estimated loading progress
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.tabManager.updateTabState(
                        id: self.parent.tab.id,
                        estimatedProgress: wv.estimatedProgress
                    )
                }
            }

            // Notification Observers
            NotificationCenter.default.addObserver(forName: NSNotification.Name("SHIFT_WEB_BACK"), object: nil, queue: .main) { [weak webView] _ in
                webView?.goBack()
            }
            NotificationCenter.default.addObserver(forName: NSNotification.Name("SHIFT_WEB_FORWARD"), object: nil, queue: .main) { [weak webView] _ in
                webView?.goForward()
            }
            NotificationCenter.default.addObserver(forName: NSNotification.Name("SHIFT_WEB_RELOAD"), object: nil, queue: .main) { [weak webView] _ in
                webView?.reload()
            }
            NotificationCenter.default.addObserver(forName: NSNotification.Name("SHIFT_WEB_STOP"), object: nil, queue: .main) { [weak webView] _ in
                webView?.stopLoading()
            }
            NotificationCenter.default.addObserver(forName: NSNotification.Name("SHIFT_WEB_LOAD_URL"), object: nil, queue: .main) { [weak webView] note in
                if let url = note.userInfo?["url"] as? URL {
                    webView?.load(URLRequest(url: url))
                }
            }
            NotificationCenter.default.addObserver(forName: NSNotification.Name("SHIFT_WEB_FIND"), object: nil, queue: .main) { [weak webView] note in
                guard let webView = webView,
                      let query = note.userInfo?["query"] as? String,
                      let forward = note.userInfo?["forward"] as? Bool else { return }
                
                if #available(iOS 16.0, *) {
                    let findConfig = WKFindConfiguration()
                    findConfig.backwards = !forward
                    findConfig.caseSensitive = false
                    findConfig.wraps = true
                    webView.find(query, configuration: findConfig) { _ in }
                }
            }
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.tabManager.updateTabState(
                    id: self.parent.tab.id,
                    isLoading: true,
                    estimatedProgress: 0.1
                )
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                let currentURL = webView.url ?? self.parent.tab.url
                let pageTitle = webView.title ?? ""

                self.parent.tabManager.updateTabState(
                    id: self.parent.tab.id,
                    title: pageTitle,
                    url: currentURL,
                    urlString: currentURL.absoluteString,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward,
                    isLoading: false,
                    estimatedProgress: 1.0
                )
                self.parent.tabManager.recordHistory(title: pageTitle, url: currentURL)
                self.parent.onURLChange(currentURL)
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.tabManager.updateTabState(
                    id: self.parent.tab.id,
                    isLoading: false
                )
            }
        }

        // Support opening links targeted with _blank in the same view
        public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
#elseif canImport(AppKit)
public struct WebViewWrapper: NSViewRepresentable {
    public let tab: BrowserTab
    public let sniffer: ShiftMediaSniffer
    @ObservedObject public var tabManager: BrowserTabManager
    public let onURLChange: (URL) -> Void

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        let userScript = WKUserScript(
            source: ShiftMediaSniffer.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)
        contentController.add(sniffer, name: ShiftMediaSniffer.messageHandlerName)

        ContentBlocker.shared.compileRuleList { ruleList in
            if let list = ruleList { contentController.add(list) }
        }

        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        let request = URLRequest(url: tab.url)
        webView.load(request)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if let current = nsView.url, current != tab.url && !tab.isLoading {
            nsView.load(URLRequest(url: tab.url))
        }
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWrapper
        init(_ parent: WebViewWrapper) { self.parent = parent }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let currentURL = webView.url {
                parent.onURLChange(currentURL)
            }
        }
    }
}
#endif
