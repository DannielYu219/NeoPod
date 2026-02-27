import Foundation
import Compression

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

struct AppDetail: Identifiable, Codable {
    let id: String
    let name: String
    let version: String
    let description: String
    let icon: String
    let size: Int
    let last_updated: String
    let files: [String]

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
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

    func getAppDetail(appId: String) async throws -> AppDetail {
        let serverAddress = StoreSettings.shared.serverAddress
        guard !serverAddress.isEmpty else {
            throw StoreError.serverNotConfigured
        }

        let urlString = "\(serverAddress)/api/apps/\(appId)"
        guard let url = URL(string: urlString) else {
            throw StoreError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StoreError.serverError
        }

        return try JSONDecoder().decode(AppDetail.self, from: data)
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
        
        if FileManager.default.fileExists(atPath: appURL.path()) {
            try FileManager.default.removeItem(at: appURL)
        }
        
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try ZipExtractor.unzip(file: zipFile, to: appURL)
                    try? FileManager.default.removeItem(at: zipFile)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func uninstallApp(appId: String) async throws {
        print("[StoreAPI] uninstallApp called with appId: \(appId)")
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[StoreAPI] Failed to get documents directory")
            throw StoreError.installFailed
        }
        
        let programURL = documentsURL.appendingPathComponent("program", isDirectory: true)
        let appURL = programURL.appendingPathComponent(appId, isDirectory: true)
        
        print("[StoreAPI] Documents URL: \(documentsURL.path())")
        print("[StoreAPI] Program URL: \(programURL.path())")
        print("[StoreAPI] App URL: \(appURL.path())")
        
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: appURL.path(), isDirectory: &isDirectory)
        
        print("[StoreAPI] App exists: \(exists), isDirectory: \(isDirectory.boolValue)")
        
        guard exists else {
            print("[StoreAPI] App folder does not exist at: \(appURL.path())")
            
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: programURL.path()) {
                print("[StoreAPI] Contents of program folder: \(contents)")
            }
            
            throw StoreError.appNotFound(appId)
        }
        
        do {
            try FileManager.default.removeItem(at: appURL)
            print("[StoreAPI] Successfully removed app at: \(appURL.path())")
        } catch {
            print("[StoreAPI] Failed to remove app: \(error)")
            throw error
        }
    }
}

enum StoreError: LocalizedError {
    case serverNotConfigured
    case invalidURL
    case serverError
    case installFailed
    case appNotFound(String)
    
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
        case .appNotFound(let appId):
            return "App '\(appId)' not found in program folder"
        }
    }
}

enum ZipExtractor {
    static func unzip(file sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: sourceURL)
        
        var offset = 0
        
        while offset < data.count - 4 {
            let signature = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            
            if signature == 0x04034b50 {
                let headerData = data.subdata(in: offset+4..<offset+30)
                
                let compressionMethod = headerData.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self) }
                let compressedSize = UInt32(littleEndian: headerData.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self) })
                let uncompressedSize = UInt32(littleEndian: headerData.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self) })
                let fileNameLength = UInt16(littleEndian: headerData.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self) })
                let extraFieldLength = UInt16(littleEndian: headerData.subdata(in: 24..<26).withUnsafeBytes { $0.load(as: UInt16.self) })
                
                let fileNameStart = offset + 30
                let fileNameEnd = fileNameStart + Int(fileNameLength)
                let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
                guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                    offset += 30 + Int(fileNameLength) + Int(extraFieldLength) + Int(compressedSize)
                    continue
                }
                
                let fileDataStart = fileNameEnd + Int(extraFieldLength)
                let fileDataEnd = fileDataStart + Int(compressedSize)
                let fileData = data.subdata(in: fileDataStart..<fileDataEnd)
                
                let fileURL = destinationURL.appendingPathComponent(fileName)
                let directoryURL = fileURL.deletingLastPathComponent()
                
                if !fileManager.fileExists(atPath: directoryURL.path()) {
                    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                }
                
                if fileName.hasSuffix("/") {
                    try fileManager.createDirectory(at: fileURL, withIntermediateDirectories: true)
                } else {
                    let outputData: Data
                    if compressionMethod == 0 {
                        outputData = fileData
                    } else if compressionMethod == 8 {
                        outputData = try decompressDeflate(data: fileData, expectedSize: Int(uncompressedSize))
                    } else {
                        throw NSError(domain: "ZipExtractor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported compression method"])
                    }
                    try outputData.write(to: fileURL)
                }
                
                offset = fileDataEnd
            } else {
                offset += 1
            }
        }
    }
    
    private static func decompressDeflate(data: Data, expectedSize: Int) throws -> Data {
        let output = NSMutableData(length: expectedSize)!
        let outputPtr = output.mutableBytes.assumingMemoryBound(to: UInt8.self)
        
        let inputPtr = (data as NSData).bytes.assumingMemoryBound(to: UInt8.self)
        
        let result = compression_decode_buffer(
            outputPtr,
            expectedSize,
            inputPtr,
            data.count,
            nil,
            COMPRESSION_ZLIB
        )
        
        if result == 0 {
            throw NSError(domain: "ZipExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
        }
        
        return output as Data
    }
}
