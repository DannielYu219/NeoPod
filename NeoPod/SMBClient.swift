// SMBClient.swift
// 作用：实现SMB/CIFS网络文件共享协议的客户端功能
// 依赖：Foundation, AMSMB2
// 输入：SMB服务器配置、文件路径
// 输出：文件列表、文件URL、文件内容
// 实现：使用AMSMB2库连接SMB服务器，支持文件浏览、读取和流式传输

import Foundation
import AMSMB2

struct SMBFileItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
    
    static func == (lhs: SMBFileItem, rhs: SMBFileItem) -> Bool {
        lhs.path == rhs.path
    }
}

enum SMBClientError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case fileNotFound
    case readError(String)
    case invalidPath
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "SMB not connected"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .fileNotFound: return "File not found"
        case .readError(let msg): return "Read error: \(msg)"
        case .invalidPath: return "Invalid path"
        }
    }
}

class SMBClient: ObservableObject {
    static let shared = SMBClient()
    
    @Published var isConnected: Bool = false
    @Published var currentServer: SMBServerConfig?
    @Published var connectionError: String?
    
    private var client: AMSMB2?
    private var share: AMSMB2Share?
    
    private init() {}
    
    func connect(to config: SMBServerConfig) async throws {
        await MainActor.run {
            connectionError = nil
        }
        
        let url = URL(string: "smb://\(config.host):\(config.port)")!
        client = AMSMB2(url: url, domain: config.domain.isEmpty ? "WORKGROUP" : config.domain, username: config.username, password: config.password)
        
        client?.timeout = 30
        
        do {
            try await client?.connect()
            share = try await client?.share(name: config.shareName)
            
            await MainActor.run {
                self.currentServer = config
                self.isConnected = true
            }
        } catch {
            await MainActor.run {
                self.connectionError = error.localizedDescription
                self.isConnected = false
            }
            throw SMBClientError.connectionFailed(error.localizedDescription)
        }
    }
    
    func disconnect() {
        share = nil
        client = nil
        isConnected = false
        currentServer = nil
    }
    
    func listDirectory(path: String = "/") async throws -> [SMBFileItem] {
        guard let share = share else {
            throw SMBClientError.notConnected
        }
        
        let items = try await share.listDirectory(atPath: path)
        
        return items.compactMap { item -> SMBFileItem? in
            let name = item.name
            if name == "." || name == ".." { return nil }
            
            return SMBFileItem(
                name: name,
                path: path.hasSuffix("/") ? "\(path)\(name)" : "\(path)/\(name)",
                isDirectory: item.isDirectory,
                size: item.fileSize,
                modificationDate: item.modificationDate
            )
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    func readFile(at path: String) async throws -> Data {
        guard let share = share else {
            throw SMBClientError.notConnected
        }
        
        return try await share.readData(atPath: path)
    }
    
    func streamFile(at path: String, offset: Int64 = 0, length: Int? = nil) async throws -> Data {
        guard let share = share else {
            throw SMBClientError.notConnected
        }
        
        if let length = length {
            return try await share.readData(atPath: path, offset: UInt64(offset), length: length)
        } else {
            return try await share.readData(atPath: path, offset: UInt64(offset))
        }
    }
    
    func fileExists(at path: String) async throws -> Bool {
        guard let share = share else {
            throw SMBClientError.notConnected
        }
        
        do {
            let _ = try await share.attributesOfItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
    
    func getFileInfo(at path: String) async throws -> SMBFileItem {
        guard let share = share else {
            throw SMBClientError.notConnected
        }
        
        let attrs = try await share.attributesOfItem(atPath: path)
        let name = URL(fileURLWithPath: path).lastPathComponent
        
        return SMBFileItem(
            name: name,
            path: path,
            isDirectory: attrs.isDirectory,
            size: attrs.fileSize,
            modificationDate: attrs.modificationDate
        )
    }
    
    func downloadFile(at path: String, to localURL: URL, progress: ((Double) -> Void)? = nil) async throws {
        guard let share = share else {
            throw SMBClientError.notConnected
        }
        
        try await share.downloadItem(atPath: path, to: localURL, progress: progress)
    }
    
    func getStreamingURL(for path: String) -> URL? {
        guard let config = currentServer else { return nil }
        
        var components = URLComponents()
        components.scheme = "smb"
        components.host = config.host
        components.port = config.port
        components.path = "/\(config.shareName)\(path)"
        components.user = config.username
        components.password = config.password
        
        return components.url
    }
}
