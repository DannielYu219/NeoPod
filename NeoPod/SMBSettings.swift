// SMBSettings.swift
// 作用：存储和管理SMB服务器配置信息
// 依赖：Foundation
// 输入：服务器地址、端口、用户名、密码、共享名称
// 输出：SMB连接配置
// 实现：使用UserDefaults持久化存储SMB服务器配置，支持多个服务器配置

import Foundation

struct SMBServerConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int = 445
    var username: String
    var password: String
    var shareName: String
    var domain: String = ""
    
    static func == (lhs: SMBServerConfig, rhs: SMBServerConfig) -> Bool {
        lhs.id == rhs.id
    }
}

class SMBSettings: ObservableObject {
    static let shared = SMBSettings()
    
    private let serversKey = "smb_servers_v1"
    
    @Published var servers: [SMBServerConfig] = []
    
    private init() {
        loadServers()
    }
    
    var isConfigured: Bool {
        !servers.isEmpty
    }
    
    func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey) else { return }
        do {
            servers = try JSONDecoder().decode([SMBServerConfig].self, from: data)
        } catch {
            print("Failed to load SMB servers: \(error)")
        }
    }
    
    func saveServers() {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: serversKey)
        } catch {
            print("Failed to save SMB servers: \(error)")
        }
    }
    
    func addServer(_ config: SMBServerConfig) {
        servers.append(config)
        saveServers()
    }
    
    func updateServer(_ config: SMBServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == config.id }) {
            servers[index] = config
            saveServers()
        }
    }
    
    func removeServer(_ config: SMBServerConfig) {
        servers.removeAll { $0.id == config.id }
        saveServers()
    }
    
    func removeServer(at indexSet: IndexSet) {
        servers.remove(atOffsets: indexSet)
        saveServers()
    }
}
