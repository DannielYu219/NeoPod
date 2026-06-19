// CameraControlHandler.swift
// NeoPod
//
// 管理 iPhone 16 Camera Control 按钮监听，将侧边按键滑动映射为歌曲列表滚动。
//
// 所有 AVCaptureSession 操作均在主线程执行（初始化很快），
// 彻底避免 Swift 6 并发隔离问题和 AVCaptureSession 多线程数据竞争。

import Foundation
internal import Combine
import AVFoundation
import AVKit

final class CameraControlHandler: NSObject {

    static let shared = CameraControlHandler()

    // MARK: - State (plain var, 非 @Published — 不需要 SwiftUI 观察)

    var isSessionRunning: Bool = false
    var isCameraControlSupported: Bool = false

    // MARK: - AVFoundation

    let captureSession = AVCaptureSession()
    private var deviceInput: AVCaptureDeviceInput?

    // MARK: - Private

    private var isConfigured = false
    private var lastProcessedPosition: CGFloat = 0.0
    private let scrollSensitivity: CGFloat = 60.0
    private let sessionQueue = DispatchQueue(label: "com.lyrastudio.NeoPod.cameraSession", qos: .userInitiated)
    private var currentItemCount: Int = 0

    // MARK: - Init

    private override init() {
        super.init()
        if #available(iOS 18.0, *) {
            isCameraControlSupported = captureSession.supportsControls
        }
    }

    // MARK: - 配置并启动 Session（主线程调用）

    func configureAndStartSession() {
        guard isCameraControlSupported else { return }
        guard !isSessionRunning else { return }

        // 配置 session（同步，主线程）
        if !isConfigured {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .low

            guard let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ) else {
                captureSession.commitConfiguration()
                print("[CameraControl] Back camera not available")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard captureSession.canAddInput(input) else {
                    captureSession.commitConfiguration()
                    print("[CameraControl] Cannot add camera input")
                    return
                }
                captureSession.addInput(input)
                deviceInput = input
            } catch {
                captureSession.commitConfiguration()
                print("[CameraControl] Failed to create input: \(error)")
                return
            }

            captureSession.commitConfiguration()

            // 在 configuration 块之外添加 Camera Control
            if #available(iOS 18.0, *) {
                configureSliderControl(itemCount: max(1, currentItemCount))
            }

            isConfigured = true
        }

        // 启动 session 必须在后台线程执行，避免阻塞主线程或触发系统线程检查崩溃
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
                self.lastProcessedPosition = 0.0
                CameraScrollManager.shared.activateCameraControl()
                print("[CameraControl] Session started")
            }
        }
    }

    // MARK: - Camera Control Slider (iOS 18+)

    @available(iOS 18.0, *)
    private func configureSliderControl(itemCount: Int) {
        guard captureSession.supportsControls else { return }

        // 清除已有控件
        for control in captureSession.controls {
            captureSession.removeControl(control)
        }

        currentItemCount = max(1, itemCount)
        // 使用 0...1 归一化范围，硬件步进 0.1 ≈ 列表 10%，实现快速滚动
        let scrollSlider = AVCaptureSlider(
            "Scroll",
            symbolName: "scroll",
            in: 0.0...1.0
        )

        // 使用主线程处理 slider 回调，避免并发问题
        scrollSlider.setActionQueue(.main) { [weak self] value in
            guard let self else { return }
            guard self.currentItemCount > 0 else { return }
            let targetIndex = max(0, min(self.currentItemCount - 1, Int(round(value * Float(self.currentItemCount - 1)))))
            print("[CameraControl] Slider value: \(value), targetIndex: \(targetIndex)")

            let manager = CameraScrollManager.shared
            print("[CameraControl] isCameraControlActive: \(manager.isCameraControlActive), isScreenTouched: \(manager.isScreenTouched)")
            if manager.isCameraControlActive {
                manager.cameraTargetIndex = targetIndex
                manager.registerCameraControlInput()
            }
        }

        if captureSession.canAddControl(scrollSlider) {
            captureSession.addControl(scrollSlider)
            print("[CameraControl] Scroll slider added with range 0...1, itemCount: \(currentItemCount)")
        }

        captureSession.setControlsDelegate(self, queue: .main)
    }

    /// 当列表数据变化时更新 slider 的刻度范围（0 到最后一首歌的序号）
    func updateSliderRange(itemCount: Int) {
        guard isCameraControlSupported else { return }
        guard #available(iOS 18.0, *) else { return }
        guard itemCount != currentItemCount else { return }

        // 如果 session 已经在运行，需要重新配置 slider
        if isSessionRunning {
            captureSession.beginConfiguration()
            configureSliderControl(itemCount: itemCount)
            captureSession.commitConfiguration()
        } else {
            configureSliderControl(itemCount: itemCount)
        }
    }

    // MARK: - 停止 Session（主线程调用）

    func stopSession() {
        guard isSessionRunning else { return }
        isSessionRunning = false
        CameraScrollManager.shared.deactivateCameraControl()

        // stopRunning 与 startRunning 一样，需要在后台线程执行
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                print("[CameraControl] Session stopped")
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        sessionQueue.sync { [captureSession] in
            captureSession.stopRunning()
        }
    }
}

// MARK: - AVCaptureSessionControlsDelegate (iOS 18+)

@available(iOS 18.0, *)
extension CameraControlHandler: AVCaptureSessionControlsDelegate {

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        CameraScrollManager.shared.activateCameraControl()
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        CameraScrollManager.shared.deactivateCameraControl()
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
}
