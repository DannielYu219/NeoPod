import SwiftUI
import WebKit

struct ProgramsView: View {
    @StateObject private var viewModel = ProgramsViewModel()
    @ObservedObject private var scrollManager = CameraScrollManager.shared
    var onFileSelected: ((HTMLFileInfo) -> Void)?
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            listView
            
            HiddenCameraOverlay()
        }
        .task {
            FileSystemManager.ensureAppFoldersExist()
            viewModel.loadHTMLFiles()
        }
        .onAppear {
            scrollManager.activateCameraControl()
        }
        .onDisappear {
            scrollManager.deactivateCameraControl()
        }
        .alert("Uninstall App", isPresented: $viewModel.showUninstallConfirm) {
            Button("Cancel", role: .cancel) {
                viewModel.appToUninstall = nil
            }
            Button("Uninstall", role: .destructive) {
                viewModel.confirmUninstall()
            }
        } message: {
            Text("Are you sure you want to uninstall \(viewModel.appToUninstall?.displayName ?? "this app")?")
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
    
    private var listView: some View {
        GeometryReader { listProxy in
            let containerMidY = listProxy.size.height / 2
            
            ScrollView(showsIndicators: false) { content(containerMidY: containerMidY) }
                .coordinateSpace(name: "programsList")
                .onChange(of: scrollManager.scrollOffset) { newOffset in
                    if scrollManager.isCameraControlActive, !viewModel.htmlFiles.isEmpty {
                    }
                }
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    scrollManager.deactivateCameraControl()
                }
        )
    }
    
    @ViewBuilder
    private func content(containerMidY: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(viewModel.htmlFiles.count) programs")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Button {
                    viewModel.loadHTMLFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
            
            if viewModel.htmlFiles.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .opacity(0.5)
                    Text("No programs")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Download apps from Store or place files in 'dev' folder")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.htmlFiles) { file in
                        ProgramRowView(
                            file: file,
                            accent: accent,
                            containerMidY: containerMidY,
                            isUninstalling: viewModel.uninstallingAppId == file.id,
                            onTap: {
                                onFileSelected?(file)
                            },
                            onUninstall: {
                                viewModel.requestUninstall(file)
                            }
                        )
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

private struct ProgramRowView: View {
    let file: HTMLFileInfo
    let accent: Color
    let containerMidY: CGFloat
    let isUninstalling: Bool
    let onTap: () -> Void
    let onUninstall: () -> Void
    
    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("programsList"))
            let distance = abs(frame.midY - containerMidY)
            
            let scale = max(0.86, 1.08 - (distance / 520))
            let opacity = max(0.55, 1.0 - (distance / 700))
            
            HStack(spacing: 14) {
                Image(systemName: file.folder == "program" ? "app.fill" : "doc.text.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(distance < 30 ? accent : .white.opacity(0.75))
                    .frame(width: 30, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(file.displayName)
                            .font(.system(size: 28, weight: .regular, design: .rounded))
                            .foregroundColor(distance < 30 ? accent : .white)
                            .lineLimit(1)
                        
                        if file.folder == "dev" {
                            Text("dev")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(formatDate(file.modificationDate))
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isUninstalling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                        .scaleEffect(0.8)
                } else if file.folder == "program" {
                    Button {
                        onUninstall()
                    } label: {
                        Image(systemName: "trash.circle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .scaleEffect(scale, anchor: .leading)
            .opacity(opacity)
            .onTapGesture {
                onTap()
            }
        }
        .frame(height: 80)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ProgramsView()
    }
}
#endif
