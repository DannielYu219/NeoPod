import SwiftUI

struct SettingView: View {
    @State private var serverAddress: String = NavidromeSettings.shared.serverAddress
    @State private var username: String = NavidromeSettings.shared.username
    @State private var password: String = NavidromeSettings.shared.password
    @State private var isSaving = false
    @State private var showSavedAlert = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    enum ConnectionStatus {
        case unknown, testing, success, failed
        
        var text: String {
            switch self {
            case .unknown: return "Not tested"
            case .testing: return "Testing..."
            case .success: return "Connected"
            case .failed: return "Connection failed"
            }
        }
        
        var color: Color {
            switch self {
            case .unknown: return .white.opacity(0.5)
            case .testing: return .yellow
            case .success: return .green
            case .failed: return .red
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Navidrome API 配置
                VStack(alignment: .leading, spacing: 16) {
                    Text("Navidrome API")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Address")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("api.u708946.nyat.app:28724", text: $serverAddress)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Username", text: $username)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // 连接状态
                    HStack {
                        Circle()
                            .fill(connectionStatus.color)
                            .frame(width: 8, height: 8)
                        Text(connectionStatus.text)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(connectionStatus.color)
                    }
                    .padding(.top, 4)
                    
                    // 操作按钮
                    HStack(spacing: 16) {
                        Button {
                            testConnection()
                        } label: {
                            Text("Test Connection")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(connectionStatus == .testing)
                        
                        Button {
                            saveSettings()
                        } label: {
                            Text("Save")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(accent)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                
                // 说明
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Navidrome")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Navidrome is an open-source web-based music streamer and server. Connect to your Navidrome instance to stream music directly within NeoPod.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineSpacing(4)
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                
                Spacer()
            }
            .padding(20)
        }
        .alert("Settings Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        }
    }
    
    private func testConnection() {
        guard !serverAddress.isEmpty else { return }
        
        connectionStatus = .testing
        
        // 临时保存以测试
        NavidromeSettings.shared.serverAddress = serverAddress
        NavidromeSettings.shared.username = username
        NavidromeSettings.shared.password = password
        
        Task {
            do {
                try await NavidromeAPI.shared.ping()
                await MainActor.run {
                    connectionStatus = .success
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed
                }
            }
        }
    }
    
    private func saveSettings() {
        isSaving = true
        
        NavidromeSettings.shared.serverAddress = serverAddress
        NavidromeSettings.shared.username = username
        NavidromeSettings.shared.password = password
        NavidromeSettings.shared.isConfigured = !serverAddress.isEmpty && !username.isEmpty
        
        isSaving = false
        showSavedAlert = true
    }
}

#Preview {
    SettingView()
}
