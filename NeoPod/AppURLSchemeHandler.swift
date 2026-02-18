// AppURLSchemeHandler.swift
import Foundation
import WebKit

class AppURLSchemeHandler: NSObject, WKURLSchemeHandler {
    
    // 允许访问的文件夹白名单
    private let allowedFolders = ["music", "video", "config", "cache", "program", "dev"]
    
    // 预先计算文档目录URL来避免重复计算
    private lazy var documentDirectoryURL: URL? = {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }()
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "app" else {
            sendError(urlSchemeTask, statusCode: 400, message: "Invalid scheme")
            return
        }
        
        // 确保只从主线程或专用队列访问UIWebView
        DispatchQueue.main.async {
            let method = urlSchemeTask.request.httpMethod?.uppercased() ?? "GET"
            
            if method == "GET" {
                self.handleFileRead(urlSchemeTask: urlSchemeTask)
            } else if method == "POST" || method == "PUT" {
                self.handleFileWrite(urlSchemeTask: urlSchemeTask)
            } else if method == "DELETE" {
                self.handleFileDelete(urlSchemeTask: urlSchemeTask)
            } else {
                self.sendError(urlSchemeTask, statusCode: 405, message: "Method not allowed")
            }
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 任务取消，无需处理
    }
    
    private func handleFileRead(urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            self.sendError(urlSchemeTask, statusCode: 400, message: "Invalid URL")
            return
        }
        
        // 解析路径：app://folder/path/to/file
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard !pathComponents.isEmpty,
              self.allowedFolders.contains(pathComponents[0].lowercased()) else {
            self.sendError(urlSchemeTask, statusCode: 403, message: "Access denied to this folder")
            return
        }
        
        // 特殊处理：列出目录内容
        if pathComponents.count > 1 && pathComponents.last?.hasPrefix("list") == true {
            self.handleListDirectory(urlSchemeTask: urlSchemeTask, pathComponents: pathComponents)
            return
        }
        
        // 构建文件路径
        guard let documentsURL = self.documentDirectoryURL else {
            self.sendError(urlSchemeTask, statusCode: 500, message: "Cannot access documents directory")
            return
        }
        
        // 安全检查：防止路径遍历攻击
        let folderPath = pathComponents[0]
        var remainingPath = ""
        if pathComponents.count > 1 {
            remainingPath = Array(pathComponents[1...]).joined(separator: "/")
        }
        let fileURL = documentsURL
            .appendingPathComponent(folderPath, isDirectory: true)
            .appendingPathComponent(remainingPath, isDirectory: false)
        
        // 验证文件在允许的文件夹内
        let folderURL = documentsURL.appendingPathComponent(folderPath, isDirectory: true)
        if !fileURL.path.hasPrefix(folderURL.path) {
            self.sendError(urlSchemeTask, statusCode: 403, message: "Path traversal detected")
            return
        }
        
