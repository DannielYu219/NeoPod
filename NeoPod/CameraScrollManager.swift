import Foundation
internal import Combine
import SwiftUI

@MainActor
class CameraScrollManager: ObservableObject {
    static let shared = CameraScrollManager()

    @Published var scrollOffset: CGFloat = 0.0
    @Published var isCameraControlActive: Bool = true
    @Published var cameraZoomLevel: CGFloat = 0.0

    private let scrollSensitivity: CGFloat = 500.0
    private let zoomDeadzone: CGFloat = 0.02
    private var lastZoomLevel: CGFloat = 0.0

    private init() {}

    func deactivateCameraControl() {
        guard isCameraControlActive else { return }
        isCameraControlActive = false
        // 同时通知 CameraControlHandler 停止处理（可选）
        // 这里保持状态，CameraControlHandler 内部会检查 isCameraControlActive
    }

    func activateCameraControl() {
        isCameraControlActive = true
        lastZoomLevel = 0.0
    }

    // MARK: - 手势捏合使用

    func updateZoomLevel(_ newZoomLevel: CGFloat) {
        guard isCameraControlActive else { return }
        cameraZoomLevel = newZoomLevel
        let zoomDelta = newZoomLevel - lastZoomLevel
        if abs(zoomDelta) < zoomDeadzone { return }

        let scrollDelta = zoomDelta * scrollSensitivity
        scrollOffset += scrollDelta
        lastZoomLevel = newZoomLevel
    }

    // MARK: - Camera Control 专用（直接提供增量）

    func applyCameraControlScroll(delta: CGFloat) {
        guard isCameraControlActive else { return }
        scrollOffset += delta
    }

    func resetScrollOffset() {
        scrollOffset = 0.0
        lastZoomLevel = 0.0
        cameraZoomLevel = 0.0
    }
}
