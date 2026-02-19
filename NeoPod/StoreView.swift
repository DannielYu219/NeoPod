import SwiftUI

struct StoreView: View {
    @StateObject private var viewModel = StoreViewModel()

    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
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
            let tilePadding: CGFloat = 20
            let availableWidth = listProxy.size.width - (tilePadding * 2)
            let columnSpacing: CGFloat = 12
            let tileWidth = (availableWidth - columnSpacing) / 2

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("STORE")
                            .font(.system(size: 34, weight: .black))
                            .foregroundColor(.white)

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
                    }

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
                        LazyVGrid(
                            columns: [
                                GridItem(.fixed(tileWidth), spacing: columnSpacing),
                                GridItem(.fixed(tileWidth), spacing: columnSpacing)
                            ],
                            alignment: .leading,
                            spacing: columnSpacing
                        ) {
                            ForEach(viewModel.apps) { app in
                                let color = tileColor(for: app)
                                NavigationLink {
                                    StoreDetailView(
                                        appId: app.id,
                                        viewModel: viewModel,
                                        accent: accent,
                                        tileColor: color
                                    )
                                } label: {
                                    StoreTileView(
                                        app: app,
                                        size: tileWidth,
                                        color: color,
                                        isInstalled: viewModel.isAppInstalled(app.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, tilePadding)
            }
        }
    }

    private func tileColor(for app: AppInfo) -> Color {
        let palette: [Color] = [
            Color(red: 0.19, green: 0.63, blue: 0.82),
            Color(red: 0.18, green: 0.54, blue: 0.38),
            Color(red: 0.68, green: 0.25, blue: 0.56),
            Color(red: 0.85, green: 0.42, blue: 0.08),
            Color(red: 0.36, green: 0.40, blue: 0.78),
            Color(red: 0.62, green: 0.17, blue: 0.20)
        ]
        let index = abs(app.id.hashValue) % palette.count
        return palette[index]
    }
}

private struct StoreTileView: View {
    let app: AppInfo
    let size: CGFloat
    let color: Color
    let isInstalled: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(color)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tileMonogram)
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white.opacity(0.85))

                    Spacer()

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                Text(app.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text("v\(app.version)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(12)
        }
        .frame(width: size, height: size)
        .cornerRadius(6)
    }

    private var tileMonogram: String {
        let trimmed = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1)).uppercased()
    }
}

private struct StoreDetailView: View {
    let appId: String
    @ObservedObject var viewModel: StoreViewModel
    let accent: Color
    let tileColor: Color

    @StateObject private var detailModel: StoreDetailViewModel

    init(appId: String, viewModel: StoreViewModel, accent: Color, tileColor: Color) {
        self.appId = appId
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.accent = accent
        self.tileColor = tileColor
        _detailModel = StateObject(wrappedValue: StoreDetailViewModel(appId: appId))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if detailModel.isLoading {
                detailLoadingView
            } else if let errorMessage = detailModel.errorMessage {
                detailErrorView(errorMessage)
            } else if let detail = detailModel.detail {
                detailContent(detail)
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detailModel.loadDetail()
        }
    }

    private var detailLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: accent))
                .scaleEffect(1.3)

            Text("Loading details...")
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func detailErrorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red.opacity(0.8))

            Text("Failed to load")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Button {
                detailModel.loadDetail()
            } label: {
                Text("Retry")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(accent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func detailContent(_ detail: AppDetail) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(tileColor)
                        .frame(height: 170)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.name)
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(.white)

                        Text("v\(detail.version)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(16)
                }

                Text(detail.description)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))

                detailMetaRow(title: "Size", value: detail.formattedSize)
                detailMetaRow(title: "Last updated", value: detail.last_updated)

                if !detail.files.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Files")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))

                        ForEach(detail.files, id: \.self) { file in
                            Text(file)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }

                installSection(detail)
            }
            .padding(20)
        }
    }

    private func detailMetaRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }

    private func installSection(_ detail: AppDetail) -> some View {
        let isInstalled = viewModel.isAppInstalled(appId)
        let isInstalling = viewModel.installingAppId == appId
        let isUninstalling = viewModel.uninstallingAppId == appId

        return VStack(alignment: .leading, spacing: 12) {
            if isInstalled {
                Text("Installed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }

            HStack(spacing: 12) {
                if isInstalling || isUninstalling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: accent))
                        .scaleEffect(1.1)

                    Text(isInstalling ? "Installing..." : "Uninstalling...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                } else if isInstalled {
                    Button {
                        viewModel.uninstallApp(AppInfo(
                            id: detail.id,
                            name: detail.name,
                            version: detail.version,
                            description: detail.description,
                            icon: detail.icon,
                            size: detail.size,
                            last_updated: detail.last_updated
                        ))
                    } label: {
                        Text("Uninstall")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        viewModel.installApp(AppInfo(
                            id: detail.id,
                            name: detail.name,
                            version: detail.version,
                            description: detail.description,
                            icon: detail.icon,
                            size: detail.size,
                            last_updated: detail.last_updated
                        ))
                    } label: {
                        Text("Install")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(accent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

@MainActor
class StoreDetailViewModel: ObservableObject {
    @Published var detail: AppDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let appId: String

    init(appId: String) {
        self.appId = appId
    }

    func loadDetail() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let detail = try await StoreAPI.shared.getAppDetail(appId: appId)
                withAnimation(.easeOut(duration: 0.25)) {
                    self.detail = detail
                    self.isLoading = false
                }
            } catch {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
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
