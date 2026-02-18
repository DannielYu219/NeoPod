import Foundation
internal import Combine
import CommonCrypto

class NavidromeAPI: ObservableObject {
    static let shared = NavidromeAPI()
    
    @Published var isAuthenticated = false
    @Published var userID: String?
    
    private var salt: String = ""
    private var token: String = ""
    
    private init() {}
    
    // MARK: - Subsonic API Auth
    
    private func generateAuthTokens(password: String) -> (salt: String, token: String) {
        let salt = String(UUID().uuidString.prefix(8))
        let passwordSalt = password + salt
        
        let data = Data(passwordSalt.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        let token = digest.map { String(format: "%02x", $0) }.joined()
        
        return (salt, token)
    }
    
    private var authParams: [String: String] {
        let settings = NavidromeSettings.shared
        guard !settings.username.isEmpty, !settings.password.isEmpty else {
            return [:]
        }
        let (salt, token) = generateAuthTokens(password: settings.password)
        self.salt = salt
        self.token = token
        
        return [
            "u": settings.username,
            "t": token,
            "s": salt,
            "v": "1.16.1",
            "c": "NeoPod",
            "f": "json"
        ]
    }
    
    // MARK: - API Methods
    
    func ping() async throws {
        let url = try buildURL("ping", params: authParams)
        let (_, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NavidromeError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// 获取用户收藏的音乐 - 最快的加载方式
    func getStarred(size: Int = 500) async throws -> StarredResponse {
        var params = authParams
        params["size"] = String(size)
        
        let url = try buildURL("getStarred", params: params)
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let result = try validateResponse(data)
        return try JSONDecoder().decode(StarredResponse.self, from: result)
    }
    
    /// 获取所有专辑
    func getAlbumList2(type: String = "alphabeticalByName", offset: Int = 0, size: Int = 100) async throws -> AlbumListResponse {
        var params = authParams
        params["type"] = type
        params["offset"] = String(offset)
        params["size"] = String(size)
        
        let url = try buildURL("getAlbumList2", params: params)
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let result = try validateResponse(data)
        return try JSONDecoder().decode(AlbumListResponse.self, from: result)
    }
    
    /// 获取专辑的所有歌曲
    func getAlbum(id: String) async throws -> AlbumSongsResponse {
        var params = authParams
        params["id"] = id
        
        let url = try buildURL("getAlbum", params: params)
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let result = try validateResponse(data)
        return try JSONDecoder().decode(AlbumSongsResponse.self, from: result)
    }
    
    /// 获取所有歌曲 - 优化版本
    func getAllSongs() async throws -> [Song] {
        // 方法1: 先尝试获取收藏的音乐（最快）
        do {
            let starred = try await getStarred(size: 500)
            if let songs = starred.subsonicResponse.song {
                return songs
            }
        } catch {
            print("getStarred failed: \(error)")
        }
        
        // 方法2: 获取专辑列表，然后获取每个专辑的歌曲
        let response = try await getAlbumList2(type: "alphabeticalByName", offset: 0, size: 50)
        guard let albums = response.subsonicResponse.albumList2?.album else {
            return []
        }
        
        var allSongs: [Song] = []
        
        // 并行获取前20个专辑的歌曲
        let albumsToFetch = Array(albums.prefix(20))
        
        await withTaskGroup(of: [Song].self) { group in
            for album in albumsToFetch {
                group.addTask {
                    do {
                        let songs = try await self.getAlbum(id: album.id)
                        return songs.subsonicResponse.album?.song ?? []
                    } catch {
                        return []
                    }
                }
            }
            
            for await songs in group {
                allSongs.append(contentsOf: songs)
            }
        }
        
        return allSongs
    }
    
    /// 获取封面图片
    func getCoverArt(id: String, size: Int = 300) async throws -> Data {
        var params = authParams
        params["id"] = id
        params["size"] = String(size)
        
        let url = try buildURL("getCoverArt", params: params)
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, 
           httpResponse.statusCode == 200,
           data.count > 0 {
            return data
        }
        
        throw NavidromeError.coverArtNotFound
    }
    
    /// 获取流媒体URL
    func getStreamURL(id: String) throws -> URL {
        var params = authParams
        let songID = id.replacingOccurrences(of: "navidrome_", with: "")
        params["id"] = songID
        params["format"] = "mp3"
        params["maxBitRate"] = "128"
        
        return try buildURL("stream", params: params)
    }
    
    // MARK: - Helpers
    
    private func buildURL(_ action: String, params: [String: String]) throws -> URL {
        guard let baseURL = NavidromeSettings.shared.baseURL else {
            throw NavidromeError.invalidURL
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/\(action).view"), resolvingAgainstBaseURL: false)
        
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components?.url else {
            throw NavidromeError.invalidURL
        }
        
        return url
    }
    
    private func validateResponse(_ data: Data) throws -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subsonicResponse = json["subsonic-response"] as? [String: Any] else {
            throw NavidromeError.invalidResponse
        }
        
        if let error = subsonicResponse["error"] as? [String: Any],
           let code = error["code"] as? Int,
           code != 0 {
            let message = error["message"] as? String ?? "Unknown error"
            throw NavidromeError.apiError(code: code, message: message)
        }
        
        return data
    }
}

// MARK: - Error

enum NavidromeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(code: Int, message: String)
    case notConfigured
    case coverArtNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP Error: \(statusCode)"
        case .apiError(let code, let message):
            return "API Error \(code): \(message)"
        case .notConfigured:
            return "Navidrome is not configured"
        case .coverArtNotFound:
            return "Cover art not found"
        }
    }
}

// MARK: - Response Models

struct StarredResponse: Codable {
    let subsonicResponse: StarredContainer
    
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct StarredContainer: Codable {
    let song: [Song]?
}

struct AlbumListResponse: Codable {
    let subsonicResponse: AlbumListContainer
    
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct AlbumListContainer: Codable {
    let albumList2: AlbumList2?
    
    enum CodingKeys: String, CodingKey {
        case albumList2 = "albumList2"
    }
}

struct AlbumList2: Codable {
    let album: [Album]?
    let total: Int?
}

struct Album: Codable {
    let id: String
    let name: String
    let artist: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, artist
        case coverArt = "coverArt"
        case songCount, duration
    }
}

struct AlbumSongsResponse: Codable {
    let subsonicResponse: AlbumDetailContainer
    
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct AlbumDetailContainer: Codable {
    let album: AlbumDetail?
}

struct AlbumDetail: Codable {
    let id: String
    let name: String
    let artist: String?
    let coverArt: String?
    let song: [Song]?
}

struct Song: Codable, Identifiable {
    let id: String
    let title: String
    let album: String?
    let artist: String?
    let duration: Int?
    let size: Int64?
    let contentType: String?
    let coverArt: String?
    let path: String?
    let bitRate: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, title, album, artist, duration, size
        case contentType = "contentType"
        case coverArt = "coverArt"
        case path
        case bitRate
    }
}

