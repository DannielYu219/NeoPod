import SwiftUI
import WebKit

// 新增一个处理文件操作的模型类
class FileOperationManager: NSObject {
    static let shared = FileOperationManager()
    
    private let allowedFolders = ["music", "video", "config", "cache", "program", "dev"]
    
    func readPath(_ path: String) throws -> [String: Any] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // 验证路径安全性
        let pathParts = path.components(separatedBy: "/")
        guard pathParts.count > 0, 
            allowedFolders.contains(pathParts[0].lowercased()) else {
            throw NSError(domain: "FileOperation", code: 403, userInfo: [NSLocalizedDescriptionKey: "Access denied"])
        }
        
        let folderPath = pathParts[0]
        let remainingPath = pathParts.count > 1 ? Array(pathParts[1...]).joined(separator: "/") : ""
        
        let targetURL = documentsURL
            .appendingPathComponent(folderPath, isDirectory: true)
            .appendingPathComponent(remainingPath, isDirectory: true)
        
        let folderURL = documentsURL.appendingPathComponent(folderPath, isDirectory: true)
        guard targetURL.path.hasPrefix(folderURL.path) else {
            throw NSError(domain: "FileOperation", code: 403, userInfo: [NSLocalizedDescriptionKey: "Path traversal detected"])  
        }
        
