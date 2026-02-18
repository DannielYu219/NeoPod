import Foundation

struct AppInfo: Identifiable, Codable {
    let id: String
    let name: String
    let version: String
    let description: String
    let icon: String
    let size: Int
    let last_updated: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, version, description, icon, size
        case last_updated = "last_updated"
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

struct AppListResponse: Codable {
    let apps: [AppInfo]
}

class StoreAPI {
    static let shared = StoreAPI()
    
    private init() {}
    
    func getApps() async throws -> [AppInfo] {
        let serverAddress = StoreSettings.shared.serverAddress
        guard !serverAddress.isEmpty else {
            throw StoreError.serverNotConfigured
        }
        
        let urlString = "\(serverAddress)/api/apps"
        guard let url = URL(string: urlString) else {
            throw StoreError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StoreError.serverError
        }
        
        let appListResponse = try JSONDecoder().decode(AppListResponse.self, from: data)
        return appListResponse.apps
    }
    
    func downloadApp(appId: String) async throws -> URL {
        let serverAddress = StoreSettings.shared.serverAddress
        guard !serverAddress.isEmpty else {
            throw StoreError.serverNotConfigured
        }
        
        let urlString = "\(serverAddress)/api/apps/\(appId)/download"
        guard let url = URL(string: urlString) else {
            throw StoreError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StoreError.serverError
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(appId).zip")
        try data.write(to: tempFile)
        
        return tempFile
    }
    
    func installApp(from zipFile: URL, appId: String) async throws {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw StoreError.installFailed
        }
        
        let programURL = documentsURL.appendingPathComponent("program", isDirectory: true)
        let appURL = programURL.appendingPathComponent(appId, isDirectory: true)
        
        if FileManager.default.fileExists(atPath: appURL.path) {
            try FileManager.default.removeItem(at: appURL)
        }
        
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try ZipArchive.unzipFile(at: zipFile, to: appURL)
                    try FileManager.default.removeItem(at: zipFile)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum StoreError: LocalizedError {
    case serverNotConfigured
    case invalidURL
    case serverError
    case installFailed
    
    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "Store server not configured"
        case .invalidURL:
            return "Invalid server URL"
        case .serverError:
            return "Server error"
        case .installFailed:
            return "Installation failed"
        }
    }
}

enum ZipArchive {
    static func unzipFile(at source: URL, to destination: URL) throws {
        try FileManager.default.unzipItem(at: source, to: destination)
    }
}