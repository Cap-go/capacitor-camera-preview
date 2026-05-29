import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func updateAspectRatio(_ aspectRatio: String?) {
        // Update internal state
        self.requestedAspectRatio = aspectRatio

        // Preserve current zoom level before session reconfiguration
        var currentZoom: CGFloat?
        if let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera {
            currentZoom = device.videoZoomFactor
        }

        // Reconfigure session preset to match the new ratio for optimal capture resolution
        if let captureSession = self.captureSession {
            captureSession.beginConfiguration()
            self.configureSessionPreset(for: aspectRatio)
            captureSession.commitConfiguration()
        }

        // Restore zoom level after session reconfiguration
        if let zoom = currentZoom, let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
                self.zoomFactor = zoom
                print("[CameraPreview] Preserved zoom level \(zoom) after aspect ratio change")
            } catch {
                print("[CameraPreview] Failed to restore zoom level after aspect ratio change: \(error)")
            }
        }

        // Update preview layer geometry on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let previewLayer = self.previewLayer else { return }
            if let superlayer = previewLayer.superlayer {
                let bounds = superlayer.bounds
                if self.requestedAspectMode == "cover" {
                    previewLayer.frame = bounds
                } else if let aspect = aspectRatio {
                    let frame = self.calculateAspectRatioFrame(for: aspect, in: bounds)
                    previewLayer.frame = frame
                } else {
                    previewLayer.frame = bounds
                }

                // Set videoGravity based on aspectMode
                previewLayer.videoGravity = self.requestedAspectMode == "cover" ? .resizeAspectFill : .resizeAspect

                // Keep grid overlay in sync with preview
                self.gridOverlayView?.frame = previewLayer.frame
            }
        }
    }
    func setInitialZoom(level: Float?) {
        let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera
        guard let device = device else {
            print("[CameraPreview] No device available for initial zoom")
            return
        }

        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, saneMaxZoomFactor)

        // Compute UI-level default (1×) when not provided
        let multiplier = self.getDisplayZoomMultiplier()
        // If level is nil, fall back to a UI zoom of 1.0×
        let uiLevel: Float = level ?? 1.0
        // Map UI/display zoom to native zoom using iOS 18+ multiplier
        let adjustedLevel = multiplier != 1.0 ? (uiLevel / multiplier) : uiLevel

        guard CGFloat(adjustedLevel) >= minZoom && CGFloat(adjustedLevel) <= maxZoom else {
            print("[CameraPreview] Initial zoom level \(adjustedLevel) out of range (\(minZoom)-\(maxZoom))")
            return
        }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(adjustedLevel)
            device.unlockForConfiguration()
            self.zoomFactor = CGFloat(adjustedLevel)
        } catch {
            print("[CameraPreview] Failed to set initial zoom: \(error)")
        }
    }
    func configureDeviceInputs(cameraPosition: String, deviceId: String?, disableAudio: Bool) throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

        // Ensure cameras are discovered before configuring inputs
        ensureCamerasDiscovered()

        var selectedDevice: AVCaptureDevice?

        // If deviceId is specified, find that specific device from discovered devices
        if let deviceId = deviceId {
            selectedDevice = self.allDiscoveredDevices.first(where: { $0.uniqueID == deviceId })
            guard selectedDevice != nil else {
                throw CameraControllerError.noCamerasAvailable
            }
        } else {
            // Use position-based selection from discovered cameras
            if cameraPosition == "rear" {
                selectedDevice = self.rearCamera
            } else if cameraPosition == "front" {
                selectedDevice = self.frontCamera
            }
        }

        guard let finalDevice = selectedDevice else {
            throw CameraControllerError.noCamerasAvailable
        }

        let deviceInput = try AVCaptureDeviceInput(device: finalDevice)

        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)

            if finalDevice.position == .front {
                self.frontCameraInput = deviceInput
                self.currentCameraPosition = .front
            } else {
                self.rearCameraInput = deviceInput
                self.currentCameraPosition = .rear
            }
        } else {
            throw CameraControllerError.inputsAreInvalid
        }

        // Add audio input if needed
        if !disableAudio {
            if self.audioDevice == nil {
                self.audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
            }
            if let audioDevice = self.audioDevice {
                self.audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(self.audioInput!) {
                    captureSession.addInput(self.audioInput!)
                } else {
                    throw CameraControllerError.inputsAreInvalid
                }
            }
        }

        // Set default exposure mode to CONTINUOUS when starting the camera
        do {
            try finalDevice.lockForConfiguration()
            if finalDevice.isExposureModeSupported(.continuousAutoExposure) {
                finalDevice.exposureMode = .continuousAutoExposure
                if finalDevice.isExposurePointOfInterestSupported {
                    finalDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            // Reset exposure compensation so sessions start neutral
            let minBias = finalDevice.minExposureTargetBias
            let maxBias = finalDevice.maxExposureTargetBias
            let neutralBias = max(minBias, min(0.0, maxBias))
            finalDevice.setExposureTargetBias(neutralBias) { _ in }
            finalDevice.unlockForConfiguration()
        } catch {
            // Non-fatal; continue without setting default exposure
        }
    }

    func displayPreview(on view: UIView) throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }

        print("[CameraPreview] ⏱ Guard check took \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
        let layerStartTime = CFAbsoluteTimeGetCurrent()

        // Get preview layer - should already be created in prepareOutputs
        guard let previewLayer = self.previewLayer else {
            throw CameraControllerError.captureSessionIsMissing
        }

        // Session should already be set during configuration

        print("[CameraPreview] ⏱ Layer session update took \(CFAbsoluteTimeGetCurrent() - layerStartTime) seconds")

        let configStartTime = CFAbsoluteTimeGetCurrent()
        // Optimize layer configuration with explicit transaction
        CATransaction.begin()
        CATransaction.setDisableActions(true) // Disable implicit animations for faster setup
        CATransaction.setAnimationDuration(0) // No animation duration

        // Start with zero alpha for smooth fade-in
        previewLayer.opacity = 0

        // Configure video gravity and frame based on aspect ratio and aspect mode
        if requestedAspectMode == "cover" {
            // Fill the entire view and let videoGravity crop as needed
            previewLayer.frame = view.bounds
        } else if let aspectRatio = requestedAspectRatio {
            // Calculate the frame based on requested aspect ratio for contain behavior
            let frame = calculateAspectRatioFrame(for: aspectRatio, in: view.bounds)
            previewLayer.frame = frame
        } else {
            // No specific aspect ratio requested - fill the entire view
            previewLayer.frame = view.bounds
        }
        // Set videoGravity based on aspectMode
        previewLayer.videoGravity = requestedAspectMode == "cover" ? .resizeAspectFill : .resizeAspect
        print("[CameraPreview] ⏱ Layer configuration took \(CFAbsoluteTimeGetCurrent() - configStartTime) seconds")

        let insertStartTime = CFAbsoluteTimeGetCurrent()
        // Set additional performance optimizations
        previewLayer.shouldRasterize = false // Avoid unnecessary rasterization
        previewLayer.drawsAsynchronously = true // Enable async rendering
        previewLayer.allowsGroupOpacity = true // Enable group opacity animations

        // Insert layer immediately (only if new)
        if previewLayer.superlayer != view.layer {
            view.layer.insertSublayer(previewLayer, at: 0)

            // Fade in the preview layer smoothly
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            previewLayer.opacity = 1.0
            CATransaction.commit()
        }

        CATransaction.commit()
        print("[CameraPreview] ⏱ Layer insertion took \(CFAbsoluteTimeGetCurrent() - insertStartTime) seconds")
        print("[CameraPreview] ⏱ Total display preview took \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
    }

    func addGridOverlay(to view: UIView, gridMode: String) {
        removeGridOverlay()

        // Disable animation for grid overlay creation and positioning
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Use preview layer frame if aspect ratio is specified, otherwise use full view bounds
        let gridFrame: CGRect
        if requestedAspectRatio != nil, let previewLayer = previewLayer {
            gridFrame = previewLayer.frame
        } else {
            gridFrame = view.bounds
        }

        gridOverlayView = GridOverlayView(frame: gridFrame)
        gridOverlayView?.gridMode = gridMode
        view.addSubview(gridOverlayView!)
        CATransaction.commit()
    }

    func removeGridOverlay() {
        gridOverlayView?.removeFromSuperview()
        gridOverlayView = nil
    }

    func updateVideoOrientation() {
        // Get orientation in a thread-safe way
        let videoOrientation = self.getVideoOrientation()

        // Apply orientation asynchronously on main thread
        let updateBlock = { [weak self] in
            guard let self = self else { return }
            self.previewLayer?.connection?.videoOrientation = videoOrientation
            self.dataOutput?.connections.forEach { $0.videoOrientation = videoOrientation }
            self.photoOutput?.connections.forEach { $0.videoOrientation = videoOrientation }
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }
    func setDefaultZoomAfterFlip() {
        let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera
        guard let device = device else {
            print("[CameraPreview] No device available for default zoom after flip")
            return
        }

        // Set zoom to 1.0x in UI terms, accounting for display multiplier
        let multiplier = self.getDisplayZoomMultiplier()
        let targetUIZoom: Float = 1.0  // We want 1.0x in the UI
        let nativeZoom = multiplier != 1.0 ? (targetUIZoom / multiplier) : targetUIZoom

        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, saneMaxZoomFactor)
        let clampedZoom = max(minZoom, min(CGFloat(nativeZoom), maxZoom))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            self.zoomFactor = clampedZoom
            print("[CameraPreview] Set default zoom after flip: UI=\(targetUIZoom)x, native=\(clampedZoom), multiplier=\(multiplier)")
        } catch {
            print("[CameraPreview] Failed to set default zoom after flip: \(error)")
        }
    }

    // Helper: pick the best preset the TARGET device supports for a given aspect ratio
}
