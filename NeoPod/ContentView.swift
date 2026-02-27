// ContentView.swift
//
//  ContentView.swift
//  NeoPod
//
//  Created by Danniel Yu on 2/14/R8.
//

import SwiftUI
import CoreData
import WebKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>
    
    @ObservedObject private var playerModel = MusicPlayerModel.shared
    
    private enum MenuDestination {
        case home
        case music
        case video
        case store
        case setting
        case programs
    }
    
    private struct MenuItem: Identifiable {
        let id = UUID()
        let title: String
        let iconName: String
        let destination: MenuDestination
    }
    
    private let listitem = [
        MenuItem(title: "music", iconName: "music.note", destination: .music),
        MenuItem(title: "video", iconName: "play.rectangle", destination: .video),
        MenuItem(title: "store", iconName: "app.badge", destination: .store),
        MenuItem(title: "setting", iconName: "gearshape", destination: .setting),
        MenuItem(title: "programs", iconName: "terminal", destination: .programs)
    ]
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    @State private var currentPage: MenuDestination = .home
    @State private var isForwardNavigation = true
    @State private var musicIsShowingPlayer = false
    @State private var videoIsShowingPlayer = false
    
    // Dev 页面专属状态
    @State private var devSelectedFile: HTMLFileInfo? = nil
    
    // 计算是否正在显示 HTML 预览
    private var isShowingHTML: Bool {
        devSelectedFile != nil
    }
    
    // 计算是否正在显示视频播放器（全屏模式）
    private var isShowingVideoPlayer: Bool {
        currentPage == .video && videoIsShowingPlayer
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZuneBackground()
                
                if isShowingVideoPlayer {
                    destinationView(for: .video)
                        .ignoresSafeArea(.all)
                } else {
                    VStack(spacing: 20) {
                        if !isShowingHTML {
                            ZuneTopBar(
                                title: titleForPage(currentPage),
                                accent: accent,
                                showsBack: currentPage != .home,
                                onBack: {
                                    if currentPage == .music, musicIsShowingPlayer {
                                        withAnimation(.easeOut(duration: 0.28)) {
                                            musicIsShowingPlayer = false
                                        }
                                        return
                                    }
                                    
                                    if currentPage == .video, videoIsShowingPlayer {
                                        withAnimation(.easeOut(duration: 0.28)) {
                                            videoIsShowingPlayer = false
                                        }
                                        return
                                    }
                                    
                                    isForwardNavigation = false
                                    withAnimation(.easeOut(duration: 0.28)) {
                                        currentPage = .home
                                    }
                                }
                            )
                            .overlay(alignment: .trailing) {
                                if playerModel.currentItem != nil {
                                    Button {
                                        navigateToNowPlaying()
                                    } label: {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(accent)
                                            .padding(8)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.opacity)
                                }
                            }
                        }
                        
                        contentArea
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, isShowingHTML ? 0 : 80)
                    
                    if let file = devSelectedFile {
                        HTMLPreviewOverlay(file: file, onClose: {
                            withAnimation(.easeOut(duration: 0.28)) {
                                devSelectedFile = nil
                            }
                        })
                        .transition(.opacity)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundColor(.white)
        .statusBarHidden(isShowingHTML || isShowingVideoPlayer)
        .edgesIgnoringSafeArea(.all)
    }
    
    private var contentArea: some View {
        ZStack {
            if currentPage == .home {
                menuList
                    .zIndex(0)
                    .transition(pageTransition)
            } else {
                destinationView(for: currentPage)
                    .zIndex(1)
                    .transition(pageTransition)
            }
        }
        .clipped()
    }
    
    private var menuList: some View {
        GeometryReader { menuProxy in
            let containerMidY = menuProxy.size.height / 2
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ForEach(listitem) { item in
                        Button {
                            isForwardNavigation = true
                            withAnimation(.easeOut(duration: 0.28)) {
                                currentPage = item.destination
                            }
                        } label: {
                            ZuneMenuRow(
                                title: item.title,
                                iconName: item.iconName,
                                accent: accent,
                                containerMidY: containerMidY
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .coordinateSpace(name: "menuScroll")
        }
    }
    
    @ViewBuilder
    private func destinationView(for destination: MenuDestination) -> some View {
        switch destination {
        case .home:
            EmptyView()
        case .music:
            MusicView(isShowingPlayer: $musicIsShowingPlayer)
        case .video:
            VideoView(isShowingPlayer: $videoIsShowingPlayer)
        case .store:
            StoreView()
        case .setting:
            SettingView()
        case .programs:
            ProgramsView(onFileSelected: { file in
                withAnimation(.easeOut(duration: 0.28)) {
                    devSelectedFile = file
                }
            })
        }
    }
    
    private func titleForPage(_ destination: MenuDestination) -> String {
        switch destination {
        case .home:
            return "HOME"
        case .music:
            return "MUSIC"
        case .video:
            return "VIDEO"
        case .store:
            return "STORE"
        case .setting:
            return "SETTING"
        case .programs:
            return "PROGRAMS"
        }
    }
    
    private var pageTransition: AnyTransition {
        if isForwardNavigation {
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }
    
    private func navigateToNowPlaying() {
        withAnimation(.easeOut(duration: 0.28)) {
            isForwardNavigation = true
            currentPage = .music
            musicIsShowingPlayer = true
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// MARK: - HTMLPreviewOverlay

struct HTMLPreviewOverlay: View {
    let file: HTMLFileInfo
    let onClose: () -> Void
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // WebView 完全全屏
            WebView(url: file.url, onClose: onClose)
                .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
    }
}

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    let url: URL
    let onClose: () -> Void
    
    // 共享的 URL Scheme Handler - 保持现有引用
    private static let urlSchemeHandler = AppURLSchemeHandler()
    
    func makeUIView(context: Context) -> InternalWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        // 注册 app:// URL Scheme Handler
        configuration.setURLSchemeHandler(WebView.urlSchemeHandler, forURLScheme: "app")
        
        // 添加 Script Message Handler 用于接收 JS 调用
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "NeoPodBridge")
        configuration.userContentController = contentController
        
        // 注入 JavaScript API - 包含文件操作API
        let scriptSource = """
        (function() {
            // Create global storage for pending file write operations
            window.pendingOperations = new Map();
            
            window.NeoPod = {
                close: function() {
                    window.webkit.messageHandlers.NeoPodBridge.postMessage({ action: 'close' });
                },
                navigateBack: function() {
                    window.webkit.messageHandlers.NeoPodBridge.postMessage({ action: 'navigateBack' });
                },
                
                // Async file read operation
                readFile: async function(filePath) {
                    try {
                        const response = await fetch('app://' + filePath);
                        if (!response.ok) {
                            throw new Error(`File read failed with status ${response.status}`);
                        }
                        return await response.text();
                    } catch (error) {
                        throw new Error('Read operation failed: ' + error.message);
                    }
                },
                
                // Read directory operation
                readDir: async function(folderPath) {
                    try {
                        const path = folderPath.endsWith('/') ? folderPath : folderPath + '/';
                        const response = await fetch('app://' + path + 'list');
                        
                        if (!response.ok) {
                            throw new Error(`Directory read failed with status ${response.status}`);
                        }
                        
                        const data = await response.json();
                        if (!data.success) {
                            throw new Error('Server returned error: ' + (data.message || 'Unknown'));
                        }
                        
                        return data.files;
                    } catch (error) {
                        throw new Error('Directory read operation failed: ' + error.message);
                    }
                },
                
                // Write file through bridge since direct fetch PUT might not contain body
                writeTextFile: async function(filePath, content) {
                    // Store operation in a pending map to handle via script communication
                    const operationId = Date.now() + Math.random().toString(36).substr(2, 9);
                    window.pendingFilePaths = window.pendingFilePaths || {};
                    window.pendingFilePaths[operationId] = { path: filePath, content: String(content) };
                    
                    return new Promise((resolve, reject) => {
                        // Send through JS bridge (we'll modify the bridge to handle this specifically later)
                        var xhr = new XMLHttpRequest();
                        xhr.open('POST', 'app://pending/' + operationId, true);
                        xhr.onload = function() {
                            if (xhr.status >= 200 && xhr.status < 300) {
                                resolve(xhr.responseText);
                            } else {
                                reject(new Error('File write failed: status ' + xhr.status));
                            }
                        };
                        xhr.onerror = function() {
                            reject(new Error('Network error'));
                        };
                        xhr.setRequestHeader('Content-Type', 'application/json');
                        xhr.send(JSON.stringify({ content: String(content) }));
                    });
                },
                
                deleteFile: async function(filePath, callback) {
                    try {
                        const response = await fetch('app://' + filePath, { method: 'DELETE' });
                        
                        if (!response.ok) {
                            throw new Error(`File deletion failed with status ${response.status}`);
                        }
                        
                        const result = await response.json();
                        if (typeof callback === 'function') {
                            callback(null, result.success ? result : { error: 'Success response malformed' });
                        }
                        return result;
                    } catch (error) {
                        const err = new Error('Delete operation failed: ' + error.message);
                        if (typeof callback === 'function') {
                            callback(err, null);
                        }
                        throw err;
                    }
                }
            };
            
            // Allow standard window closing
            var originalClose = window.close;
            window.close = function() {
                window.NeoPod.close();
            };
            
            console.log('NeoPod API initialized successfully');
        })();
        """
        
        let userScript = WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)
        
        let webView = InternalWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator  // Add UI delegate to handle certain navigations
        
        // Configure scroll behavior
        webView.scrollView.bounces = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        // Disable safe area inset adjustments
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.translatesAutoresizingMaskIntoConstraints = true
        
        return webView
    }
    
    func updateUIView(_ uiView: InternalWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }
    
    class InternalWebView: WKWebView {
        override func layoutSubviews() {
            super.layoutSubviews()
            if let superview = superview {
                frame = superview.bounds
            }
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let onClose: () -> Void
        
        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
            super.init()
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: String],
                  let action = body["action"] else {
                return
            }
            
            DispatchQueue.main.async {
                switch action {
                case "close":
                    self.onClose()
                case "navigateBack":
                    // Additional navigation functionality if needed
                    break
                default:
                    break
                }
            }
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView loaded successfully")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView failed to load: \(error.localizedDescription)")
        }
    }
}


private struct ZuneMenuRow: View {
    let title: String
    let iconName: String
    let accent: Color
    let containerMidY: CGFloat
    
    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("menuScroll"))
            let distance = abs(frame.midY - containerMidY)
            let scale = max(0.78, 1.3 - (distance / 360))
            let opacity = max(0.5, 1.0 - (distance / 700))
            
            HStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundColor(distance < 30 ? accent : .white.opacity(0.75))
                    .frame(width: 36, alignment: .leading)
                Text(title)
                    .font(.system(size: 46, weight: .regular, design: .rounded))
                    .textCase(.lowercase)
                    .foregroundColor(distance < 30 ? accent : .white)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 24)
            .contentShape(Rectangle())
            .scaleEffect(scale, anchor: .leading)
            .opacity(opacity)
        }
        .frame(height: 104)
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
