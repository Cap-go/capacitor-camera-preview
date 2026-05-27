import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    @objc func flip(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        // Ensure UI operations happen on main thread
        DispatchQueue.main.async {
            // Disable user interaction during flip
            self.previewView.isUserInteractionEnabled = false

            do {
                try self.cameraController.switchCameras()

                // Update preview layer frame without animation
                CATransaction.begin()
                CATransaction.setDisableActions(true)

                // Preserve aspect ratio if it was set (unless cover mode is requested)
                if let previewLayer = self.cameraController.previewLayer {
                    if self.cameraController.requestedAspectMode == "cover" {
                        previewLayer.frame = self.previewView.bounds
                    } else if let aspectRatio = self.cameraController.requestedAspectRatio {
                        let frame = self.cameraController.calculateAspectRatioFrame(for: aspectRatio, in: self.previewView.bounds)
                        previewLayer.frame = frame
                    } else {
                        // No aspect ratio set, use full bounds
                        previewLayer.frame = self.previewView.bounds
                    }

                    // Set videoGravity based on aspectMode
                    previewLayer.videoGravity = self.cameraController.requestedAspectMode == "cover" ? .resizeAspectFill : .resizeAspect
                    // Keep grid overlay in sync with preview if it exists
                    if let gridOverlay = self.cameraController.gridOverlayView {
                        gridOverlay.frame = previewLayer.frame
                    }
                }

                CATransaction.commit()

                self.previewView.isUserInteractionEnabled = true

                // Ensure webview remains transparent after flip
                self.makeWebViewTransparent()

                call.resolve()
            } catch {
                self.previewView.isUserInteractionEnabled = true
                print("Failed to flip camera: \(error.localizedDescription)")
                call.reject("Failed to flip camera: \(error.localizedDescription)")
            }
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        let force = call.getBool("force") ?? false

        // If force is true, skip all checks and force stop
        if !force {
            if self.isInitializing {
                call.reject("cannot stop camera while initialization is in progress")
                return
            }
            if !self.isInitialized {
                call.reject("camera not initialized")
                return
            }
        }

        // UI operations must be on main thread
        DispatchQueue.main.async {
            // If a photo capture is in-flight, defer cleanup until it finishes,
            // but hide the preview immediately so UI can close.
            self.cameraController.removeGridOverlay()
            if let previewView = self.previewView {
                previewView.removeFromSuperview()
                self.previewView = nil
            }

            // Restore webView to opaque state with original background
            if let webView = self.webView {
                webView.isOpaque = true
                // Restore the original background colors that were saved
                self.restoreWebViewBackground(webView)
            }

            self.isInitialized = false
            self.isInitializing = false

            // Remove notification observers regardless
            NotificationCenter.default.removeObserver(self)
            if self.isGeneratingDeviceOrientationNotifications {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
                self.isGeneratingDeviceOrientationNotifications = false
            }

            if self.cameraController.isCapturingPhoto && !force {
                // Defer heavy cleanup until capture callback completes (only if not forcing)
                self.cameraController.stopRequestedAfterCapture = true
            } else {
                // Force stop or no capture pending; cleanup now
                if force {
                    self.cameraController.stopRequestedAfterCapture = false
                }
                self.cameraController.cleanup()
            }

            call.resolve()
        }
    }

    override public func checkPermissions(_ call: CAPPluginCall) {
        let disableAudio = call.getBool("disableAudio") ?? true
        let cameraStatus = self.mapAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .video))

        var result: [String: Any] = [
            "camera": cameraStatus
        ]

        if disableAudio == false {
            let audioPermission = AVAudioSession.sharedInstance().recordPermission
            result["microphone"] = self.mapAudioPermission(audioPermission)
        }

        call.resolve(result)
    }

    override public func requestPermissions(_ call: CAPPluginCall) {
        let disableAudio = call.getBool("disableAudio") ?? true
        self.disableAudio = disableAudio

        let title = call.getString("title") ?? "Camera Permission Needed"
        let message = call.getString("message") ?? "Enable camera access in Settings to use the preview."
        let openSettingsText = call.getString("openSettingsButtonTitle") ?? "Open Settings"
        let cancelText = call.getString("cancelButtonTitle") ?? "Cancel"
        let showSettingsAlert = call.getBool("showSettingsAlert") ?? false

        var currentCameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioSession = AVAudioSession.sharedInstance()
        var currentAudioStatus: AVAudioSession.RecordPermission? = disableAudio ? nil : audioSession.recordPermission

        let dispatchGroup = DispatchGroup()
        var pendingRequests = 0

        if currentCameraStatus == .notDetermined {
            pendingRequests += 1
            dispatchGroup.enter()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                currentCameraStatus = granted ? .authorized : .denied
                dispatchGroup.leave()
            }
        }

        if let audioStatus = currentAudioStatus,
           audioStatus == .undetermined {
            pendingRequests += 1
            dispatchGroup.enter()
            audioSession.requestRecordPermission { granted in
                currentAudioStatus = granted ? .granted : .denied
                dispatchGroup.leave()
            }
        }

        let finalizeResponse: () -> Void = { [weak self] in
            guard let self = self else { return }

            let cameraResult = self.mapAuthorizationStatus(currentCameraStatus)
            var result: [String: Any] = [
                "camera": cameraResult
            ]

            if let audioStatus = currentAudioStatus {
                result["microphone"] = self.mapAudioPermission(audioStatus)
            }

            let shouldShowAlert = showSettingsAlert &&
                (cameraResult == "denied" ||
                    ((result["microphone"] as? String) == "denied"))

            guard shouldShowAlert else {
                call.resolve(result)
                return
            }

            self.presentCameraPermissionAlert(title: title,
                                              message: message,
                                              openSettingsText: openSettingsText,
                                              cancelText: cancelText) {
                call.resolve(result)
            }
        }

        if pendingRequests == 0 {
            DispatchQueue.main.async(execute: finalizeResponse)
        } else {
            dispatchGroup.notify(queue: .main, execute: finalizeResponse)
        }
    }
    // Get user's cache directory path
}
