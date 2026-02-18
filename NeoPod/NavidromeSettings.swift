import Foundation
internal import Combine

class NavidromeSettings: ObservableObject {
    static let shared = NavidromeSettings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let serverAddress = "navidrome_server_address"
        static let username = "navidrome_username"
        static let password = "navidrome_password"
        static let isConfigured = "navidrome_is_configured"
    }
    
    @Published var serverAddress: String {
        didSet {
            defaults.set(serverAddress, forKey: Keys.serverAddress)
        }
    }
    
    @Published var username: String {
        didSet {
            defaults.set(username, forKey: Keys.username)
        }
    }
    
    @Published var password: String {
        didSet {
            defaults.set(password, forKey: Keys.password)
        }
    }
    
    var isConfigured: Bool {
        get { defaults.bool(forKey: Keys.isConfigured) }
        set { defaults.set(newValue, forKey: Keys.isConfigured) }
    }
    
    private init() {
        self.serverAddress = defaults.string(forKey: Keys.serverAddress) ?? "api.u708946.nyat.app:28724"
        self.username = defaults.string(forKey: Keys.username) ?? ""
        self.password = defaults.string(forKey: Keys.password) ?? ""
    }
    
    var baseURL: URL? {
        guard !serverAddress.isEmpty else { return nil }
        var address = serverAddress
        if !address.hasPrefix("http://") && !address.hasPrefix("https://") {
            address = "https://" + address
        }
        return URL(string: address)
    }
}
