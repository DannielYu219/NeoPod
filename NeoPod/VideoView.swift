// VideoView.swift
// 作用：视频播放视图，支持本地视频和SMB网络视频播放
// 依赖：SwiftUI, AVFoundation, SMBClient, SMBSettings, FileSystemManager
// 输入：用户选择视频源（本地/SMB）
// 输出：视频列表、全屏视频播放界面
// 实现：使用AVPlayerViewController播放视频，支持本地文件和SMB网络流，全屏显示视频画面，根据视频分辨率自动设置横竖屏

import SwiftUI
import AVFoundation
import MediaPlayer
internal import Combine
import AVKit

enum VideoSource {
    case local
    case smb
}

struct VideoDisplayItem: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL?
    let smbPath: String?
    let duration: Double?
    let source: VideoSource
    
    static func == (lhs: VideoDisplayItem, rhs: VideoDisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class VideoViewModel: ObservableObject {
    @Published var displayItems: [VideoDisplayItem] = []
    @Published var smbFiles: [SMBFileItem] = []
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var errorMessage: String?
    @Published var currentSource: VideoSource = .local
    @Published var smbCurrentPath: String = "/"
    @Published var smbPathHistory: [String] = []
    
    private let videoExtensions = ["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts", "m3u8", "mpg", "mpeg"]
    
    func loadContent() async {
        if !displayItems.isEmpty { return }
        await loadLocalFiles()
    }
    
    func loadLocalFiles() async {
        isLoading = true
        loadingStatus = "Scanning local videos..."
        errorMessage = nil
        currentSource = .local
        defer { isLoading = false }
        
        displayItems = []
        
        guard let videoURL = FileSystemManager.videoFolderURL() else { return }
        
        let foundFiles = await Task.detached(priority: .userInitiated) { () -> [URL] in
            var results: [URL] = []
            let accessing = videoURL.startAccessingSecurityScopedResource()
            defer { if accessing { videoURL.stopAccessingSecurityScopedResource() } }
            
            if let enumerator = FileManager.default.enumerator(at: videoURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    if self.videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                        results.append(fileURL)
                    }
                }
            }
            return results
        }.value
        
        let localItems = foundFiles.map { url in
            VideoDisplayItem(
                id: url.absoluteString,
                title: url.deletingPathExtension().lastPathComponent,
                url: url,
                smbPath: nil,
                duration: nil,
                source: .local
            )
        }
        displayItems = localItems.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    func loadSMBFiles(path: String = "/") async {
        guard SMBClient.shared.isConnected else {
            errorMessage = "SMB not connected"
            return
        }
        
        isLoading = true
        loadingStatus = "Loading SMB files..."
        errorMessage = nil
        currentSource = .smb
        defer { isLoading = false }
        
        do {
            let files = try await SMBClient.shared.listDirectory(path: path)
            smbFiles = files
            smbCurrentPath = path
            
            let videoItems = files.filter { !$0.isDirectory && videoExtensions.contains(URL(fileURLWithPath: $0.name).pathExtension.lowercased()) }.map { file in
                VideoDisplayItem(
                    id: file.path,
                    title: URL(fileURLWithPath: file.name).deletingPathExtension().lastPathComponent,
                    url: nil,
                    smbPath: file.path,
                    duration: nil,
                    source: .smb
                )
            }
            displayItems = videoItems
        } catch {
            errorMessage = "Failed to load SMB files: \(error.localizedDescription)"
        }
    }
    
    func navigateToSMBDirectory(_ item: SMBFileItem) async {
        if item.isDirectory {
            smbPathHistory.append(smbCurrentPath)
            await loadSMBFiles(path: item.path)
        }
    }
    
    func navigateBackSMB() async {
        if let previousPath = smbPathHistory.popLast() {
            await loadSMBFiles(path: previousPath)
        }
    }
    
    func refreshContent() async {
        displayItems = []
        smbFiles = []
        if currentSource == .local {
            await loadLocalFiles()
        } else {
            await loadSMBFiles(path: smbCurrentPath)
        }
    }
}

class VideoPlayerModel: NSObject, ObservableObject {
    static let shared = VideoPlayerModel()
    
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 1
    @Published var currentItem: VideoDisplayItem?
    @Published var showControls: Bool = true
    
    var playerController: AVPlayerViewController?
    var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var controlsHideTask: Task<Void, Never>?
    
    override init() {
        super.init()
        setupAudioSession()
        setupRemoteTransportControls()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {}
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        commandCenter.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
    }
    
