import Foundation
import AVFoundation
internal import Combine

/// 相机缩放控制器 - 管理相机会话和捏合缩放手势
/// 作用：通过隐藏的相机界面捕捉用户的捏合手势，将缩放结果转换为可共享的滚动值
/// 依赖：AVFoundation 框架
/// 输入：用户捏合手势
/// 输出：通过 @Published zoomLevel 发布 0.0-1.0 的缩放比例值
@MainActor
class CameraZoomController: ObservableObject {
    @Published var zoomLevel: CGFloat = 0.0  // 0.0 - 1.0 映射后的缩放值
    @Published var isCameraReady: Bool = false
    @Published var errorMessage: String?
    
    private var captureSession: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    var session: AVCaptureSession? { captureSession }
    private var currentZoomFactor: CGFloat = 1.0  // 实际相机缩放因子
    private let minZoomFactor: CGFloat = 1.0
    private let maxZoomFactor: CGFloat = 5.0  // 最大缩放倍数
    
    /// 设置并启动后置相机会话
    func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let session = captureSession else { return }
        
        // 获取后置相机
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            errorMessage = "后置相机不可用"
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            videoDeviceInput = input
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            isCameraReady = true
            
            // 在后台线程启动相机会话
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        } catch {
            errorMessage = "相机初始化失败: \(error.localizedDescription)"
            isCameraReady = false
        }
    }
    
    /// 处理捏合手势的缩放值
    /// 将手势的缩放因子限制在有效范围内，并映射为 0.0-1.0 的标准化值
    func handlePinchZoom(scale: CGFloat) {
        guard isCameraReady, let input = videoDeviceInput else { return }
        
        let device = input.device
        
        // 限制缩放范围
        let newZoomFactor = max(minZoomFactor, min(scale, maxZoomFactor))
        
        // 尝试应用平滑缩放
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = newZoomFactor
            device.unlockForConfiguration()
            currentZoomFactor = newZoomFactor
        } catch {
            // 如果锁定失败，仍然更新映射值
            currentZoomFactor = newZoomFactor
        }
        
        // 映射到 0.0-1.0 范围
        zoomLevel = (currentZoomFactor - minZoomFactor) / (maxZoomFactor - minZoomFactor)
    }
    
    /// 重置缩放到默认值
    func resetZoom() {
        guard isCameraReady, let input = videoDeviceInput else {
            zoomLevel = 0.0
            currentZoomFactor = 1.0
            return
        }
        
        let device = input.device
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = 1.0
            device.unlockForConfiguration()
            currentZoomFactor = 1.0
        } catch {}
        
        zoomLevel = 0.0
    }
    
    /// 停止相机会话
    func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
        videoDeviceInput = nil
        isCameraReady = false
        zoomLevel = 0.0
    }
    
    deinit {
        Task.detached { [captureSession] in
            await MainActor.run {
                captureSession?.stopRunning()
            }
        }
    }
}
