import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func getExposureModes() throws -> [String] {
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

        var modes: [String] = []
        if device.isExposureModeSupported(.locked) { modes.append("LOCK") }
        if device.isExposureModeSupported(.autoExpose) { modes.append("AUTO") }
        if device.isExposureModeSupported(.continuousAutoExposure) { modes.append("CONTINUOUS") }
        if device.isExposureModeSupported(.custom) { modes.append("CUSTOM") }
        return modes
    }

    func getExposureMode() throws -> String {
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

        switch device.exposureMode {
        case .locked:
            return "LOCK"
        case .autoExpose:
            return "AUTO"
        case .continuousAutoExposure:
            return "CONTINUOUS"
        case .custom:
            return "CUSTOM"
        @unknown default:
            return "CONTINUOUS"
        }
    }

    func setExposureMode(mode: String) throws {
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

        let normalized = mode.uppercased()
        let desiredMode: AVCaptureDevice.ExposureMode?
        switch normalized {
        case "LOCK":
            desiredMode = .locked
        case "AUTO":
            desiredMode = .autoExpose
        case "CONTINUOUS":
            desiredMode = .continuousAutoExposure
        case "CUSTOM":
            desiredMode = .custom
        default:
            desiredMode = .continuousAutoExposure
        }

        guard let finalMode = desiredMode, device.isExposureModeSupported(finalMode) else {
            throw CameraControllerError.invalidOperation
        }

        do {
            try device.lockForConfiguration()
            device.exposureMode = finalMode
            // Reset EV to 0 when switching to AUTO or CONTINUOUS
            if finalMode == .autoExpose || finalMode == .continuousAutoExposure {
                device.setExposureTargetBias(0.0) { _ in }
            }
            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }

    func getExposureCompensationRange() throws -> (min: Float, max: Float, step: Float) {
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

        // iOS reports EV bias directly; typical step is 0.1 or 0.125 depending on device
        // There's no direct API for step; approximate as 0.1 for compatibility
        let step: Float = 0.1
        return (min: device.minExposureTargetBias, max: device.maxExposureTargetBias, step: step)
    }

    func getExposureCompensation() throws -> Float {
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

        return device.exposureTargetBias
    }

    func setExposureCompensation(_ value: Float) throws {
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

        let clamped = max(device.minExposureTargetBias, min(value, device.maxExposureTargetBias))

        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped) { _ in }
            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }

}