    func playLocal(url: URL, displayItem: VideoDisplayItem) {
        let accessing = url.startAccessingSecurityScopedResource()
        setupPlayer(url: url, item: displayItem)
        if accessing { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { url.stopAccessingSecurityScopedResource() } }
    }
    
    func playSMB(path: String, displayItem: VideoDisplayItem) async {
        do {
            let data = try await SMBClient.shared.readFile(at: path)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try data.write(to: tempURL)
            
            await MainActor.run {
                self.setupPlayer(url: tempURL, item: displayItem)
            }
        } catch {
            print("Failed to play SMB file: \(error)")
        }
    }
    
    private func setupPlayer(url: URL, item: VideoDisplayItem) {
        if let observer = timeObserver { player?.removeTimeObserver(observer); timeObserver = nil }
        
        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        currentItem = item
        isPlaying = true
        progress = 0
        showControls = true
        
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        playerController = controller
        
        player?.play()
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            if !seconds.isNaN { self.progress = seconds }
        }
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            self?.isPlaying = false
            self?.progress = 0
        }
        
        Task {
            do {
                let dur = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(dur)
                if !seconds.isNaN && !seconds.isInfinite && seconds > 0 {
                    await MainActor.run { self.duration = seconds }
                }
            } catch {}
        }
        
        scheduleControlsHide()
    }
    
    func toggleControls() {
        showControls.toggle()
        if showControls {
            scheduleControlsHide()
        } else {
            controlsHideTask?.cancel()
        }
    }
    
    func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    if self.isPlaying {
                        self.showControls = false
                    }
                }
            }
        }
    }
    
    func togglePlayPause() { 
        if isPlaying { pause() } else { play() }
    }
    
    func play() { 
        player?.play()
        isPlaying = true
        scheduleControlsHide()
    }
    
    func pause() { 
        player?.pause()
        isPlaying = false
        showControls = true
        controlsHideTask?.cancel()
    }
    
    func stop() { 
        player?.pause()
        player?.seek(to: .zero)
        progress = 0
        isPlaying = false
        playerController = nil
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] completed in
            if completed { self?.progress = time }
        }
    }
    
    func seekForward(_ seconds: Double = 10) {
        let newTime = min(progress + seconds, duration)
        seek(to: newTime)
    }
    
    func seekBackward(_ seconds: Double = 10) {
        let newTime = max(progress - seconds, 0)
        seek(to: newTime)
    }
}

struct VideoView: View {
    @Binding private var isShowingPlayer: Bool
    @StateObject private var viewModel = VideoViewModel()
    @ObservedObject private var playerModel = VideoPlayerModel.shared
    @ObservedObject private var smbSettings = SMBSettings.shared
    @ObservedObject private var smbClient = SMBClient.shared
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    @State private var showSMBSettings = false
    @State private var scrollHaptic: UISelectionFeedbackGenerator?
    @State private var selectionHaptic: UIImpactFeedbackGenerator?
    @State private var currentCenterIndex: Int? = nil
    
