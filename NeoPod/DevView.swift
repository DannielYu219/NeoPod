import SwiftUI
import WebKit

struct DevView: View {
    @StateObject private var viewModel = DevViewModel()
    var onFileSelected: ((HTMLFileInfo) -> Void)?
    
    private let accent = Color(red: 0.96, green: 0.45, blue: 0.15)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            listView
        }
        .task {
            FileSystemManager.ensureAppFoldersExist()
            viewModel.loadHTMLFiles()
        }
    }
    
    private var listView: some View {
        GeometryReader { listProxy in
            let containerMidY = listProxy.size.height / 2
            
            ScrollView(showsIndicators: false) {
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
                            Text("No HTML files")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("Place .html files in 'dev' or 'program' folder")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.htmlFiles) { file in
                                DevRowView(
                                    file: file,
                                    accent: accent,
                                    containerMidY: containerMidY,
                                    onTap: {
                                        onFileSelected?(file)
                                    }
                                )
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .coordinateSpace(name: "devList")
        }
    }
}

private struct DevRowView: View {
    let file: HTMLFileInfo
    let accent: Color
    let containerMidY: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("devList"))
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
                            Text(file.name)
                                .font(.system(size: 28, weight: .regular, design: .rounded))
                                .foregroundColor(distance < 30 ? accent : .white)
                                .lineLimit(1)
                            
                            Text(file.folder)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        Text(formatDate(file.modificationDate))
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .scaleEffect(scale, anchor: .leading)
                .opacity(opacity)
            }
            .frame(height: 80)
        }
        .buttonStyle(.plain)
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
        DevView()
    }
}
#endif