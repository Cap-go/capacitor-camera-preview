import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func prepareFullSession() {
        // This function is now deprecated in favor of inline session creation in prepare()
        // Kept for backward compatibility
        guard self.captureSession == nil else { return }

        self.captureSession = AVCaptureSession()
    }
    func ensureCamerasDiscovered() {
        // Rediscover cameras if the array is empty OR if the camera pointers are nil
        guard allDiscoveredDevices.isEmpty || (rearCamera == nil && frontCamera == nil) else { return }
        discoverAndConfigureCameras()
    }
    func discoverAndConfigureCameras() {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera
        ]

        let session = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: .unspecified)
        let cameras = session.devices.compactMap { $0 }

        // Store all discovered devices for fast lookup later
        self.allDiscoveredDevices = cameras

        // Log all found devices for debugging

        for camera in cameras {
            _ = camera.isVirtualDevice ? camera.constituentDevices.count : 1

        }

        // Set front camera (usually just one option)
        self.frontCamera = cameras.first(where: { $0.position == .front })

        // Find rear camera - prefer tripleCamera for multi-lens support
        let rearCameras = cameras.filter { $0.position == .back }

        // First try to find built-in triple camera (provides access to all lenses)
        if let tripleCamera = rearCameras.first(where: {
            $0.deviceType == .builtInTripleCamera
        }) {
            self.rearCamera = tripleCamera
        } else if let dualWideCamera = rearCameras.first(where: {
            $0.deviceType == .builtInDualWideCamera
        }) {
            // Fallback to dual wide camera
            self.rearCamera = dualWideCamera
        } else if let dualCamera = rearCameras.first(where: {
            $0.deviceType == .builtInDualCamera
        }) {
            // Fallback to dual camera
            self.rearCamera = dualCamera
        } else if let wideAngleCamera = rearCameras.first(where: {
            $0.deviceType == .builtInWideAngleCamera
        }) {
            // Fallback to wide angle camera
            self.rearCamera = wideAngleCamera
        } else if let firstRearCamera = rearCameras.first {
            // Final fallback to any rear camera
            self.rearCamera = firstRearCamera
        }

        // Pre-configure focus modes
        configureCameraFocus(camera: self.rearCamera)
        configureCameraFocus(camera: self.frontCamera)
    }
    func configureCameraFocus(camera: AVCaptureDevice?) {
        guard let camera = camera else { return }

        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            camera.unlockForConfiguration()
        } catch {
            print("[CameraPreview] Could not configure focus for \(camera.localizedName): \(error)")
        }
    }

}
