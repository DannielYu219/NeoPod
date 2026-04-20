import SwiftUI
import AVFoundation
import MediaPlayer
import CoreHaptics
internal import Combine

// MARK: - Music View Model

@MainActor
class MusicViewModel: ObservableObject {
    @Published var displayItems: [MusicDisplayItem] = []
    @Published var remoteSongs: [Song] = []
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var errorMessage: String?
    
    private let cacheKey = "cachedSongIDs_v2"
    private var cachedSongCount: Int = 0
    @Published var loadedCount = 0
    
    var hasCachedContent: Bool { !displayItems.isEmpty }
    
    func loadContent() async {
        if !displayItems.isEmpty { return }
        isLoading = true
        loadingStatus = "Scanning..."
        errorMessage = nil
        defer { isLoading = false }
        
        displayItems = []
        await loadLocalFiles()
        
        let cachedSongs = loadCachedSongs()
        if !cachedSongs.isEmpty {
            let items = cachedSongs.map { song in
                MusicDisplayItem(id: song.id, title: song.title, artist: song.artist, localURL: nil, remoteID: song.id, duration: song.duration.map { Double($0) })
            }
            displayItems.append(contentsOf: items)
            remoteSongs = cachedSongs
            loadedCount = cachedSongs.count
        }
        
        if NavidromeSettings.shared.isConfigured {
            loadingStatus = "Checking server..."
            await refreshRemoteSongsIfNeeded()
        }
        
        displayItems.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    func refreshContent() async {
        displayItems = []
        remoteSongs = []
        cachedSongCount = 0
        UserDefaults.standard.removeObject(forKey: cacheKey)
        await loadContent()
    }
    
    private func loadLocalFiles() async {
        guard let musicURL = FileSystemManager.musicFolderURL() else { return }
        
        let foundFiles = await Task.detached(priority: .userInitiated) { () -> [URL] in
            var results: [URL] = []
            let allowedExtensions = ["mp3", "m4a", "aac", "wav", "flac", "alac", "aiff", "caf"]
            let accessing = musicURL.startAccessingSecurityScopedResource()
            defer { if accessing { musicURL.stopAccessingSecurityScopedResource() } }
            
            if let enumerator = FileManager.default.enumerator(at: musicURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    if allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
                        results.append(fileURL)
                    }
                }
            }
            return results
        }.value
        
        let localItems = foundFiles.map { url in
            MusicDisplayItem(id: url.absoluteString, title: url.deletingPathExtension().lastPathComponent, artist: nil, localURL: url, remoteID: nil, duration: nil)
        }
        displayItems.append(contentsOf: localItems)
    }
    
    private func refreshRemoteSongsIfNeeded() async {
        loadingStatus = "Loading albums..."
        do {
            let response = try await NavidromeAPI.shared.getAlbumList2(type: "alphabeticalByName", offset: 0, size: 500)
            guard let albums = response.subsonicResponse.albumList2?.album, !albums.isEmpty else { return }
            
            let serverAlbumCount = albums.count
            if serverAlbumCount != cachedSongCount || cachedSongCount == 0 {
                loadingStatus = "Loading \(albums.count) albums..."
                var allSongs: [Song] = []
                
                for batchStart in stride(from: 0, to: albums.count, by: 10) {
                    let batchEnd = min(batchStart + 10, albums.count)
                    let batch = Array(albums[batchStart..<batchEnd])
                    
                    let batchSongs = await withTaskGroup(of: [Song].self) { group in
                        for album in batch {
                            group.addTask {
                                do {
                                    let response = try await NavidromeAPI.shared.getAlbum(id: album.id)
                                    return response.subsonicResponse.album?.song ?? []
                                } catch { return [] }
                            }
                        }
                        var results: [Song] = []
                        for await songs in group { results.append(contentsOf: songs) }
                        return results
                    }
                    allSongs.append(contentsOf: batchSongs)
                }
                
                await updateRemoteSongs(allSongs)
            }
        } catch {
            errorMessage = "Server error: \(error.localizedDescription)"
        }
    }
    
    private func updateRemoteSongs(_ songs: [Song]) async {
        displayItems.removeAll { $0.remoteID != nil }
        remoteSongs = songs
        cachedSongCount = songs.count
        
        let items = songs.map { song in
            MusicDisplayItem(id: song.id, title: song.title, artist: song.artist, localURL: nil, remoteID: song.id, duration: song.duration.map { Double($0) })
        }
        displayItems.append(contentsOf: items)
        loadedCount = songs.count
        saveSongsToCache(songs)
    }
    
    private func saveSongsToCache(_ songs: [Song]) {
        do {
            let data = try JSONEncoder().encode(songs)
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(songs.count, forKey: "cachedSongCount_v2")
            cachedSongCount = songs.count
        } catch {}
    }
    
    private func loadCachedSongs() -> [Song] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        do {
            let songs = try JSONDecoder().decode([Song].self, from: data)
            cachedSongCount = UserDefaults.standard.integer(forKey: "cachedSongCount_v2")
            return songs
        } catch { return [] }
    }
}

