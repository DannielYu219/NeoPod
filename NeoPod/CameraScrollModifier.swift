import SwiftUI

/// 相机控制滚动修饰器 - 扩展 ScrollView 以响应相机缩放输入
/// 作用：为 ScrollView 添加相机缩放驱动的滚动能力
/// 依赖：CameraScrollManager
/// 实现：监听 CameraScrollManager 的 scrollOffset 变化，通过 ScrollViewProxy 滚动到对应位置
struct CameraControlledScrollModifier: ViewModifier {
    @ObservedObject private var scrollManager = CameraScrollManager.shared
    
    // 用于累积滚动偏移
    @State private var accumulatedOffset: CGFloat = 0.0
    // 滚动节流 - 避免过于频繁的更新
    @State private var lastUpdateTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 0.016  // 约 60fps
    
    func body(content: Content) -> some View {
        content
            .overlay(
                // 当相机控制激活时，显示透明的相机叠层
                Group {
                    if scrollManager.isCameraControlActive {
                        Color.clear
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        // 使用垂直拖动作为相机缩放的替代输入
                                        let dragDelta = -value.translation.height
                                        let normalizedZoom = max(0.0, min(1.0, dragDelta / 300.0))
                                        scrollManager.updateZoomLevel(normalizedZoom)
                                    }
                                    .onEnded { _ in
                                        scrollManager.updateZoomLevel(0.0)
                                    }
                            )
                            .allowsHitTesting(scrollManager.isCameraControlActive)
                    }
                }
            )
    }
}

/// 可复用的相机滚动控制视图
/// 作用：将隐藏的相机叠层与内容视图结合
struct CameraScrollContainer<Content: View>: View {
    @ObservedObject private var scrollManager = CameraScrollManager.shared
    @State private var isCameraActive: Bool = false
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            content
            
            // 隐藏的相机叠层（默认隐藏，可通过设置激活）
            HiddenCameraOverlay(isActive: $isCameraActive)
                .allowsHitTesting(isCameraActive)
                .opacity(isCameraActive ? 1 : 0)
        }
    }
}
