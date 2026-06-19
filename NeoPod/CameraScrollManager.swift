// CameraScrollManager.swift
// NeoPod
//
// 集中管理 Camera Control 侧滑滚动状态。
// 优先级规则（华硕 Zentouch 风格）：
//   屏幕触摸中       → Camera Control 滚动立即禁用
//   屏幕触摸结束     → 等待 Camera Control 有滑动输入后自动重新激活
//   Camera Control 滑动中 + 用户触摸屏幕 → 立即禁用 Camera Control 滚动

import Foundation
internal import Combine
import SwiftUI

@MainActor
final class CameraScrollManager: ObservableObject {
    static let shared = CameraScrollManager()

    @Published var scrollOffset: CGFloat = 0.0
    @Published var isCameraControlActive: Bool = false
    @Published var isScreenTouched: Bool = false
    @Published var cameraZoomLevel: CGFloat = 0.0
    @Published var cameraTargetIndex: Int = 0

    private let scrollSensitivity: CGFloat = 500.0
    private let zoomDeadzone: CGFloat = 0.02
    private var lastZoomLevel: CGFloat = 0.0
    private var hasNewCameraControlInput: Bool = false

    private init() {}

    func activateCameraControl() {
        isCameraControlActive = true
        lastZoomLevel = 0.0
        hasNewCameraControlInput = false
    }

    func deactivateCameraControl() {
        isCameraControlActive = false
        hasNewCameraControlInput = false
    }

    func touchDeactivate() {
        guard !isScreenTouched else { return }
        isScreenTouched = true
        isCameraControlActive = false
        hasNewCameraControlInput = false
    }

    func tryReactivate() {
        isScreenTouched = false
    }

    func registerCameraControlInput() {
        guard !isScreenTouched else { return }
        if !isCameraControlActive {
            isCameraControlActive = true
            hasNewCameraControlInput = true
        }
    }

    func applyCameraControlScroll(delta: CGFloat) {
        guard isCameraControlActive, !isScreenTouched else { return }
        guard delta.isFinite else { return }
        scrollOffset += delta
    }

    func updateZoomLevel(_ newZoomLevel: CGFloat) {
        guard isCameraControlActive else { return }
        guard newZoomLevel.isFinite else { return }
        cameraZoomLevel = newZoomLevel
        let zoomDelta = newZoomLevel - lastZoomLevel
        if abs(zoomDelta) < zoomDeadzone { return }
        let scrollDelta = zoomDelta * scrollSensitivity
        scrollOffset += scrollDelta
        lastZoomLevel = newZoomLevel
    }

    func resetScrollOffset() {
        scrollOffset = 0.0
        lastZoomLevel = 0.0
        cameraZoomLevel = 0.0
    }
}
