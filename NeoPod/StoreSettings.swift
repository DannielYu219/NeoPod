import Foundation
internal import Combine

class StoreSettings: ObservableObject {
    static let shared = StoreSettings()
    
    private let serverAddressKey = "storeServerAddress"
    
    @Published var serverAddress: String {
        didSet {
            UserDefaults.standard.set(serverAddress, forKey: serverAddressKey)
        }
    }
    
    @Published var isConfigured: Bool = false
    
    private init() {
        self.serverAddress = UserDefaults.standard.string(forKey: serverAddressKey) ?? ""
        self.isConfigured = !serverAddress.isEmpty
    }
    
    func save() {
        isConfigured = !serverAddress.isEmpty
    }
}
