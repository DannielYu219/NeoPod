import SwiftUI
import WebKit

// MARK: - WebView Wrapper

struct WebView: UIViewRepresentable {
    let url: URL
    let onClose: () -> Void
    
    // 共享的 URL Scheme Handler
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
        
        // 注入 JavaScript API
        let scriptSource = """
        (function() {
            window.NeoPod = {
                close: function() {
                    window.webkit.messageHandlers.NeoPodBridge.postMessage({ action: 'close' });
                },
                navigateBack: function() {
                    window.webkit.messageHandlers.NeoPodBridge.postMessage({ action: 'navigateBack' });
                },
                
                // 文件操作API
                readFileSync: function(filePath) {
                    const response = fetch('app://' + filePath);
                    if (response.status === 200) {
                        return response.text();
                    }
                    throw new Error('Failed to read file: ' + response.status);
                },
                
                writeFile: function(filePath, content, onSuccess, onError) {
                    const xhr = new XMLHttpRequest();
                    xhr.open('PUT', 'app://' + filePath, true);
                    xhr.setRequestHeader('Content-Type', 'text/plain');
                    
                    xhr.onreadystatechange = function() {
                        if (xhr.readyState === 4) {
                            if (xhr.status >= 200 && xhr.status < 300) {
                                onSuccess && onSuccess(xhr.responseText);
                            } else {
                                onError && onError(new Error('Failed to write file: ' + xhr.status));
                            }
                        }
                    };
                    
                    xhr.onerror = function() {
                        onError && onError(new Error('Network error occurred'));
                    };
                    
                    xhr.send(content);
                },
                
                writeFileAsync: async function(filePath, content) {
                    try {
                        const response = await fetch('app://' + filePath, {
                            method: 'PUT',
                            headers: {
                                'Content-Type': 'text/plain'
                            },
                            body: content
                        });
                        if (!response.ok) {
                            throw new Error('Failed to write file: ' + response.statusText);
                        }
                        return await response.text();
                    } catch (error) {
                        throw new Error('Network error: ' + error.message);
                    }
                },
                
                readDir: function(folderPath, callback) {
                    // 使用特殊的list路径格式
                    fetch('app://' + folderPath + '/list/')
                        .then(response => {
                            if (response.ok) {
                                return response.json();
                            }
                            throw new Error('Failed to read directory: ' + response.status);
                        })
                        .then(data => callback(null, data.files))
                        .catch(error => callback(error, null));
                },
                
                readDirSync: async function(folderPath) {
                    try {
                        const response = await fetch('app://' + folderPath + '/list/');
                        if (!response.ok) {
                            throw new Error('Failed to read directory: ' + response.statusText);
                        }
                        const data = await response.json();
                        return data.files;
                    } catch (error) {
                        throw new Error('Network error: ' + error.message);
                    }
                },
                
                deleteFile: function(filePath, onSuccess, onError) {
                    const xhr = new XMLHttpRequest();
                    xhr.open('DELETE', 'app://' + filePath, true);
                    
                    xhr.onreadystatechange = function() {
                        if (xhr.readyState === 4) {
                            if (xhr.status >= 200 && xhr.status < 300) {
                                onSuccess && onSuccess();
                            } else {
                                onError && onError(new Error('Failed to delete file: ' + xhr.status));
                            }
                        }
                    };
                    
                    xhr.onerror = function() {
                        onError && onError(new Error('Network error occurred'));
                    };
                    
                    xhr.send();
                }
            };
            
            // 兼容标准窗口关闭调用
            var originalClose = window.close;
            window.close = function() {
                window.NeoPod.close();
            };
            
            console.log('NeoPod API is ready!');
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
        let request = URLRequest(url: url)
        uiView.load(request)
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
            guard let body = message.body as? [String: String],
                  let action = body["action"] else {
                return
            }
            
            switch action {
            case "close":
                // 执行关闭操作
                DispatchQueue.main.async {
                    self.onClose()
                }
            case "navigateBack":
                // 可以扩展其他导航功能
                break
            default:
                break
            }
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
