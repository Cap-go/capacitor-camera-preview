import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func getCurrentLensInfo() throws -> (focalLength: Float, deviceType: String, baseZoomRatio: Float) {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        var deviceType = "wideAngle"
        var baseZoomRatio: Float = 1.0

        switch device.deviceType {
        case .builtInWideAngleCamera:
            deviceType = "wideAngle"
            baseZoomRatio = 1.0
        case .builtInUltraWideCamera:
            deviceType = "ultraWide"
            baseZoomRatio = 0.5
        case .builtInTelephotoCamera:
            deviceType = "telephoto"
            baseZoomRatio = 2.0
        case .builtInDualCamera:
            deviceType = "dual"
            baseZoomRatio = 1.0
        case .builtInDualWideCamera:
            deviceType = "dualWide"
            baseZoomRatio = 1.0
        case .builtInTripleCamera:
            deviceType = "triple"
            baseZoomRatio = 1.0
        case .builtInTrueDepthCamera:
            deviceType = "trueDepth"
            baseZoomRatio = 1.0
        default:
            deviceType = "wideAngle"
            baseZoomRatio = 1.0
        }

        // Approximate focal length for mobile devices
        let focalLength: Float = 4.25

        return (focalLength: focalLength, deviceType: deviceType, baseZoomRatio: baseZoomRatio)
    }

    func swapToDevice(deviceId: String) throws {
        guard let captureSession = self.captureSession else {
            throw CameraControllerError.captureSessionIsMissing
        }

        // Find the device with the specified deviceId
        let allDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        ).devices

        guard let targetDevice = allDevices.first(where: { $0.uniqueID == deviceId }) else {
            throw CameraControllerError.noCamerasAvailable
        }

        // Store the current running state
        let wasRunning = captureSession.isRunning
        if wasRunning {
            captureSession.stopRunning()
        }

        // Begin configuration
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            // Restart the session if it was running before
            if wasRunning {
                captureSession.startRunning()
            }
        }

        // Store audio input if it exists
        let audioInput = captureSession.inputs.first { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) ?? false }

        // Remove only video inputs
        captureSession.inputs.forEach { input in
            if (input as? AVCaptureDeviceInput)?.device.hasMediaType(.video) ?? false {
                captureSession.removeInput(input)
            }
        }

        // Configure the new device
        let newInput = try AVCaptureDeviceInput(device: targetDevice)

        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)

            // Update camera references based on device position
            if targetDevice.position == .front {
                self.frontCameraInput = newInput
                self.frontCamera = targetDevice
                self.currentCameraPosition = .front
            } else {
                self.rearCameraInput = newInput
                self.rearCamera = targetDevice
                self.currentCameraPosition = .rear

                // Configure rear camera
                try targetDevice.lockForConfiguration()
                if targetDevice.isFocusModeSupported(.continuousAutoFocus) {
                    targetDevice.focusMode = .continuousAutoFocus
                }
                targetDevice.unlockForConfiguration()
            }
        } else {
            throw CameraControllerError.invalidOperation
        }

        // Re-add audio input if it existed
        if let audioInput = audioInput, captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Update video orientation
        self.updateVideoOrientation()
    }

    func cleanup() {
        stopBarcodeScanner()
        if let captureSession = self.captureSession {
            captureSession.stopRunning()
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            captureSession.outputs.forEach { captureSession.removeOutput($0) }
        }
        // Remove listener for subject area change
        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)

        self.motionManager.stopAccelerometerUpdates()
        self.previewLayer?.removeFromSuperlayer()
        self.previewLayer = nil

        self.focusIndicatorView?.removeFromSuperview()
        self.focusIndicatorView = nil

        self.frontCameraInput = nil
        self.rearCameraInput = nil
        self.audioInput = nil

        self.frontCamera = nil
        self.rearCamera = nil
        self.audioDevice = nil
        self.allDiscoveredDevices = []

        self.dataOutput = nil
        self.metadataOutput = nil
        self.photoOutput = nil
        self.fileVideoOutput = nil

        self.captureSession = nil
        self.currentCameraPosition = nil

        // Reset output preparation status
        self.outputsPrepared = false

        // Reset first frame detection
        self.hasReceivedFirstFrame = false
        self.firstFrameReadyCallback = nil
    }

    // MARK: - Exposure Controls

}
