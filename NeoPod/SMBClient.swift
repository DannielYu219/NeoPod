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
    
    private var client: SMB2Manager?
    
    private init() {}
    
    func connect(to config: SMBServerConfig) async throws {
        await MainActor.run {
            connectionError = nil
        }
        
        let url = URL(string: "smb://\(config.host):\(config.port)")!
        let credential = URLCredential(
            user: config.username,
            password: config.password,
            persistence: .forSession
        )
        
        guard let smbClient = SMB2Manager(url: url, credential: credential, domain: config.domain.isEmpty ? "WORKGROUP" : config.domain) else {
            throw SMBClientError.connectionFailed("Failed to create SMB client")
        }
        
        client = smbClient
        
        do {
            try await client?.connectShare(name: config.shareName)
            
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
        Task {
            try? await client?.disconnectShare()
        }
        client = nil
        isConnected = false
        currentServer = nil
    }
    
    func listDirectory(path: String = "/") async throws -> [SMBFileItem] {
        guard let client = client else {
            throw SMBClientError.notConnected
        }
        
        let items = try await client.contentsOfDirectory(atPath: path)
        
        return items.compactMap { entry -> SMBFileItem? in
            guard let name = entry[.nameKey] as? String else { return nil }
            if name == "." || name == ".." { return nil }
            
            let isDirectory = (entry[.fileResourceTypeKey] as? URLFileResourceType) == .directory
            let size = entry[.fileSizeKey] as? Int64 ?? 0
            let modDate = entry[.contentModificationDateKey] as? Date
            
            let itemPath: String
            if path == "/" {
                itemPath = "/\(name)"
            } else if path.hasSuffix("/") {
                itemPath = "\(path)\(name)"
            } else {
                itemPath = "\(path)/\(name)"
            }
            
            return SMBFileItem(
                name: name,
                path: itemPath,
                isDirectory: isDirectory,
                size: size,
                modificationDate: modDate
            )
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    func readFile(at path: String) async throws -> Data {
        guard let client = client else {
            throw SMBClientError.notConnected
        }
        
        return try await client.contents(atPath: path)
    }
    
    func streamFile(at path: String, offset: Int64 = 0, length: Int? = nil) async throws -> Data {
        guard let client = client else {
            throw SMBClientError.notConnected
        }
        
        if let length = length {
            return try await client.contents(atPath: path, offset: UInt64(offset), length: length)
        } else {
            return try await client.contents(atPath: path, offset: UInt64(offset))
        }
    }
    
    func fileExists(at path: String) async throws -> Bool {
        guard let client = client else {
            throw SMBClientError.notConnected
        }
        
        do {
            let _ = try await client.attributesOfItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
    
    func getFileInfo(at path: String) async throws -> SMBFileItem {
        guard let client = client else {
            throw SMBClientError.notConnected
        }
        
        let attrs = try await client.attributesOfItem(atPath: path)
        let name = URL(fileURLWithPath: path).lastPathComponent
        
        let isDirectory = (attrs[.fileResourceTypeKey] as? URLFileResourceType) == .directory
        let size = attrs[.fileSizeKey] as? Int64 ?? 0
        let modDate = attrs[.contentModificationDateKey] as? Date
        
        return SMBFileItem(
            name: name,
            path: path,
            isDirectory: isDirectory,
            size: size,
            modificationDate: modDate
        )
    }
    
    func downloadFile(at path: String, to localURL: URL, progress: ((Double) -> Void)? = nil) async throws {
        guard let client = client else {
            throw SMBClientError.notConnected
        }
        
        try await client.downloadItem(atPath: path, to: localURL, progress: progress)
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
