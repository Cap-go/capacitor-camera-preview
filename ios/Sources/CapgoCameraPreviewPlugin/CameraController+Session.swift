import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func prepareOutputs() {
        // Skip if already prepared
        guard !self.outputsPrepared else { return }

        // Create photo output
        self.photoOutput = AVCapturePhotoOutput()
        self.photoOutput?.isHighResolutionCaptureEnabled = true

        // Create video output
        self.fileVideoOutput = AVCaptureMovieFileOutput()

        // Create data output for preview
        self.dataOutput = AVCaptureVideoDataOutput()
        self.dataOutput?.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as String): NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)
        ]
        self.dataOutput?.alwaysDiscardsLateVideoFrames = true

        // Pre-create preview layer without session to avoid delay later
        if self.previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer()
            // Configure orientation immediately
            if let connection = layer.connection {
                // Ensure UI calls are made on the main thread
                if Thread.isMainThread {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        switch windowScene.interfaceOrientation {
                        case .portrait:
                            connection.videoOrientation = .portrait
                        case .landscapeLeft:
                            connection.videoOrientation = .landscapeLeft
                        case .landscapeRight:
                            connection.videoOrientation = .landscapeRight
                        case .portraitUpsideDown:
                            connection.videoOrientation = .portraitUpsideDown
                        case .unknown:
                            connection.videoOrientation = .portrait
                        @unknown default:
                            connection.videoOrientation = .portrait
                        }
                    }
                } else {
                    // If not on main thread, use a sync call to get the orientation
                    DispatchQueue.main.sync {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            switch windowScene.interfaceOrientation {
                            case .portrait:
                                connection.videoOrientation = .portrait
                            case .landscapeLeft:
                                connection.videoOrientation = .landscapeLeft
                            case .landscapeRight:
                                connection.videoOrientation = .landscapeRight
                            case .portraitUpsideDown:
                                connection.videoOrientation = .portraitUpsideDown
                            case .unknown:
                                connection.videoOrientation = .portrait
                            @unknown default:
                                connection.videoOrientation = .portrait
                            }
                        }
                    }
                }
            }
            // Don't set session here - we'll do it during configuration
            self.previewLayer = layer
        }

        // Mark as prepared
        self.outputsPrepared = true
    }

    func prepare(cameraPosition: String, deviceId: String? = nil, disableAudio: Bool, cameraMode: Bool, aspectRatio: String? = nil, aspectMode: String = "contain", initialZoomLevel: Float?, disableFocusIndicator: Bool = false, videoQuality: String = "high", completionHandler: @escaping (Error?) -> Void) {
        print("[CameraPreview] 🎬 Starting prepare - position: \(cameraPosition), deviceId: \(deviceId ?? "nil"), disableAudio: \(disableAudio), cameraMode: \(cameraMode), aspectRatio: \(aspectRatio ?? "nil"), aspectMode: \(aspectMode), zoom: \(initialZoomLevel ?? 1)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completionHandler(CameraControllerError.unknown)
                }
                return
            }

            // Start accelerometer
            var startedAccelerometer = false
            if self.motionManager.isAccelerometerAvailable {
                self.motionManager.accelerometerUpdateInterval = 1.0 / 60.0
                if !self.motionManager.isAccelerometerActive {
                    self.motionManager.startAccelerometerUpdates()
                    startedAccelerometer = true
                }
            }

            do {
                // Create session if needed
                if self.captureSession == nil {
                    self.captureSession = AVCaptureSession()
                }

                guard let captureSession = self.captureSession else {
                    throw CameraControllerError.captureSessionIsMissing
                }

                // Set quality of video
                self.videoQuality = videoQuality

                // Prepare outputs early
                self.prepareOutputs()

                // Single configuration block for all initial setup
                captureSession.beginConfiguration()

                // Set aspect ratio preset and remember requested ratio
                self.requestedAspectRatio = aspectRatio
                self.requestedAspectMode = aspectMode
                self.configureSessionPreset(for: aspectRatio)

                // Set disableFocusIndicator
                self.disableFocusIndicator = disableFocusIndicator

                // Configure device inputs
                try self.configureDeviceInputs(cameraPosition: cameraPosition, deviceId: deviceId, disableAudio: disableAudio)

                // Add ALL outputs BEFORE starting session to avoid flashes from reconfiguration

                // Get orientation in a thread-safe way
                let videoOrientation = self.getVideoOrientation()

                // Add data output for preview
                if let dataOutput = self.dataOutput, captureSession.canAddOutput(dataOutput) {
                    captureSession.addOutput(dataOutput)
                    // Use dedicated queue for better performance
                    let videoQueue = DispatchQueue(label: "com.camera.videoQueue", qos: .userInteractive)
                    dataOutput.setSampleBufferDelegate(self, queue: videoQueue)
                    // Set orientation immediately
                    dataOutput.connections.forEach { $0.videoOrientation = videoOrientation }
                }

                // Add photo output immediately to avoid later reconfiguration
                if let photoOutput = self.photoOutput, captureSession.canAddOutput(photoOutput) {
                    photoOutput.isHighResolutionCaptureEnabled = true
                    captureSession.addOutput(photoOutput)
                    // Set orientation immediately
                    photoOutput.connections.forEach { $0.videoOrientation = videoOrientation }
                }

                // Add video output if in camera mode
                if cameraMode, let fileVideoOutput = self.fileVideoOutput, captureSession.canAddOutput(fileVideoOutput) {
                    captureSession.addOutput(fileVideoOutput)
                    // Set orientation immediately
                    fileVideoOutput.connections.forEach { $0.videoOrientation = videoOrientation }
                }

                // Set up preview layer session in the same configuration block
                if let layer = self.previewLayer {
                    layer.session = captureSession
                    // Set orientation for preview layer
                    layer.connection?.videoOrientation = videoOrientation
                    // Start with a very subtle fade to smooth any remaining visual artifacts
                    layer.opacity = 0.95
                }

                captureSession.commitConfiguration()

                // Set initial zoom
                self.setInitialZoom(level: initialZoomLevel)

                // Set up listener for change in subject area of camera feed
                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
                NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)

                // Start the session - all outputs are already configured
                captureSession.startRunning()

                // Bring to full opacity after a tiny moment to smooth any visual artifacts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    if let layer = self?.previewLayer {
                        CATransaction.begin()
                        CATransaction.setAnimationDuration(0.1)
                        layer.opacity = 1.0
                        CATransaction.commit()
                    }
                }

                // Success callback
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
            } catch {
                if startedAccelerometer {
                    self.motionManager.stopAccelerometerUpdates()
                }
                DispatchQueue.main.async {
                    completionHandler(error)
                }
            }
        }
    }
    func configureSessionPreset(for aspectRatio: String?) {
        guard let captureSession = self.captureSession else { return }

        var targetPreset: AVCaptureSession.Preset = .photo

        // Prioritize video quality setting
        switch self.videoQuality.lowercased() {
        case "low":
            // Match Android "Low" (SD/480p)
            if captureSession.canSetSessionPreset(.vga640x480) {
                targetPreset = .vga640x480
            } else {
                targetPreset = .low
            }
        case "medium":
            // Match Android "Medium" (HD/720p)
            if captureSession.canSetSessionPreset(.hd1280x720) {
                targetPreset = .hd1280x720
            } else {
                targetPreset = .medium
            }
        case "high":
            // Exisiting logic for High Quality (4K/1080p based on Asepct Ratio)

            if let aspectRatio = aspectRatio {
                switch aspectRatio {
                case "16:9":
                    // Start with 1080p for faster initialization, 4K only when explicitly needed
                    // This maintains capture quality while optimizing preview performance
                    if captureSession.canSetSessionPreset(.hd1920x1080) {
                        targetPreset = .hd1920x1080
                    } else if captureSession.canSetSessionPreset(.hd4K3840x2160) {
                        targetPreset = .hd4K3840x2160
                    }
                case "4:3":
                    if captureSession.canSetSessionPreset(.photo) {
                        targetPreset = .photo
                    } else if captureSession.canSetSessionPreset(.high) {
                        targetPreset = .high
                    } else {
                        targetPreset = captureSession.sessionPreset
                    }
                default:
                    if captureSession.canSetSessionPreset(.photo) {
                        targetPreset = .photo
                    } else if captureSession.canSetSessionPreset(.high) {
                        targetPreset = .high
                    } else {
                        targetPreset = captureSession.sessionPreset
                    }
                }
            }
        // Handle unexpected values
        default:
            if captureSession.canSetSessionPreset(.photo) {
                targetPreset = .photo
            } else {
                targetPreset = .high
            }
        }
        if captureSession.canSetSessionPreset(targetPreset) {
            captureSession.sessionPreset = targetPreset
        }
    }

    /// Update the requested aspect ratio at runtime and reconfigure session/preview accordingly
}