        if remainingPath.isEmpty || path.hasSuffix("/") {
            // 列出目录内容
            var files: [[String: Any]] = []
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in fileURLs {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
                
                let fileEntry: [String: Any] = [
                    "name": fileURL.lastPathComponent,
                    "isDirectory": resourceValues.isDirectory ?? false,
                    "size": resourceValues.fileSize ?? 0,
                    "modified": (resourceValues.contentModificationDate ?? Date()).timeIntervalSince1970,
                    "created": (resourceValues.creationDate ?? Date()).timeIntervalSince1970,
                    "extension": fileURL.pathExtension.lowercased()
                ]
                files.append(fileEntry)
            }
            return ["success": true, "folder": folderPath, "path": remainingPath, "files": files] as [String: Any]
        } else {
            // 读取单个文件
            let fileURL = documentsURL
                .appendingPathComponent(folderPath, isDirectory: false)
                .appendingPathComponent(remainingPath, isDirectory: false)
            
            let data = try Data(contentsOf: fileURL)
            let base64String = data.base64EncodedString()
            return ["success": true, "content": base64String, "mimeType": getMimeType(for: fileURL)]
        }
    }
    
    func writePath(_ path: String, content: String) throws -> [String: Any] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // 解析路径
        let pathParts = path.components(separatedBy: "/")
        guard pathParts.count > 0,
            allowedFolders.contains(pathParts[0].lowercased()) else {
            throw NSError(domain: "FileOperation", code: 403, userInfo: [NSLocalizedDescriptionKey: "Access denied"])
        }
        
        let folderPath = pathParts[0]
        let remainingPath = pathParts.count > 1 ? Array(pathParts[1...]).joined(separator: "/") : ""
        
        let fileURL = documentsURL
            .appendingPathComponent(folderPath, isDirectory: true)
            .appendingPathComponent(remainingPath, isDirectory: false)
        
        let targetURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true) // 创建目录
        
        let data = Data(base64Encoded: content) ?? content.data(using: .utf8)!
        try data.write(to: fileURL, options: .atomic)
        
        return ["success": true, "path": path, "message": "File written successfully"]
    }
    
    func deletePath(_ path: String) throws -> [String: Any] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        let pathParts = path.components(separatedBy: "/")
        guard pathParts.count > 0,
            allowedFolders.contains(pathParts[0].lowercased()) else {
            throw NSError(domain: "FileOperation", code: 403, userInfo: [NSLocalizedDescriptionKey: "Access denied"])
        }
        
        let folderPath = pathParts[0]
        let remainingPath = pathParts.count > 1 ? Array(pathParts[1...]).joined(separator: "/") : ""
        
        let fileURL = documentsURL
            .appendingPathComponent(folderPath, isDirectory: true)
            .appendingPathComponent(remainingPath, isDirectory: false)
        
        try? FileManager.default.removeItem(at: fileURL)
        
        return ["success": true, "path": path, "message": "File deleted successfully"]
    }
    
    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "txt": return "text/plain"
        case "xml": return "application/xml"
        default: return "application/octet-stream"
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let onClose: () -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "nativeBridge")
        configuration.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        configureUI(webView)
        
        // 注入 JavaScript 桥接API
        injectJsApi(webView: webView)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
    
    private func configureUI(_ webView: WKWebView) {
        webView.scrollView.bounces = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.translatesAutoresizingMaskIntoConstraints = true
    }
    
    private func injectJsApi(webView: WKWebView) {
        let jsCode = """
        window.NeoPod = {
            close: function() {
                window.webkit.messageHandlers.nativeBridge.postMessage({action: 'close'});
            },
            navigateBack: function() {
                window.webkit.messageHandlers.nativeBridge.postMessage({action: 'navigateBack'});
            },
            
            // 异步读取文件
            readFile: async function(filePath) {
                const msg = {action: 'readFile', path: filePath};
                const response = await window.__nativeCall(msg);
                if (!response.success) {
                    throw new Error(response.error || 'Read failed');
                }
                const buffer = Uint8Array.from(atob(response.content), c => c.charCodeAt(0));
                return new TextDecoder().decode(buffer);
            },

            // 读目录
            readDir: async function(folderPath) {
                const msg = {action: 'readDir', path: folderPath.endsWith('/') ? folderPath : folderPath + '/'};
                const response = await window.__nativeCall(msg);
                if (!response.success) {
                    throw new Error(response.error || 'Directory listing failed');
                }
                return response.files;
            },
            
            // 写文件
            writeFile: async function(filePath, content) {
                const encodedContent = btoa(new TextEncoder().encode(content).reduce((data, byte) => data + String.fromCharCode(byte), ''));
                const msg = {action: 'writeFile', path: filePath, content: encodedContent};
                const response = await window.__nativeCall(msg);
                if (!response.success) {
                    throw new Error(response.error || 'Write failed');
                }
                return response;
            },

            // 删除文件
            deleteFile: async function(filePath) {
                const msg = {action: 'deleteFile', path: filePath};
                const response = await window.__nativeCall(msg);
                if (!response.success) {
                    throw new Error(response.error || 'Delete failed');
                }
                return response;
            },
            
            // 内部native函数
            __callbacks__: {},
            __callbackId: 0
        };

        // 定义内部native调用函数
        window.__nativeCall = async function(msg) {
            return new Promise((resolve, reject) => {
                const id = ++window.NeoPod.__callbackId;
                window.NeoPod.__callbacks__[id] = {resolve: resolve, reject: reject};

                window.webkit.messageHandlers.nativeBridge.postMessage({
                    action: 'nativeCall',
                    id: id,
                    data: msg
                });
            });
        };
        """
        
        // 在文档加载完成后注入API
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    print("Error injecting js API: \(error)")
                } else {
                    print("NeoPod JS API injected successfully")
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let onClose: () -> Void
        private var pendingCalls: [Int: (result: ([String: Any]?) -> Void, error: (Error) -> Void)] = [:]
        
        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
            super.init()
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            switch action {
            case "close":
                onClose()
            case "navigateBack":
                // navigation back logic
                break
            case "nativeCall":
                if let nativeMsg = body["data"] as? [String: Any],
                   let id = body["id"] as? Int {
                    handleNativeCall(nativeMsg, id: id)
                }
            default:
                break
            }
        }
        
        private func handleNativeCall(_ call: [String: Any], id: Int) {
            guard let action = call["action"] as? String else {
                callback(id: id, result: ["success": false, "error": "Missing action"])
                return
            }
            let path = call["path"] as? String ?? ""
            
            Task {
                do {
                    switch action {
                    case "readFile":
                        let result = try FileOperationManager.shared.readPath(path)
                        await MainActor.run {
                            self.callback(id: id, result: result)
                        }
                    case "readDir":
                        let result = try FileOperationManager.shared.readPath(path)
                        await MainActor.run {
                            self.callback(id: id, result: result)
                        }
                    case "writeFile":
                        let content = call["content"] as? String ?? ""
                        let result = try FileOperationManager.shared.writePath(path, content: content)
                        await MainActor.run {
                            self.callback(id: id, result: result)
                        }
                    case "deleteFile":
                        let result = try FileOperationManager.shared.deletePath(path)
                        await MainActor.run {
                            self.callback(id: id, result: result)
                        }
                    default:
                        await MainActor.run {
                            self.callback(id: id, result: ["success": false, "error": "Unknown action"])
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.callback(id: id, result: ["success": false, "error": error.localizedDescription])
                    }
                }
            }
        }
        
        private func callback(id: Int, result: [String: Any]?) {
            guard let completionPair = pendingCalls[id] else { return }
            completionPair.resolve(result)
            pendingCalls.removeValue(forKey: id)
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