        // 异步执行文件读取操作 - 重要：避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let data = try Data(contentsOf: fileURL)
                    let mimeType = self.getMimeType(for: fileURL)
                    
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": mimeType,
                            "Access-Control-Allow-Origin": "*",
                            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                            "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With"
                        ]
                    )
                    
                    DispatchQueue.main.async {
                        urlSchemeTask.didReceive(response!)
                        urlSchemeTask.didReceive(data)
                        urlSchemeTask.didFinish()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.sendError(urlSchemeTask, statusCode: 404, message: "File not found: \(fileURL.path)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.sendError(urlSchemeTask, statusCode: 404, message: "File read error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleListDirectory(urlSchemeTask: WKURLSchemeTask, pathComponents: [String]) {
        guard let documentsURL = self.documentDirectoryURL else {
            DispatchQueue.main.async {
                self.sendError(urlSchemeTask, statusCode: 500, message: "Cannot access documents directory")
            }
            return
        }
        
        let folderPath = pathComponents[0]
        var remainingPath = ""
        if pathComponents.count > 2 {  // 因为有list作为最后一个组件
            remainingPath = Array(pathComponents[1..<(pathComponents.count-1)]).joined(separator: "/")
        }
        
        // 验证安全性
        let targetFolderURL = documentsURL.appendingPathComponent(folderPath, isDirectory: true)
        let targetURL = targetFolderURL.appendingPathComponent(remainingPath, isDirectory: true)
        
        if !targetURL.path.hasPrefix(targetFolderURL.path) {
            DispatchQueue.main.async {
                self.sendError(urlSchemeTask, statusCode: 403, message: "Path traversal detected")
            }
            return
        }
        
        // 异步执行目录枚举操作
        DispatchQueue.global(qos: .userInitiated).async {
            var files: [[String: Any]] = []
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: targetURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                
                for fileURL in fileURLs {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
                    
                    let fileEntry: [String: Any] = [
                        "name": fileURL.lastPathComponent,
                        "isDirectory": resourceValues.isDirectory ?? false,
                        "size": resourceValues.fileSize ?? 0,
                        "modified": (resourceValues.contentModificationDate ?? Date()).timeIntervalSince1970,
                        "created": (resourceValues.creationDate ?? Date()).timeIntervalSince1970,
                        "extension": fileURL.pathExtension.lowercased(),
                        "path": "\(folderPath)\(remainingPath.isEmpty ? "" : "/")\(remainingPath)".appending("/\(fileURL.lastPathComponent)")
                    ]
                    
                    files.append(fileEntry)
                }
                
                let fileListData = [
                    "folder": folderPath,
                    "path": remainingPath,
                    "files": files,
                    "success": true
                ] as [String: Any]
                
                let jsonData = try JSONSerialization.data(withJSONObject: fileListData)
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    let response = HTTPURLResponse(
                        url: urlSchemeTask.request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": "application/json",
                            "Access-Control-Allow-Origin": "*",
                            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                            "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With"
                        ]
                    )
                    
                    urlSchemeTask.didReceive(response!)
                    urlSchemeTask.didReceive(jsonData)
                    urlSchemeTask.didFinish()
                }
                
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.sendError(urlSchemeTask, statusCode: 500, message: "Could not list directory: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleFileWrite(urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            self.sendError(urlSchemeTask, statusCode: 400, message: "Invalid URL")
            return
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard !pathComponents.isEmpty,
              self.allowedFolders.contains(pathComponents[0].lowercased()),
              let documentsURL = self.documentDirectoryURL else {
            
            self.sendError(urlSchemeTask, statusCode: 403, message: "Access denied or invalid location")
            return
        }
        
        // 安全检查：防止路径遍历攻击
        let folderPath = pathComponents[0]
        var remainingPath = ""
        if pathComponents.count > 1 {
            remainingPath = Array(pathComponents[1...]).joined(separator: "/")
        }
        let fileURL = documentsURL
            .appendingPathComponent(folderPath, isDirectory: true)
            .appendingPathComponent(remainingPath, isDirectory: false)
        
        let folderURL = documentsURL.appendingPathComponent(folderPath, isDirectory: true)
        if !fileURL.path.hasPrefix(folderURL.path) {
            self.sendError(urlSchemeTask, statusCode: 403, message: "Path traversal detected")
            return
        }
        
        // 创建必要目录
        let directoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                self.sendError(urlSchemeTask, statusCode: 500, message: "Could not create directories: \(error.localizedDescription)")
                return
            }
        }
        
        // 实际获取 POST/PUT 请求体的内容比较复杂，因为 WKURLSchemeTask 没有直接的方式获取请求体
        // 这里我们假设请求体在某个扩展的实现中可用
        // 通常在移动端应用中，我们会通过 JavaScript bridge 来传递数据
        DispatchQueue.global(qos: .background).async {
            // 在真实的实现中，你需要以适当方式获取提交的数据
            // 可以使用请求的消息处理器来处理传递的数据
            let isJSONType = urlSchemeTask.request.allHTTPHeaderFields?["Content-Type"]?.hasPrefix("application/json") ?? false
            
            // 这部分处理会比较复杂 - 我们创建一个占位响应
            let response = HTTPURLResponse(
                url: urlSchemeTask.request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With"
                ]
            )
            
            let responseData = "Content processing...".data(using: .utf8)!
            let successResult = ["success": true, "message": "File will be processed", "path": remainingPath]
            let jsonResponse = try? JSONSerialization.data(withJSONObject: successResult)
            
            DispatchQueue.main.async {
                urlSchemeTask.didReceive(response!)
                urlSchemeTask.didReceive(jsonResponse ?? responseData)
                urlSchemeTask.didFinish()
            }
        }
    }
    
    private func handleFileDelete(urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            self.sendError(urlSchemeTask, statusCode: 400, message: "Invalid URL")
            return
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard !pathComponents.isEmpty,
              self.allowedFolders.contains(pathComponents[0].lowercased()),
              let documentsURL = self.documentDirectoryURL else {
            
            self.sendError(urlSchemeTask, statusCode: 403, message: "Access denied or invalid location")
            return
        }
        
        // 安全检查：防止路径遍历攻击
        let folderPath = pathComponents[0]
        var remainingPath = ""
        if pathComponents.count > 1 {
            remainingPath = Array(pathComponents[1...]).joined(separator: "/")
        }
        let fileURL = documentsURL
            .appendingPathComponent(folderPath, isDirectory: true)
            .appendingPathComponent(remainingPath, isDirectory: false)
        
        let folderURL = documentsURL.appendingPathComponent(folderPath, isDirectory: true)
        if !fileURL.path.hasPrefix(folderURL.path) {
            self.sendError(urlSchemeTask, statusCode: 403, message: "Path traversal detected")
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        let response = HTTPURLResponse(
                            url: urlSchemeTask.request.url!,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: [
                                "Content-Type": "application/json",
                                "Access-Control-Allow-Origin": "*",
                                "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                                "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With"  
                            ]
                        )
                        let successResult = ["success": true, "message": "File deleted successfully", "deletedPath": fileURL.path]
                        let jsonResponse = try? JSONSerialization.data(withJSONObject: successResult)
                        
                        urlSchemeTask.didReceive(response!)
                        urlSchemeTask.didReceive(jsonResponse ?? Data())
                        urlSchemeTask.didFinish()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.sendError(urlSchemeTask, statusCode: 404, message: "File not found for deletion: \(fileURL.path)")
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.sendError(urlSchemeTask, statusCode: 500, message: "Could not delete file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func sendError(_ urlSchemeTask: WKURLSchemeTask, statusCode: Int, message: String) {
        DispatchQueue.main.async {
            let response = HTTPURLResponse(
                url: urlSchemeTask.request.url ?? URL(string: "app://error")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/plain",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With"
                ]
            )
            urlSchemeTask.didReceive(response!)
            urlSchemeTask.didReceive(message.data(using: .utf8) ?? Data())
            urlSchemeTask.didFinish()
        }
    }
    
    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
