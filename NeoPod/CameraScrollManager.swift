import Foundation
internal import Combine
import SwiftUI

/// 相机滚动管理器 - 单例，用于在隐藏相机界面和滚动组件之间共享缩放/滚动状态
/// 作用：将相机缩放结果映射为全局滚动值，实现跨视图的滚动控制
/// 依赖：CameraZoomController
/// 输入：相机缩放值 (0.0-1.0)
/// 输出：通过 @Published scrollOffset 发布滚动偏移量，供 ScrollView 使用
@MainActor
class CameraScrollManager: ObservableObject {
    static let shared = CameraScrollManager()
    
    @Published var scrollOffset: CGFloat = 0.0  // 当前滚动偏移量
    @Published var isCameraControlActive: Bool = true  // 默认激活
    @Published var cameraZoomLevel: CGFloat = 0.0  // 当前相机缩放级别 (0.0-1.0)
    
    // 滚动灵敏度 - 值越大，缩放对滚动的影响越大
    private let scrollSensitivity: CGFloat = 500.0
    
    // 缩放死区 - 小于此值的缩放变化不会触发滚动
    private let zoomDeadzone: CGFloat = 0.02
    
    private var lastZoomLevel: CGFloat = 0.0
    
    private init() {}
    
    /// 停用相机控制 - 在屏幕任何点击时调用
    func deactivateCameraControl() {
        guard isCameraControlActive else { return }
        isCameraControlActive = false
        scrollOffset = 0.0
        cameraZoomLevel = 0.0
        lastZoomLevel = 0.0
    }
    
    /// 重新激活相机控制 - 页面出现时调用
    func activateCameraControl() {
        isCameraControlActive = true
        lastZoomLevel = 0.0
    }
    
    /// 更新相机缩放值并计算对应的滚动偏移
    func updateZoomLevel(_ newZoomLevel: CGFloat) {
        guard isCameraControlActive else { return }
        
        cameraZoomLevel = newZoomLevel
        
        // 计算缩放变化量，忽略死区内的小变化
        let zoomDelta = newZoomLevel - lastZoomLevel
        if abs(zoomDelta) < zoomDeadzone {
            return
        }
        
        // 将缩放变化映射为滚动偏移
        let scrollDelta = zoomDelta * scrollSensitivity
        scrollOffset += scrollDelta
        
        lastZoomLevel = newZoomLevel
    }
    
    /// 重置滚动偏移
    func resetScrollOffset() {
        scrollOffset = 0.0
        lastZoomLevel = 0.0
        cameraZoomLevel = 0.0
    }
}
