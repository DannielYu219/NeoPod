// FileSystemManager.swift
// 作用：管理应用的文件系统，提供文件夹路径和文件操作功能
// 依赖：Foundation
// 输入：无
// 输出：各文件夹URL、HTML文件列表
// 实现：使用FileManager管理Documents目录下的子文件夹，支持music/video/config/cache/program/dev目录

import Foundation

enum FileSystemManager {
    private static let appFolderNames = [
        "music",
        "video",
        "config",
        "cache",
        "program",
        "dev"
    ]

    static func ensureAppFoldersExist() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        for folderName in appFolderNames {
            let folderURL = documentsURL.appendingPathComponent(folderName, isDirectory: true)
            if !fileManager.fileExists(atPath: folderURL.path) {
                do {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                } catch {
                    print("Failed to create folder: \(folderName). Error: \(error)")
                }
            }
        }
    }

    static func musicFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("music", isDirectory: true)
    }
    
    static func videoFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("video", isDirectory: true)
    }
    
    static func devFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("dev", isDirectory: true)
    }
    
    static func programFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("program", isDirectory: true)
    }
    
    static func htmlFilesInDevAndProgramFolders() -> [HTMLFileInfo] {
        var htmlFiles: [HTMLFileInfo] = []
        
        if let devURL = devFolderURL() {
            htmlFiles.append(contentsOf: htmlFilesInDirectory(devURL, basePath: "dev"))
        }
        
        if let programURL = programFolderURL() {
            htmlFiles.append(contentsOf: htmlFilesInDirectory(programURL, basePath: "program"))
        }
        
        htmlFiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        
        return htmlFiles
    }
    
    private static func htmlFilesInDirectory(_ directoryURL: URL, basePath: String) -> [HTMLFileInfo] {
        var htmlFiles: [HTMLFileInfo] = []
        
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return htmlFiles }
        
        do {
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
            let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
            
            while let url = enumerator?.nextObject() as? URL {
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                
                if resourceValues.isRegularFile == true {
                    let ext = url.pathExtension.lowercased()
                    if ext == "html" || ext == "htm" {
                        let relativePath = url.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
                        let modificationDate = resourceValues.contentModificationDate ?? Date()
                        
                        let displayName = getDisplayName(for: url, relativePath: relativePath, basePath: basePath)
                        
                        let fileInfo = HTMLFileInfo(
                            id: url.absoluteString,
                            name: relativePath,
                            displayName: displayName,
                            url: url,
                            modificationDate: modificationDate,
                            folder: basePath
                        )
                        htmlFiles.append(fileInfo)
                    }
                }
            }
        } catch {
            print("Failed to read directory \(directoryURL.path): \(error)")
        }
        
        return htmlFiles
    }
    
    private static func getDisplayName(for htmlURL: URL, relativePath: String, basePath: String) -> String {
        if basePath == "program" {
            let pathComponents = relativePath.split(separator: "/")
            if let appId = pathComponents.first {
                let appFolderURL = htmlURL.deletingLastPathComponent()
                while appFolderURL.lastPathComponent != String(appId) && appFolderURL.path != "/" {
                    break
                }
                
                let infoURL = htmlURL.deletingLastPathComponent()
                    .appendingPathComponent("info.json")
                
                if let info = readAppInfo(from: infoURL) {
                    return info.name
                }
                
                return String(appId)
            }
        }
        
        return relativePath.replacingOccurrences(of: "/", with: " / ")
    }
    
    private static func readAppInfo(from url: URL) -> AppInfoFile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            let info = try JSONDecoder().decode(AppInfoFile.self, from: data)
            return info
        } catch {
            print("Failed to read app info: \(error)")
            return nil
        }
    }
    
    static func htmlFilesInDevFolder() -> [HTMLFileInfo] {
        guard let devURL = devFolderURL() else { return [] }
        
        var htmlFiles: [HTMLFileInfo] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: devURL, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            
            for fileURL in files where fileURL.pathExtension.lowercased() == "html" || fileURL.pathExtension.lowercased() == "htm" {
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
                let fileInfo = HTMLFileInfo(
                    id: fileURL.absoluteString,
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    displayName: fileURL.deletingPathExtension().lastPathComponent,
                    url: fileURL,
                    modificationDate: modificationDate,
                    folder: "dev"
                )
                htmlFiles.append(fileInfo)
            }
            
            htmlFiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            print("Failed to read dev folder: \(error)")
        }
        
        return htmlFiles
    }
    
    static func appURL(for folder: String, path: String) -> URL? {
        guard allowedFolders.contains(folder.lowercased()) else { return nil }
        let urlString = "app://\(folder)/\(path)"
        return URL(string: urlString)
    }
    
    static let allowedFolders = ["music", "video", "config", "cache", "program", "dev"]
}

struct AppInfoFile: Codable {
    let name: String
    let version: String
    let description: String?
    let author: String?
    let last_updated: String?
    let icon: String?
    let main_file: String?
}

struct HTMLFileInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let url: URL
    let modificationDate: Date
    let folder: String
    
    init(id: String, name: String, displayName: String? = nil, url: URL, modificationDate: Date, folder: String = "dev") {
        self.id = id
        self.name = name
        self.displayName = displayName ?? name
        self.url = url
        self.modificationDate = modificationDate
        self.folder = folder
    }
}