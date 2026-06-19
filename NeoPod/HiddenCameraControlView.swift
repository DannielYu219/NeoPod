// HiddenCameraControlView.swift
// NeoPod
//
// 隐藏的 Camera Control 视图层。
// 嵌入极小的 AVCaptureVideoPreviewLayer 以满足系统对 Camera Control 的要求。

import SwiftUI
import AVFoundation
import AVKit

struct HiddenCameraControlView: View {
    // 不使用 @ObservedObject — handler 不再是 ObservableObject
    private let handler = CameraControlHandler.shared

    var body: some View {
        if handler.isCameraControlSupported {
            CameraPreviewRepresentable(session: handler.captureSession)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .onAppear {
                    print("[CameraControl] HiddenCameraControlView appeared, starting session")
                    handler.configureAndStartSession()
                }
                .onDisappear {
                    print("[CameraControl] HiddenCameraControlView disappeared, stopping session")
                    handler.stopSession()
                }
        } else {
            Color.clear
                .frame(width: 0, height: 0)
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Camera Control Interaction Host

/// 全屏透明宿主，负责把 Camera Control 按钮事件路由给当前 App。
/// 与 preview 分离，这样 preview 可以真正隐藏。
struct CameraControlInteractionView: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraControlInteractionUIView {
        CameraControlInteractionUIView()
    }

    func updateUIView(_ uiView: CameraControlInteractionUIView, context: Context) {}
}

final class CameraControlInteractionUIView: UIView {
    private var eventInteraction: AVCaptureEventInteraction?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard eventInteraction == nil else { return }
        let interaction = AVCaptureEventInteraction { event in
            print("[CameraControl] Event phase: \(event.phase.rawValue)")
            if event.phase == .began {
                CameraScrollManager.shared.activateCameraControl()
            }
        }
        addInteraction(interaction)
        eventInteraction = interaction
    }
}
