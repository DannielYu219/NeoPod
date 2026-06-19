// HiddenCameraOverlay.swift
// NeoPod
//
// 旧版捏合手势降级层：仅在 Camera Control 不可用时启用。

import SwiftUI

struct HiddenCameraOverlay: View {
    @ObservedObject private var scrollManager = CameraScrollManager.shared
    private let cameraHandler = CameraControlHandler.shared

    var body: some View {
        if !cameraHandler.isCameraControlSupported {
            GeometryReader { _ in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let normalizedZoom = max(0.0, min(1.0, (value - 1.0) / 4.0))
                                scrollManager.updateZoomLevel(normalizedZoom)
                            }
                            .onEnded { _ in
                                scrollManager.updateZoomLevel(0.0)
                            }
                    )
            }
            .allowsHitTesting(false)
        } else {
            Color.clear.allowsHitTesting(false).frame(width: 0, height: 0)
        }
    }
}
