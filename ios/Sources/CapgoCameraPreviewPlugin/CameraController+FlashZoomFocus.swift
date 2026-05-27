import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func getSupportedFlashModes() throws -> [String] {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard
            let device = currentCamera
        else {
            throw CameraControllerError.noCamerasAvailable
        }

        var supportedFlashModesAsStrings: [String] = []
        if device.hasFlash {
            guard let supportedFlashModes: [AVCaptureDevice.FlashMode] = self.photoOutput?.supportedFlashModes else {
                throw CameraControllerError.noCamerasAvailable
            }

            for flashMode in supportedFlashModes {
                var flashModeValue: String?
                switch flashMode {
                case AVCaptureDevice.FlashMode.off:
                    flashModeValue = "off"
                case AVCaptureDevice.FlashMode.on:
                    flashModeValue = "on"
                case AVCaptureDevice.FlashMode.auto:
                    flashModeValue = "auto"
                default: break
                }
                if flashModeValue != nil {
                    supportedFlashModesAsStrings.append(flashModeValue!)
                }
            }
        }
        if device.hasTorch {
            supportedFlashModesAsStrings.append("torch")
        }
        return supportedFlashModesAsStrings

    }

    func getHorizontalFov() throws -> Float {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard
            let device = currentCamera
        else {
            throw CameraControllerError.noCamerasAvailable
        }

        // Get the active format and field of view
        let activeFormat = device.activeFormat
        let fov = activeFormat.videoFieldOfView

        // Adjust for current zoom level
        let zoomFactor = device.videoZoomFactor
        let adjustedFov = fov / Float(zoomFactor)

        return adjustedFov
    }

    func setFlashMode(flashMode: AVCaptureDevice.FlashMode) throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        guard let supportedFlashModes: [AVCaptureDevice.FlashMode] = self.photoOutput?.supportedFlashModes else {
            throw CameraControllerError.invalidOperation
        }
        if supportedFlashModes.contains(flashMode) {
            do {
                try device.lockForConfiguration()

                if device.hasTorch && device.isTorchAvailable && device.torchMode == AVCaptureDevice.TorchMode.on {
                    device.torchMode = AVCaptureDevice.TorchMode.off
                }
                self.flashMode = flashMode
                let photoSettings = AVCapturePhotoSettings()
                photoSettings.flashMode = flashMode
                self.photoOutput?.photoSettingsForSceneMonitoring = photoSettings

                device.unlockForConfiguration()
            } catch {
                throw CameraControllerError.invalidOperation
            }
        } else {
            throw CameraControllerError.invalidOperation
        }
    }

    func setTorchMode() throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard
            let device = currentCamera,
            device.hasTorch,
            device.isTorchAvailable
        else {
            throw CameraControllerError.invalidOperation
        }

        do {
            try device.lockForConfiguration()
            if device.isTorchModeSupported(AVCaptureDevice.TorchMode.on) {
                device.torchMode = AVCaptureDevice.TorchMode.on
            } else if device.isTorchModeSupported(AVCaptureDevice.TorchMode.auto) {
                device.torchMode = AVCaptureDevice.TorchMode.auto
            } else {
                device.torchMode = AVCaptureDevice.TorchMode.off
            }
            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }

    func getZoom() throws -> (min: Float, max: Float, current: Float) {
        var currentCamera: AVCaptureDevice?

        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        let effectiveMaxZoom = min(device.maxAvailableVideoZoomFactor, self.saneMaxZoomFactor)

        return (
            min: Float(device.minAvailableVideoZoomFactor),
            max: Float(effectiveMaxZoom),
            current: Float(device.videoZoomFactor)
        )
    }

    func setZoom(level: CGFloat, ramp: Bool, autoFocus: Bool = true) throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        let effectiveMaxZoom = min(device.maxAvailableVideoZoomFactor, self.saneMaxZoomFactor)
        let zoomLevel = max(device.minAvailableVideoZoomFactor, min(level, effectiveMaxZoom))

        do {
            try device.lockForConfiguration()

            if ramp {
                // Use a very fast ramp rate for immediate response
                device.ramp(toVideoZoomFactor: zoomLevel, withRate: 8.0)
            } else {
                device.videoZoomFactor = zoomLevel
            }

            device.unlockForConfiguration()

            // Update our internal zoom factor tracking
            self.zoomFactor = zoomLevel

            // Trigger autofocus after zoom if requested
            if autoFocus {
                self.triggerAutoFocus()
            }
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }
    func triggerAutoFocus() {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            return
        }

        // Focus on the center of the preview (0.5, 0.5)
        let centerPoint = CGPoint(x: 0.5, y: 0.5)

        do {
            try device.lockForConfiguration()

            // Set focus mode to auto if supported
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = centerPoint
                }
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = centerPoint
                }
            }

            if device.isExposurePointOfInterestSupported {
                let exposureMode = try getExposureMode()
                if exposureMode == "AUTO" || exposureMode == "CONTINUOUS" {
                    device.exposurePointOfInterest = centerPoint
                }
            }
            device.unlockForConfiguration()
        } catch {
            // Silently ignore errors during autofocus
        }
    }

    func setFocus(at point: CGPoint, showIndicator: Bool = false, in view: UIView? = nil) throws {
        // Validate that coordinates are within bounds (0-1 range for device coordinates)
        if point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1 {
            print("setFocus: Coordinates out of bounds - x: \(point.x), y: \(point.y)")
            throw CameraControllerError.invalidOperation
        }

        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        guard device.isFocusPointOfInterestSupported else {
            // Device doesn't support focus point of interest
            return
        }

        // Show focus indicator if enabled, requested and view is provided - only after validation
        if showIndicator, let view = view, let previewLayer = self.previewLayer {
            // Convert the device point to layer point for indicator display
            let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: point)
            showFocusIndicator(at: layerPoint, in: view)
        }

        do {
            try device.lockForConfiguration()

            // Set focus mode to auto if supported
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            // Set the focus point
            device.focusPointOfInterest = point

            // Skip exposure point if exposure locked
            if device.exposureMode != .locked {

                // Also set exposure point if supported
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                    device.setExposureTargetBias(0.0) { _ in }
                    device.exposurePointOfInterest = point
                }
            }

            // Turn on subject area monitor for switch to continuous focus if needed
            device.isSubjectAreaChangeMonitoringEnabled = true

            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.unknown
        }
    }

    func getFlashMode() throws -> String {
        switch self.flashMode {
        case .off:
            return "off"
        case .on:
            return "on"
        case .auto:
            return "auto"
        @unknown default:
            return "off"
        }
    }

    func getCurrentDeviceId() throws -> String {
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

        return device.uniqueID
    }

}
