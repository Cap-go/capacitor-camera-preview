import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func bestPreset(for aspectRatio: String?, quality: String, on device: AVCaptureDevice) -> AVCaptureSession.Preset {

        // Handle specific quality overrides first
        switch quality.lowercased() {
        case "low":
            if device.supportsSessionPreset(.vga640x480) { return .vga640x480 }
            return .low
        case "medium":
            if device.supportsSessionPreset(.hd1280x720) { return .hd1280x720 }
            return .medium
        case "high":
            break // Exit and go off code below
        default:
            break // Exit and go off code below
        }
        // Preference order depends on aspect ratio
        if aspectRatio == "16:9" {
            // Prefer 4K → 1080p → 720p → high → photo → vga
            if device.supportsSessionPreset(.hd4K3840x2160) { return .hd4K3840x2160 }
            if device.supportsSessionPreset(.hd1920x1080) { return .hd1920x1080 }
            if device.supportsSessionPreset(.hd1280x720) { return .hd1280x720 }
            if device.supportsSessionPreset(.high) { return .high }
            if device.supportsSessionPreset(.photo) { return .photo } // safe, though 4:3
            return .vga640x480
        } else {
            // 4:3 or unknown: prefer photo → high → 1080p → 720p → vga
            if device.supportsSessionPreset(.photo) { return .photo }
            if device.supportsSessionPreset(.high) { return .high }
            if device.supportsSessionPreset(.hd1920x1080) { return .hd1920x1080 }
            if device.supportsSessionPreset(.hd1280x720) { return .hd1280x720 }
            return .vga640x480
        }
    }

    func switchCameras() throws {
        guard let currentCameraPosition = currentCameraPosition,
              let captureSession = self.captureSession else {
            throw CameraControllerError.captureSessionIsMissing
        }

        // Determine the device we’re switching TO
        let targetDevice: AVCaptureDevice
        switch currentCameraPosition {
        case .front:
            guard let rear = rearCamera else { throw CameraControllerError.invalidOperation }
            targetDevice = rear
        case .rear:
            guard let front = frontCamera else { throw CameraControllerError.invalidOperation }
            targetDevice = front
        }

        // Compute the desired preset for the TARGET device up front
        let desiredPreset = bestPreset(for: self.requestedAspectRatio, quality: self.videoQuality, on: targetDevice)

        // Keep the preview layer visually stable during the swap
        let savedPreviewFrame = self.previewLayer?.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.previewLayer?.connection?.isEnabled = false  // reduce visible glitching

        // No need to stopRunning; Apple recommends reconfiguring within begin/commit
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            self.previewLayer?.connection?.isEnabled = true
            // Restore frame (it shouldn't change, but this ensures zero animation)
            if let savedFrame = savedPreviewFrame { self.previewLayer?.frame = savedFrame }
            CATransaction.commit()
            DispatchQueue.main.async { [weak self] in
                self?.setDefaultZoomAfterFlip()   // normalize zoom (UI 1.0x)
            }
        }

        // Preserve audio input (if any)
        let existingAudioInput = captureSession.inputs.first {
            ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) ?? false
        }

        // Remove ONLY video inputs
        for input in captureSession.inputs {
            if (input as? AVCaptureDeviceInput)?.device.hasMediaType(.video) ?? false {
                captureSession.removeInput(input)
            }
        }

        // Only downgrade to a safe preset if the TARGET cannot support the CURRENT one
        let currentPreset = captureSession.sessionPreset
        let targetSupportsCurrent = targetDevice.supportsSessionPreset(currentPreset)
        if !targetSupportsCurrent {
            // Choose the first preset supported by BOTH the target device and the session
            let fallbacks: [AVCaptureSession.Preset] =
                (self.requestedAspectRatio == "16:9")
                ? [.hd4K3840x2160, .hd1920x1080, .hd1280x720, .high, .photo, .vga640x480]
                : [.photo, .high, .hd1920x1080, .hd1280x720, .vga640x480]
            for preset in fallbacks {
                if targetDevice.supportsSessionPreset(preset), captureSession.canSetSessionPreset(preset) {
                    captureSession.sessionPreset = preset
                    break
                }
            }
        }

        // Add the new video input
        let newInput = try AVCaptureDeviceInput(device: targetDevice)
        guard captureSession.canAddInput(newInput) else {
            throw CameraControllerError.invalidOperation
        }
        captureSession.addInput(newInput)

        // Update pointers / focus defaults
        if targetDevice.position == .front {
            self.frontCameraInput = newInput
            self.currentCameraPosition = .front
        } else {
            self.rearCameraInput = newInput
            self.currentCameraPosition = .rear
        }
        // (Lightweight focus config; non-fatal on failure)
        try? targetDevice.lockForConfiguration()
        if targetDevice.isFocusModeSupported(.continuousAutoFocus) {
            targetDevice.focusMode = .continuousAutoFocus
        }
        targetDevice.unlockForConfiguration()

        // Restore audio input if it existed
        if let audioInput = existingAudioInput, captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Now apply the BEST preset for the target device & requested AR
        if captureSession.sessionPreset != desiredPreset,
           targetDevice.supportsSessionPreset(desiredPreset),
           captureSession.canSetSessionPreset(desiredPreset) {
            captureSession.sessionPreset = desiredPreset
        }

        // Re-attach movie file output so its connection is bound to the new input.
        if let fileVideoOutput = self.fileVideoOutput,
           captureSession.outputs.contains(where: { $0 === fileVideoOutput }) {
            captureSession.removeOutput(fileVideoOutput)
            if captureSession.canAddOutput(fileVideoOutput) {
                captureSession.addOutput(fileVideoOutput)
            }
        }

        // Keep orientation correct
        self.updateVideoOrientation()
    }

}
