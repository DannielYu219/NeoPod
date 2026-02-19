import SwiftUI
internal import Combine

struct StoreView: View {
    @StateObject private var viewModel = StoreViewModel()
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !StoreSettings.shared.isConfigured {
                notConfiguredView
            } else if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                appListView
            }
        }
        .task {
            if StoreSettings.shared.isConfigured {
                viewModel.loadApps()
            }
        }
    }
    
    private var notConfiguredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.5))
            
            Text("Store Not Configured")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(.white)
            
            Text("Please configure the store server address in Settings")
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: accent))
                .scaleEffect(1.5)
            
            Text("Loading apps...")
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.8))
            
            Text("Error")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(.white)
            
            Text(error)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            Button {
                viewModel.loadApps()
            } label: {
                Text("Retry")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(accent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var appListView: some View {
        GeometryReader { listProxy in
            let containerMidY = listProxy.size.height / 2
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(viewModel.apps.count) apps available")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Button {
                            viewModel.loadApps()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    
                    if viewModel.apps.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 48))
                                .opacity(0.5)
                            Text("No apps available")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.apps) { app in
                                StoreRowView(
                                    app: app,
                                    accent: accent,
                                    containerMidY: containerMidY,
                                    isInstalled: viewModel.isAppInstalled(app.id),
                                    isInstalling: viewModel.installingAppId == app.id,
                                    isUninstalling: viewModel.uninstallingAppId == app.id,
                                    onInstall: {
                                        viewModel.installApp(app)
                                    },
                                    onUninstall: {
                                        viewModel.uninstallApp(app)
                                    }
                                )
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .coordinateSpace(name: "storeList")
        }
    }
}

private struct StoreRowView: View {
    let app: AppInfo
    let accent: Color
    let containerMidY: CGFloat
    let isInstalled: Bool
    let isInstalling: Bool
    let isUninstalling: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    
    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("storeList"))
            let distance = abs(frame.midY - containerMidY)
            
            let scale = max(0.86, 1.08 - (distance / 520))
            let opacity = max(0.55, 1.0 - (distance / 700))
            
            HStack(spacing: 14) {
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "app.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(distance < 30 ? accent : .white.opacity(0.75))
                    .frame(width: 30, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(app.name)
                            .font(.system(size: 28, weight: .regular, design: .rounded))
                            .foregroundColor(distance < 30 ? accent : .white)
                            .lineLimit(1)
                        
                        Text("v\(app.version)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text(app.description)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isInstalling || isUninstalling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isUninstalling ? .red : accent))
                        .scaleEffect(0.8)
                } else if isInstalled {
                    Button {
                        onUninstall()
                    } label: {
                        Image(systemName: "trash.circle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onInstall()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .scaleEffect(scale, anchor: .leading)
            .opacity(opacity)
        }
        .frame(height: 80)
    }
}

@MainActor
class StoreViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var installingAppId: String?
    @Published var uninstallingAppId: String?
    
    func loadApps() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let apps = try await StoreAPI.shared.getApps()
                withAnimation(.easeOut(duration: 0.28)) {
                    self.apps = apps
                    self.isLoading = false
                }
            } catch {
                withAnimation(.easeOut(duration: 0.28)) {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func installApp(_ app: AppInfo) {
        installingAppId = app.id
        
        Task {
            do {
                let zipFile = try await StoreAPI.shared.downloadApp(appId: app.id)
                try await StoreAPI.shared.installApp(from: zipFile, appId: app.id)
                
                await MainActor.run {
                    installingAppId = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to install \(app.name): \(error.localizedDescription)"
                    installingAppId = nil
                }
            }
        }
    }
    
    func uninstallApp(_ app: AppInfo) {
        uninstallingAppId = app.id
        
        Task {
            do {
                try await StoreAPI.shared.uninstallApp(appId: app.id)
                
                await MainActor.run {
                    uninstallingAppId = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to uninstall \(app.name): \(error.localizedDescription)"
                    uninstallingAppId = nil
                }
            }
        }
    }
    
    func isAppInstalled(_ appId: String) -> Bool {
        guard let programURL = FileSystemManager.programFolderURL() else { return false }
        let appURL = programURL.appendingPathComponent(appId, isDirectory: true)
        return FileManager.default.fileExists(atPath: appURL.path)
    }
}

#if DEBUG
#Preview {
    StoreView()
}
#endif