// MARK: - 显示模型

struct MusicDisplayItem: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String?
    let localURL: URL?
    let remoteID: String?
    var duration: Double?
    
    static func == (lhs: MusicDisplayItem, rhs: MusicDisplayItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Music Player Model

class MusicPlayerModel: NSObject, ObservableObject {
    static let shared = MusicPlayerModel()
    
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 1
    @Published var currentItem: MusicDisplayItem?
    @Published var isBuffering = false
    @Published var repeatMode: RepeatMode = .one
    
    enum RepeatMode: Int {
        case off = 0, one = 1, all = 2
        var icon: String { switch self { case .off: return "repeat"; case .one: return "repeat.1"; case .all: return "repeat" } }
        var isActive: Bool { self != .off }
    }
    
    var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var playlist: [MusicDisplayItem] = []
    private var currentIndex: Int = 0
    
    override init() {
        super.init()
        setupAudioSession()
        setupRemoteTransportControls()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {}
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        commandCenter.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        commandCenter.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in self?.playNext(); return .success }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in self?.playPrevious(); return .success }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }
    
    func setPlaylist(_ items: [MusicDisplayItem], startIndex: Int = 0) {
        playlist = items
        currentIndex = startIndex
    }
    
    func playNext() {
        guard !playlist.isEmpty else { return }
        switch repeatMode {
        case .one: seek(to: 0); play()
        case .all: currentIndex = (currentIndex + 1) % playlist.count; playCurrentItem()
        case .off: if currentIndex + 1 < playlist.count { currentIndex += 1; playCurrentItem() }
        }
    }
    
    func playPrevious() {
        guard !playlist.isEmpty else { return }
        if progress > 3 { seek(to: 0); return }
        switch repeatMode {
        case .one: seek(to: 0); play()
        case .all: currentIndex = (currentIndex - 1 + playlist.count) % playlist.count; playCurrentItem()
        case .off: if currentIndex > 0 { currentIndex -= 1; playCurrentItem() } else { seek(to: 0) }
        }
    }
    
    func toggleRepeatMode() {
        repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .one
    }
    
    func playCurrentItem() {
        guard !playlist.isEmpty, currentIndex < playlist.count else { return }
        let item = playlist[currentIndex]
        
        if let localURL = item.localURL {
            playLocal(url: localURL, displayItem: item)
        } else if let remoteID = item.remoteID {
            do {
                let streamURL = try NavidromeAPI.shared.getStreamURL(id: remoteID)
                playStream(url: streamURL, displayItem: item)
            } catch {}
        }
    }
    
    func playLocal(url: URL, displayItem: MusicDisplayItem) {
        let accessing = url.startAccessingSecurityScopedResource()
        if let presetDuration = displayItem.duration, presetDuration > 0 {
            self.duration = presetDuration
        } else {
            self.duration = 1
            Task { await self.loadDurationFromAsset(url: url) }
        }
        setupPlayer(url: url, item: displayItem)
        if accessing { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { url.stopAccessingSecurityScopedResource() } }
    }
    
    func playStream(url: URL, displayItem: MusicDisplayItem) {
        if let presetDuration = displayItem.duration, presetDuration > 0 { self.duration = presetDuration }
        else { self.duration = 180 }
        setupPlayer(url: url, item: displayItem)
    }
    
    private func loadDurationFromAsset(url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let dur = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(dur)
            if !seconds.isNaN && !seconds.isInfinite && seconds > 0 {
                await MainActor.run { self.duration = seconds; self.updateNowPlayingInfo() }
            }
        } catch {}
    }
    
    private func setupPlayer(url: URL, item: MusicDisplayItem) {
        if item == currentItem, let p = player, (p.rate != 0 || isPlaying) { return }
        
        if let observer = timeObserver { player?.removeTimeObserver(observer); timeObserver = nil }
        
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        currentItem = item
        isPlaying = true
        progress = 0
        player?.play()
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            if !seconds.isNaN { self.progress = seconds; self.updateNowPlayingInfo() }
        }
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            self?.handlePlaybackEnd()
        }
        
        updateNowPlayingInfo(title: item.title, artist: item.artist)
    }
    
    private func handlePlaybackEnd() {
        switch repeatMode {
        case .one: seek(to: 0); play()
        case .all: playNext()
        case .off: isPlaying = false; progress = 0; updateNowPlayingInfoState()
        }
    }
    
    func togglePlayPause() { if isPlaying { pause() } else { play() } }
    func play() { player?.play(); isPlaying = true; updateNowPlayingInfoState() }
    func pause() { player?.pause(); isPlaying = false; updateNowPlayingInfoState() }
    func stop() { player?.pause(); player?.seek(to: .zero); progress = 0; isPlaying = false; updateNowPlayingInfoState() }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] completed in
            if completed { self?.progress = time; self?.updateNowPlayingInfoState() }
        }
    }
    
    private func updateNowPlayingInfo(title: String? = nil, artist: String? = nil) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        if let title = title ?? currentItem?.title { info[MPMediaItemPropertyTitle] = title }
        if let artist = artist ?? currentItem?.artist { info[MPMediaItemPropertyArtist] = artist }
        let validDuration = (!duration.isNaN && duration > 0) ? duration : currentItem?.duration ?? 0
        info[MPMediaItemPropertyPlaybackDuration] = validDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updateNowPlayingInfoState() { updateNowPlayingInfo() }
}

