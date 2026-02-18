// FileSystemManager.swift
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
        
        htmlFiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
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
                        let displayName = relativePath.replacingOccurrences("/", with: " / ")
                        let modificationDate = resourceValues.contentModificationDate ?? Date()
                        
                        let fileInfo = HTMLFileInfo(
                            id: url.absoluteString,
                            name: displayName,
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
                    url: fileURL,
                    modificationDate: modificationDate,
                    folder: "dev"
                )
                htmlFiles.append(fileInfo)
            }
            
            htmlFiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

struct HTMLFileInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let modificationDate: Date
    let folder: String
    
    init(id: String, name: String, url: URL, modificationDate: Date, folder: String = "dev") {
        self.id = id
        self.name = name
        self.url = url
        self.modificationDate = modificationDate
        self.folder = folder
    }
}