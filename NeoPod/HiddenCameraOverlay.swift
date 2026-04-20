import SwiftUI
import AVFoundation

/// 隐藏相机界面叠层 - 透明覆盖层，用于捕获捏合缩放手势
/// 作用：创建一个不可见的相机预览层，允许用户通过捏合手势控制缩放
/// 依赖：CameraZoomController, CameraScrollManager
/// 输入：用户捏合手势
/// 输出：通过 CameraScrollManager 发布滚动偏移量
struct HiddenCameraOverlay: View {
    @StateObject private var cameraController = CameraZoomController()
    @ObservedObject private var scrollManager = CameraScrollManager.shared
    
    @Binding var isActive: Bool
    var onZoomChange: ((CGFloat) -> Void)?  // 缩放变化回调
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 完全透明的背景
                Color.clear
                
                // 相机预览层（透明度极低，用户不可见）
                if cameraController.isCameraReady {
                    CameraPreviewView(session: cameraController.session)
                        .opacity(0.001)  // 几乎完全透明
                        .allowsHitTesting(false)
                }
                
                // 捏合手势识别区域
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            // 捏合手势识别
                            MagnificationGesture()
                                .onChanged { value in
                                    // 将捏合值转换为缩放级别
                                    let normalizedScale = (value - 1.0) / 4.0  // 映射到 0-1 范围
                                    let clampedScale = max(0.0, min(1.0, normalizedScale))
                                    
                                    cameraController.handlePinchZoom(scale: 1.0 + clampedScale * 4.0)
                                    
                                    // 更新滚动管理器
                                    scrollManager.updateZoomLevel(clampedScale)
                                    
                                    // 触发回调
                                    onZoomChange?(clampedScale)
                                }
                                .onEnded { _ in
                                    // 手势结束时重置
                                    cameraController.resetZoom()
                                },
                            
                            // 拖动手势作为备用方案
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // 垂直拖动也映射为缩放
                                    let translation = value.translation.height
                                    let normalizedZoom = max(0.0, min(1.0, -translation / 300.0))
                                    
                                    cameraController.handlePinchZoom(scale: 1.0 + normalizedZoom * 4.0)
                                    scrollManager.updateZoomLevel(normalizedZoom)
                                    onZoomChange?(normalizedZoom)
                                }
                                .onEnded { _ in
                                    cameraController.resetZoom()
                                }
                        )
                    )
            }
        }
        .onAppear {
            if isActive {
                cameraController.setupCamera()
                scrollManager.activateCameraControl()
            }
        }
        .onDisappear {
            scrollManager.deactivateCameraControl()
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                cameraController.setupCamera()
                scrollManager.activateCameraControl()
            } else {
                cameraController.stopCamera()
                scrollManager.deactivateCameraControl()
            }
        }
    }
}

/// 相机预览视图 - UIViewRepresentable 包装 AVCaptureSession 预览
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 添加相机预览层
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        if let session = session {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill
            uiView.layer.addSublayer(previewLayer)
        }
    }
}