    init(isShowingPlayer: Binding<Bool> = .constant(false)) {
        self._isShowingPlayer = isShowingPlayer
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if isShowingPlayer, let current = playerModel.currentItem {
                    FullScreenVideoPlayer(item: current, accent: accent, onClose: {
                        playerModel.stop()
                        withAnimation(.easeOut(duration: 0.28)) {
                            isShowingPlayer = false
                        }
                    })
                    .transition(.opacity)
                } else {
                    videoListView
                        .transition(.move(edge: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            scrollHaptic = UISelectionFeedbackGenerator()
            selectionHaptic = UIImpactFeedbackGenerator(style: .medium)
            scrollHaptic?.prepare()
            selectionHaptic?.prepare()
            await viewModel.loadContent()
        }
        .sheet(isPresented: $showSMBSettings) {
            SMBSettingsView()
        }
    }
    
    private var videoListView: some View {
        GeometryReader { listProxy in
            let containerMidY = listProxy.size.height / 2
            
            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            headerView
                            
                            if viewModel.displayItems.isEmpty && !viewModel.isLoading {
                                emptyStateView
                            } else {
                                videoListContent(containerMidY: containerMidY)
                            }
                        }
                    }
                    .coordinateSpace(name: "videoList")
                }
                
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.8), .black]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .allowsHitTesting(false)
                .padding(.horizontal, -24)
            }
        }
        .ignoresSafeArea(.all)
    }
    
    private var headerView: some View {
        HStack {
            if viewModel.isLoading {
                ProgressView().tint(.white)
                Text(viewModel.loadingStatus)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("\(viewModel.displayItems.count) videos")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                sourceToggleButtons
                
                Button {
                    Task { await viewModel.refreshContent() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(accent)
                }.buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
    
    private var sourceToggleButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.loadLocalFiles() }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(viewModel.currentSource == .local ? accent : .white.opacity(0.5))
            }.buttonStyle(.plain)
            
            Button {
                if smbClient.isConnected {
                    Task { await viewModel.loadSMBFiles() }
                } else {
                    showSMBSettings = true
                }
            } label: {
                Image(systemName: "network")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(viewModel.currentSource == .smb ? accent : .white.opacity(0.5))
            }.buttonStyle(.plain)
            
            if smbSettings.isConfigured && !smbClient.isConnected {
                Button {
                    showSMBSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 48))
                .opacity(0.5)
            Text("No videos")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            if viewModel.currentSource == .local {
                Text("Add videos to the video folder")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
    
    private func videoListContent(containerMidY: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if viewModel.currentSource == .smb && !viewModel.smbPathHistory.isEmpty {
                Button {
                    Task { await viewModel.navigateBackSMB() }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(accent)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.currentSource == .smb {
                ForEach(viewModel.smbFiles.filter { $0.isDirectory }) { item in
                    SMBDirectoryRow(item: item, accent: accent) {
                        Task { await viewModel.navigateToSMBDirectory(item) }
                    }
                }
            }
            
            ForEach(Array(viewModel.displayItems.enumerated()), id: \.element.id) { index, item in
                VideoRowView(
                    item: item,
                    index: index,
                    accent: accent,
                    containerMidY: containerMidY,
                    isCurrentVideo: playerModel.currentItem?.id == item.id,
                    onFocused: {
                        if currentCenterIndex != index {
                            currentCenterIndex = index
                            scrollHaptic?.selectionChanged()
                            scrollHaptic?.prepare()
                        }
                    },
                    onTap: {
                        selectionHaptic?.impactOccurred()
                        selectionHaptic?.prepare()
                        playVideo(item: item)
                        withAnimation(.easeOut(duration: 0.28)) { isShowingPlayer = true }
                    }
                )
                .id(item.id)
            }
        }
        .padding(.bottom, 140)
    }
    
    private func playVideo(item: VideoDisplayItem) {
        if let url = item.url {
            playerModel.playLocal(url: url, displayItem: item)
        } else if let smbPath = item.smbPath {
            Task {
                await playerModel.playSMB(path: smbPath, displayItem: item)
            }
        }
    }
}

struct FullScreenVideoPlayer: View {
    let item: VideoDisplayItem
    let accent: Color
    let onClose: () -> Void
    
    @ObservedObject private var playerModel = VideoPlayerModel.shared
    @State private var controlsVisible = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VideoPlayerViewControllerRepresentable(playerController: playerModel.playerController)
                    .ignoresSafeArea(.all)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                if playerModel.showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                playerModel.toggleControls()
            }
        }
        .ignoresSafeArea(.all)
        .statusBar(hidden: true)
        .onAppear {
            controlsVisible = playerModel.showControls
        }
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomControls
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.7)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .padding(12)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(item.title)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            Color.clear.frame(width: 48)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
    
    private var bottomControls: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                progressSlider
                
                HStack(spacing: 50) {
                    Button {
                        playerModel.seekBackward(15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        playerModel.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(accent)
                                .frame(width: 72, height: 72)
                            Image(systemName: playerModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .regular))
                                .foregroundColor(.black)
                                .offset(x: playerModel.isPlaying ? 0 : 3)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        playerModel.seekForward(15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom : 20)
            }
            .padding(.horizontal, 24)
        }
    }
    
    private var progressSlider: some View {
        VStack(spacing: 8) {
            Slider(value: Binding(
                get: { playerModel.progress },
                set: { playerModel.seek(to: $0) }
            ), in: 0...max(playerModel.duration, 1))
            .accentColor(accent)
            .tint(.white.opacity(0.3))
            
            HStack {
                Text(timeString(from: playerModel.progress))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
                
                Spacer()
                
                Text("-\(timeString(from: max(0, playerModel.duration - playerModel.progress)))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }
    
    private func timeString(from value: Double) -> String {
        let totalSeconds = Int(value)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct VideoPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let playerController: AVPlayerViewController?
    
    func makeUIViewController(context: Context) -> UIViewController {
        if let controller = playerController {
            return controller
        } else {
            let emptyController = UIViewController()
            emptyController.view.backgroundColor = .black
            return emptyController
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}

private struct VideoRowView: View {
    let item: VideoDisplayItem
    let index: Int
    let accent: Color
    let containerMidY: CGFloat
    let isCurrentVideo: Bool
    let onFocused: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("videoList"))
                let distance = abs(frame.midY - containerMidY)
                
                let threshold: CGFloat = 36
                let scale = max(0.86, 1.08 - (distance / 520))
                let opacity = max(0.55, 1.0 - (distance / 700))
                
                HStack(spacing: 14) {
                    Image(systemName: isCurrentVideo ? "play.rectangle.fill" : "play.rectangle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(isCurrentVideo ? accent : .white.opacity(0.75))
                        .frame(width: 30, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 32, weight: .regular, design: .rounded))
                            .foregroundColor((distance < 30 || isCurrentVideo) ? accent : .white)
                            .lineLimit(1)
                        
                        HStack {
                            if item.source == .smb {
                                Image(systemName: "network")
                                    .font(.system(size: 12))
                            }
                            Image(systemName: "film")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .scaleEffect(scale, anchor: .leading)
                .opacity(opacity)
                .onChange(of: frame.midY) { newValue in
                    if abs(newValue - containerMidY) < threshold {
                        onFocused()
                    }
                }
            }
            .frame(height: 72)
        }
        .buttonStyle(.plain)
    }
}

private struct SMBDirectoryRow: View {
    let item: SMBFileItem
    let accent: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(accent)
                    .frame(width: 30, alignment: .leading)
                
                Text(item.name)
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                    .foregroundColor(accent)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SMBSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SMBSettings.shared
    @ObservedObject private var client = SMBClient.shared
    
    @State private var showingAddServer = false
    @State private var editingServer: SMBServerConfig?
    @State private var isConnecting = false
    @State private var connectionError: String?
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    Section("SMB Servers") {
                        if settings.servers.isEmpty {
                            Text("No servers configured")
                                .foregroundColor(.white.opacity(0.5))
                        } else {
                            ForEach(settings.servers) { server in
                                ServerRowView(
                                    server: server,
                                    isConnected: client.currentServer?.id == server.id,
                                    accent: accent,
                                    onConnect: { await connectToServer(server) },
                                    onEdit: { editingServer = server },
                                    onDelete: { settings.removeServer(server) }
                                )
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    Section {
                        Button {
                            showingAddServer = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Add Server")
                            }
                            .foregroundColor(accent)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(.white)
            }
            .navigationTitle("SMB Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(accent)
                }
            }
            .sheet(isPresented: $showingAddServer) {
                SMBServerEditView(server: nil)
            }
            .sheet(item: $editingServer) { server in
                SMBServerEditView(server: server)
            }
        }
    }
    
    private func connectToServer(_ server: SMBServerConfig) async {
        isConnecting = true
        connectionError = nil
        
        do {
            try await client.connect(to: server)
        } catch {
            connectionError = error.localizedDescription
        }
        
        isConnecting = false
    }
}

private struct ServerRowView: View {
    let server: SMBServerConfig
    let isConnected: Bool
    let accent: Color
    let onConnect: () async -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(server.name)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                    }
                }
                
                Text("\(server.host):\(server.port)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                
                Text("\\\\\(server.shareName)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    Task { await onConnect() }
                } label: {
                    Image(systemName: isConnected ? "arrow.clockwise" : "link")
                        .foregroundColor(isConnected ? .green : accent)
                }
                .buttonStyle(.plain)
                
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
        }
    }
}

struct SMBServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SMBSettings.shared
    
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "445"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var shareName: String = ""
    @State private var domain: String = ""
    
    let server: SMBServerConfig?
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Form {
                    Section("Server Info") {
                        TextField("Display Name", text: $name)
                        TextField("Host", text: $host)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    Section("Authentication") {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        TextField("Domain (optional)", text: $domain)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    Section("Share") {
                        TextField("Share Name", text: $shareName)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(.white)
            }
            .navigationTitle(server == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.5))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveServer() }
                        .foregroundColor(accent)
                        .disabled(name.isEmpty || host.isEmpty || shareName.isEmpty)
                }
            }
            .onAppear {
                if let server = server {
                    name = server.name
                    host = server.host
                    port = String(server.port)
                    username = server.username
                    password = server.password
                    shareName = server.shareName
                    domain = server.domain
                }
            }
        }
    }
    
    private func saveServer() {
        let config = SMBServerConfig(
            id: server?.id ?? UUID(),
            name: name,
            host: host,
            port: Int(port) ?? 445,
            username: username,
            password: password,
            shareName: shareName,
            domain: domain
        )
        
        if server != nil {
            settings.updateServer(config)
        } else {
            settings.addServer(config)
        }
        
        dismiss()
    }
}

#Preview {
    NavigationStack {
        VideoView()
    }
}
