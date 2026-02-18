import Foundation
import UIKit

class CoverArtCache {
    static let shared = CoverArtCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // 创建缓存目录
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("CoverArt")
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 设置内存缓存限制
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    func image(for id: String, size: Int = 300) async -> UIImage? {
        let key = "\(id)_\(size)" as NSString
        
        // 1. 检查内存缓存
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        // 2. 检查磁盘缓存
        let fileURL = cacheDirectory.appendingPathComponent("\(key).jpg")
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            cache.setObject(image, forKey: key)
            return image
        }
        
        // 3. 从网络加载
        do {
            let data = try await NavidromeAPI.shared.getCoverArt(id: id, size: size)
            if let image = UIImage(data: data) {
                // 保存到缓存
                cache.setObject(image, forKey: key)
                try? data.write(to: fileURL)
                return image
            }
        } catch {
            print("Failed to load cover art: \(error)")
        }
        
        return nil
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
