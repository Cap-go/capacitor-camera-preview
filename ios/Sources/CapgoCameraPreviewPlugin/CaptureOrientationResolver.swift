import AVFoundation
import Foundation

/// Selects whether still capture follows on-screen preview orientation or physical device tilt.
enum CaptureOrientationResolver {
    static let orientationPreview = "preview"
    static let orientationDevice = "device"

    static func usesDeviceOrientation(mode: String?) -> Bool {
        mode != orientationPreview
    }

    static func resolveOrientation(
        mode: String?,
        previewOrientation: AVCaptureVideoOrientation,
        deviceOrientation: AVCaptureVideoOrientation
    ) -> AVCaptureVideoOrientation {
        if mode == orientationPreview {
            return previewOrientation
        }
        return deviceOrientation
    }
}
