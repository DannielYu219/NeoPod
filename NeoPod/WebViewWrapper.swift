// 注意：实际代码应放在原来的 ContentView.swift 中
// Update your original WebView in ContentView.swift as follows:

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
        WebView.urlSchemeHandler
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
