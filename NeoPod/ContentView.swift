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
        case chat
        case setting
        case dev
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
        MenuItem(title: "chat", iconName: "message", destination: .chat),
        MenuItem(title: "setting", iconName: "gearshape", destination: .setting),
        MenuItem(title: "dev", iconName: "terminal", destination: .dev)
    ]
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    @State private var currentPage: MenuDestination = .home
    @State private var isForwardNavigation = true
    @State private var musicIsShowingPlayer = false
    
    // Dev 页面专属状态
    @State private var devSelectedFile: HTMLFileInfo? = nil
    
    // 计算是否正在显示 HTML 预览
    private var isShowingHTML: Bool {
        devSelectedFile != nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZuneBackground()
                
                // 主内容区域
                VStack(spacing: 20) {
                    // 只在非 HTML 预览时显示 TopBar
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
                                
                                isForwardNavigation = false
                                withAnimation(.easeOut(duration: 0.28)) {
                                    currentPage = .home
                                }
                            }
                        )
                        // 在 Header 右侧覆盖一个"正在播放"按钮
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
                
                // HTML 预览覆盖层（完全全屏）
                if let file = devSelectedFile {
                    HTMLPreviewOverlay(file: file, onClose: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            devSelectedFile = nil
                        }
                    })
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundColor(.white)
        .statusBarHidden(isShowingHTML)
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
            VideoView()
        case .chat:
            ChatView()
        case .setting:
            SettingView()
        case .dev:
            DevView(onFileSelected: { file in
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
        case .chat:
            return "CHAT"
        case .setting:
            return "SETTING"
        case .dev:
            return "DEV"
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
    
    // 共享的 URL Scheme Handler
    private static let urlSchemeHandler = AppURLSchemeHandler()
    
    func makeUIView(context: Context) -> InternalWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        // 注册 app:// URL Scheme Handler
        configuration.setURLSchemeHandler(WebView.urlSchemeHandler, forURLScheme: "app")
        
        // 添加 Script Message Handler 用于接收 JS 调用
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "NeoPodBridge")
        configuration.userContentController = contentController
        
        // 注入 JavaScript API（包含文件操作）
        let scriptSource = """
        (function() {
            const callbacks = {};
            let callbackId = 0;

            function callNative(action, payload) {
                return new Promise((resolve, reject) => {
                    const id = ++callbackId;
                    callbacks[id] = { resolve, reject };
                    window.webkit.messageHandlers.NeoPodBridge.postMessage({
                        action: 'file',
                        id: id,
                        payload: Object.assign({ action: action }, payload || {})
                    });
                });
            }

            window.NeoPod = {
                close: function() {
                    window.webkit.messageHandlers.NeoPodBridge.postMessage({ action: 'close' });
                },
                navigateBack: function() {
                    window.webkit.messageHandlers.NeoPodBridge.postMessage({ action: 'navigateBack' });
                },
                readDir: async function(path) {
                    const result = await callNative('readDir', { path: path });
                    return result.files || [];
                },
                readFile: async function(path) {
                    const result = await callNative('readFile', { path: path });
                    return result.content || '';
                },
                writeFile: async function(path, content) {
                    return await callNative('writeFile', { path: path, content: String(content) });
                },
                deleteFile: async function(path) {
                    return await callNative('deleteFile', { path: path });
                },
                __resolve: function(id, result) {
                    if (callbacks[id]) {
                        callbacks[id].resolve(result);
                        delete callbacks[id];
                    }
                },
                __reject: function(id, message) {
                    if (callbacks[id]) {
                        callbacks[id].reject(new Error(message));
                        delete callbacks[id];
                    }
                }
            };
            
            // 兼容标准窗口关闭调用
            var originalClose = window.close;
            window.close = function() {
                window.NeoPod.close();
            };
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
        webView.scrollView.bounces = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        // 关键修复：禁用安全区 inset
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        // 设置 autoresizing 以填充整个父视图
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.translatesAutoresizingMaskIntoConstraints = true
        
        return webView
    }
    
    func updateUIView(_ uiView: InternalWebView, context: Context) {
        guard uiView.url != url else { return }
        
        if url.isFileURL {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let devURL = FileSystemManager.devFolderURL()
            let readAccessURL: URL
            
            if let devURL, url.path.hasPrefix(devURL.path) {
                readAccessURL = devURL
            } else if let documentsURL, url.path.hasPrefix(documentsURL.path) {
                readAccessURL = documentsURL
            } else {
                readAccessURL = url.deletingLastPathComponent()
            }
            
            uiView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
        } else {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }
    
    // 自定义 WKWebView 子类，重写 layoutSubviews 以确保填满
    class InternalWebView: WKWebView {
        override func layoutSubviews() {
            super.layoutSubviews()
            // 确保 webView 始终填满父容器
            if let superview = superview {
                frame = superview.bounds
            }
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onClose: () -> Void
        
        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
            super.init()
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else {
                return
            }
            
            switch action {
            case "close":
                DispatchQueue.main.async {
                    self.onClose()
                }
            case "navigateBack":
                break
            case "file":
                guard let id = body["id"] as? Int,
                      let payload = body["payload"] as? [String: Any],
                      let webView = message.webView else {
                    return
                }
                handleFileOperation(payload: payload, id: id, webView: webView)
            default:
                break
            }
        }
        
        private func handleFileOperation(payload: [String: Any], id: Int, webView: WKWebView) {
            guard let operation = payload["action"] as? String else {
                sendReject(id: id, message: "Missing file operation", webView: webView)
                return
            }
            
            let path = payload["path"] as? String ?? ""
            
            do {
                switch operation {
                case "readDir":
                    let result = try readDirectory(path: path)
                    sendResolve(id: id, result: result, webView: webView)
                case "readFile":
                    let result = try readFile(path: path)
                    sendResolve(id: id, result: result, webView: webView)
                case "writeFile":
                    let content = payload["content"] as? String ?? ""
                    let result = try writeFile(path: path, content: content)
                    sendResolve(id: id, result: result, webView: webView)
                case "deleteFile":
                    let result = try deleteFile(path: path)
                    sendResolve(id: id, result: result, webView: webView)
                default:
                    sendReject(id: id, message: "Unsupported file operation: \(operation)", webView: webView)
                }
            } catch {
                sendReject(id: id, message: error.localizedDescription, webView: webView)
            }
        }
        
        private func readDirectory(path: String) throws -> [String: Any] {
            let targetURL = try resolvePath(path: path, isDirectory: true)
            
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            var files: [[String: Any]] = []
            for fileURL in fileURLs {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                files.append([
                    "name": fileURL.lastPathComponent,
                    "isDirectory": values.isDirectory ?? false,
                    "size": values.fileSize ?? 0,
                    "modified": (values.contentModificationDate ?? Date()).timeIntervalSince1970
                ])
            }
            
            return [
                "success": true,
                "files": files
            ]
        }
        
        private func readFile(path: String) throws -> [String: Any] {
            let fileURL = try resolvePath(path: path, isDirectory: false)
            let data = try Data(contentsOf: fileURL)
            let content = String(data: data, encoding: .utf8) ?? ""
            return [
                "success": true,
                "content": content
            ]
        }
        
        private func writeFile(path: String, content: String) throws -> [String: Any] {
            let fileURL = try resolvePath(path: path, isDirectory: false)
            let directoryURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            let data = content.data(using: .utf8) ?? Data()
            try data.write(to: fileURL, options: .atomic)
            return [
                "success": true,
                "path": path
            ]
        }
        
        private func deleteFile(path: String) throws -> [String: Any] {
            let fileURL = try resolvePath(path: path, isDirectory: false)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return [
                "success": true,
                "path": path
            ]
        }
        
        private func resolvePath(path: String, isDirectory: Bool) throws -> URL {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "NeoPodFile", code: 500, userInfo: [NSLocalizedDescriptionKey: "Documents directory not found"])
            }
            
            let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = trimmedPath.split(separator: "/").map(String.init)
            guard let folder = components.first, FileSystemManager.allowedFolders.contains(folder.lowercased()) else {
                throw NSError(domain: "NeoPodFile", code: 403, userInfo: [NSLocalizedDescriptionKey: "Access denied"])
            }
            
            let folderURL = documentsURL.appendingPathComponent(folder, isDirectory: true)
            let remaining = components.dropFirst().joined(separator: "/")
            let targetURL = remaining.isEmpty
                ? folderURL
                : folderURL.appendingPathComponent(remaining, isDirectory: isDirectory)
            
            guard targetURL.path.hasPrefix(folderURL.path) else {
                throw NSError(domain: "NeoPodFile", code: 403, userInfo: [NSLocalizedDescriptionKey: "Path traversal detected"])
            }
            
            return targetURL
        }
        
        private func sendResolve(id: Int, result: [String: Any], webView: WKWebView) {
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let jsonString = String(data: data, encoding: .utf8) else {
                sendReject(id: id, message: "Failed to encode response", webView: webView)
                return
            }
            webView.evaluateJavaScript("window.NeoPod.__resolve(\(id), \(jsonString));")
        }
        
        private func sendReject(id: Int, message: String, webView: WKWebView) {
            let escaped = message
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            webView.evaluateJavaScript("window.NeoPod.__reject(\(id), \"\(escaped)\");")
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView finished loading")
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