// MARK: - MusicView

struct MusicView: View {
    @Binding private var isShowingPlayer: Bool
    @StateObject private var viewModel = MusicViewModel()
    @ObservedObject private var playerModel = MusicPlayerModel.shared
    @ObservedObject private var scrollManager = CameraScrollManager.shared
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    @State private var scrollHaptic: UISelectionFeedbackGenerator?
    @State private var selectionHaptic: UIImpactFeedbackGenerator?
    @State private var currentCenterIndex: Int? = nil
    @State private var isCameraControlEnabled: Bool = false
    
    init(isShowingPlayer: Binding<Bool>) {
        self._isShowingPlayer = isShowingPlayer
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if isShowingPlayer, let current = playerModel.currentItem {
                    playerView(for: current)
                        .transition(.move(edge: .trailing))
                } else {
                    listView
                        .transition(.move(edge: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            HiddenCameraOverlay(isActive: $isCameraControlEnabled)
                .allowsHitTesting(isCameraControlEnabled)
        }
        .task {
            scrollHaptic = UISelectionFeedbackGenerator()
            selectionHaptic = UIImpactFeedbackGenerator(style: .medium)
            scrollHaptic?.prepare()
            selectionHaptic?.prepare()
            await viewModel.loadContent()
        }
        .onAppear {
            scrollManager.activateCameraControl()
            isCameraControlEnabled = true
        }
        .onDisappear {
            scrollManager.deactivateCameraControl()
            isCameraControlEnabled = false
        }
    }
    
    private var listView: some View {
        GeometryReader { listProxy in
            let containerMidY = listProxy.size.height / 2
            
            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView().tint(.white)
                                    Text(viewModel.loadingStatus)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.8))
                                } else if viewModel.loadedCount > 0 {
                                    Text("\(viewModel.loadedCount) songs")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                if !viewModel.isLoading {
                                    Button { Task { await viewModel.refreshContent() } } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(accent)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                            
                            // List 内容
                            if viewModel.displayItems.isEmpty && !viewModel.isLoading {
                                VStack(spacing: 12) {
                                    Image(systemName: "music.note.list").font(.system(size: 48)).opacity(0.5)
                                    Text("No music").font(.system(size: 18, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 100)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(viewModel.displayItems.enumerated()), id: \.element.id) { index, item in
                                        MusicRowView(
                                            item: item,
                                            index: index,
                                            accent: accent,
                                            containerMidY: containerMidY,
                                            isCurrentTrack: playerModel.currentItem?.id == item.id,
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
                                                playSong(item: item)
                                                withAnimation(.easeOut(duration: 0.28)) { isShowingPlayer = true }
                                            }
                                        )
                                        .id(item.id)
                                    }
                                }
                                .padding(.bottom, 140)
                            }
                        }
                    }
                    .onAppear {
                        // 进入列表页时，如果有正在播放的歌曲，滚动到对应位置
                        if let currentId = playerModel.currentItem?.id {
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo(currentId, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: scrollManager.scrollOffset) { newOffset in
                        // 响应相机缩放驱动的滚动
                        if scrollManager.isCameraControlActive, !viewModel.displayItems.isEmpty {
                            let targetIndex = max(0, min(viewModel.displayItems.count - 1, Int(newOffset / 72)))
                            let targetItem = viewModel.displayItems[targetIndex]
                            withAnimation(.easeOut(duration: 0.1)) {
                                scrollProxy.scrollTo(targetItem.id, anchor: .center)
                            }
                        }
                    }
                }
                .coordinateSpace(name: "musicList")
                
                // 底部渐变背景
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
    
    private func playSong(item: MusicDisplayItem) {
        playerModel.setPlaylist(viewModel.displayItems, startIndex: viewModel.displayItems.firstIndex(where: { $0.id == item.id }) ?? 0)
        
        if let localURL = item.localURL {
            playerModel.playLocal(url: localURL, displayItem: item)
        } else if let remoteID = item.remoteID {
            do {
                let streamURL = try NavidromeAPI.shared.getStreamURL(id: remoteID)
                playerModel.playStream(url: streamURL, displayItem: item)
            } catch {}
        }
    }
    
    private func playerView(for item: MusicDisplayItem) -> some View {
        VStack(spacing: 0) {
            // Header (NOW PLAYING)
            HStack {
                Spacer()
                Text("NOW PLAYING")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                Spacer()
            }
            .padding(.top, 8)
            
            Spacer()
            
            // 歌曲信息
            VStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 36, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if let artist = item.artist {
                    Text(artist)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 进度条
            VStack(spacing: 6) {
                Slider(value: Binding(get: { playerModel.progress }, set: { playerModel.seek(to: $0) }), in: 0...max(playerModel.duration, 1))
                    .accentColor(accent)
                
                HStack {
                    Text(timeString(from: playerModel.progress))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .monospacedDigit()
                    Spacer()
                    Text("-\(timeString(from: max(0, playerModel.duration - playerModel.progress)))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 20)
            
            // 下方控件
            HStack(spacing: 40) {
                Button { playerModel.toggleRepeatMode() } label: {
                    Image(systemName: playerModel.repeatMode.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(playerModel.repeatMode.isActive ? accent : .white.opacity(0.5))
                }.buttonStyle(.plain)
                
                Button { playerModel.playPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(.white)
                }.buttonStyle(.plain)
                
                Button { playerModel.togglePlayPause() } label: {
                    ZStack {
                        Circle().fill(accent).frame(width: 64, height: 64)
                        Image(systemName: playerModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.black)
                            .offset(x: playerModel.isPlaying ? 0 : 2)
                    }
                }.buttonStyle(.plain)
                
                Button { playerModel.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(.white)
                }.buttonStyle(.plain)
                
                Image(systemName: playerModel.repeatMode.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.clear)
            }
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func timeString(from value: Double) -> String {
        let totalSeconds = Int(value)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - MusicRow View (保持不变，已包含 ID)

private struct MusicRowView: View {
    let item: MusicDisplayItem
    let index: Int
    let accent: Color
    let containerMidY: CGFloat
    let isCurrentTrack: Bool
    let onFocused: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("musicList"))
                let distance = abs(frame.midY - containerMidY)
                
                let threshold: CGFloat = 36 
                let scale = max(0.86, 1.08 - (distance / 520))
                let opacity = max(0.55, 1.0 - (distance / 700))
                
                HStack(spacing: 14) {
                    Image(systemName: isCurrentTrack ? "waveform" : "music.note")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(isCurrentTrack ? accent : .white.opacity(0.75))
                        .frame(width: 30, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 32, weight: .regular, design: .rounded))
                            .foregroundColor((distance < 30 || isCurrentTrack) ? accent : .white)
                            .lineLimit(1)
                        
                        if let artist = item.artist {
                            Text(artist)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
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

