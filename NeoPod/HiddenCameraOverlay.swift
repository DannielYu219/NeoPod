import SwiftUI

/// 隐藏相机界面叠层 - 非阻塞式手势捕获层
/// 作用：在 ScrollView 上叠加捏合手势识别，用户可直接用捏合手势控制滚动
/// 设计：不拦截原生触摸/鼠标滚轮，仅作为额外输入源并行工作
/// 无相机设备时自动降级，不影响应用正常使用
struct HiddenCameraOverlay: View {
    @ObservedObject private var scrollManager = CameraScrollManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    // 捏合手势 - 不阻塞原生滚动
                    MagnificationGesture()
                        .onChanged { value in
                            // 将捏合值映射到 0.0-1.0 范围
                            let normalizedZoom = max(0.0, min(1.0, (value - 1.0) / 4.0))
                            scrollManager.updateZoomLevel(normalizedZoom)
                        }
                        .onEnded { _ in
                            scrollManager.updateZoomLevel(0.0)
                        }
                )
        }
        .allowsHitTesting(true)  // 允许手势穿透，不阻塞原生 ScrollView
    }
}
