// CameraControlHandler.swift
import SwiftUI

/// 管理 iPhone 16 相机控制（Camera Control）按钮的监听，
/// 将按钮的滑动映射为滚动偏移，传递给 CameraScrollManager。
/// 
/// ⚠️ 当前 SDK 不支持 Camera Control API（需要 iOS 17.2+ SDK / Xcode 15.3+），
/// 因此暂时以空实现占位，待升级 Xcode 后再恢复功能。
@MainActor
final class CameraControlHandler {

    static let shared = CameraControlHandler()

    private var isActive = false

    private init() {}

    // MARK: - 激活 / 停用

    func activateIfAvailable() {
        guard !isActive else { return }
        isActive = true
        print("Camera Control: not available (requires newer SDK)")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        print("Camera Control deactivated")
    }
}
