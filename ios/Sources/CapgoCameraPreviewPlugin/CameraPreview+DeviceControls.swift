import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    @objc func startBarcodeScanner(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("Camera is not running")
            return
        }

        let formats = call.getArray("formats") as? [String] ?? []
        let detectionInterval = call.getInt("detectionInterval") ?? 500

        do {
            try self.cameraController.startBarcodeScanner(formats: formats, detectionIntervalMs: detectionInterval) { [weak self] barcodes in
                self?.notifyListeners("barcodeScanned", data: ["barcodes": barcodes])
            }
            call.resolve()
        } catch {
            call.reject("Failed to start barcode scanner: \(error.localizedDescription)")
        }
    }

    @objc func stopBarcodeScanner(_ call: CAPPluginCall) {
        self.cameraController.stopBarcodeScanner()
        call.resolve()
    }

    @objc func getSupportedFlashModes(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            let supportedFlashModes = try self.cameraController.getSupportedFlashModes()
            call.resolve(["result": supportedFlashModes])
        } catch {
            call.reject("failed to get supported flash modes")
        }
    }

    @objc func getHorizontalFov(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            let horizontalFov = try self.cameraController.getHorizontalFov()
            call.resolve(["result": horizontalFov])
        } catch {
            call.reject("failed to get FOV")
        }
    }

    @objc func setFlashMode(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        guard let flashMode = call.getString("flashMode") else {
            call.reject("failed to set flash mode. required parameter flashMode is missing")
            return
        }
        do {
            var flashModeAsEnum: AVCaptureDevice.FlashMode?
            switch flashMode {
            case "off":
                flashModeAsEnum = AVCaptureDevice.FlashMode.off
            case "on":
                flashModeAsEnum = AVCaptureDevice.FlashMode.on
            case "auto":
                flashModeAsEnum = AVCaptureDevice.FlashMode.auto
            default: break
            }
            if let flashModeEnum = flashModeAsEnum {
                try self.cameraController.setFlashMode(flashMode: flashModeEnum)
            } else if flashMode == "torch" {
                try self.cameraController.setTorchMode()
            } else {
                call.reject("Flash Mode not supported")
                return
            }
            call.resolve()
        } catch {
            call.reject("failed to set flash mode")
        }
    }

    @objc func startRecordVideo(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            try self.cameraController.captureVideo()
            call.resolve()
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func stopRecordVideo(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        self.cameraController.stopRecording { (fileURL, error) in
            guard let fileURL = fileURL else {
                print(error ?? "Video capture error")
                guard let error = error else {
                    call.reject("Video capture error")
                    return
                }
                call.reject(error.localizedDescription)
                return
            }

            call.resolve(["videoFilePath": fileURL.absoluteString])
        }
    }

    @objc func isRunning(_ call: CAPPluginCall) {
        let isRunning = self.isInitialized && (self.cameraController.captureSession?.isRunning ?? false)
        call.resolve(["isRunning": isRunning])
    }

    @objc func getAvailableDevices(_ call: CAPPluginCall) {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera
        ]

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        var devices: [[String: Any]] = []

        // Collect all devices by position
        for device in session.devices {
            var lenses: [[String: Any]] = []

            let constituentDevices = device.isVirtualDevice ? device.constituentDevices : [device]

            for lensDevice in constituentDevices {
                var deviceType: String
                switch lensDevice.deviceType {
                case .builtInWideAngleCamera: deviceType = "wideAngle"
                case .builtInUltraWideCamera: deviceType = "ultraWide"
                case .builtInTelephotoCamera: deviceType = "telephoto"
                case .builtInDualCamera: deviceType = "dual"
                case .builtInDualWideCamera: deviceType = "dualWide"
                case .builtInTripleCamera: deviceType = "triple"
                case .builtInTrueDepthCamera: deviceType = "trueDepth"
                default: deviceType = "unknown"
                }

                var baseZoomRatio: Float = 1.0
                if lensDevice.deviceType == .builtInUltraWideCamera {
                    baseZoomRatio = 0.5
                } else if lensDevice.deviceType == .builtInTelephotoCamera {
                    baseZoomRatio = 2.0 // A common value for telephoto lenses
                }

                let lensInfo: [String: Any] = [
                    "label": lensDevice.localizedName,
                    "deviceType": deviceType,
                    "focalLength": 4.25, // Placeholder
                    "baseZoomRatio": baseZoomRatio,
                    "minZoom": Float(lensDevice.minAvailableVideoZoomFactor),
                    "maxZoom": Float(lensDevice.maxAvailableVideoZoomFactor)
                ]
                lenses.append(lensInfo)
            }

            let deviceData: [String: Any] = [
                "deviceId": device.uniqueID,
                "label": device.localizedName,
                "position": device.position == .front ? "front" : "rear",
                "lenses": lenses,
                "minZoom": Float(device.minAvailableVideoZoomFactor),
                "maxZoom": Float(device.maxAvailableVideoZoomFactor),
                "isLogical": device.isVirtualDevice
            ]

            devices.append(deviceData)
        }

        call.resolve(["devices": devices])
    }

    @objc func getZoom(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            let zoomInfo = try self.cameraController.getZoom()
            let lensInfo = try self.cameraController.getCurrentLensInfo()
            let displayMultiplier = self.cameraController.getDisplayZoomMultiplier()

            var minZoom = zoomInfo.min
            var maxZoom = zoomInfo.max
            var currentZoom = zoomInfo.current

            // Apply iOS 18+ display multiplier so UI sees the expected values
            if displayMultiplier != 1.0 {
                minZoom *= displayMultiplier
                maxZoom *= displayMultiplier
                currentZoom *= displayMultiplier
            }

            call.resolve([
                "min": minZoom,
                "max": maxZoom,
                "current": currentZoom,
                "lens": [
                    "focalLength": lensInfo.focalLength,
                    "deviceType": lensInfo.deviceType,
                    "baseZoomRatio": lensInfo.baseZoomRatio,
                    "digitalZoom": Float(currentZoom) / lensInfo.baseZoomRatio
                ]
            ])
        } catch {
            call.reject("Failed to get zoom: \(error.localizedDescription)")
        }
    }

    @objc func setZoom(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        guard var level = call.getFloat("level") else {
            call.reject("level parameter is required")
            return
        }

        // If using the multi-lens camera, translate the JS zoom value for the native layer
        // First, convert from UI/display zoom to native zoom using the iOS 18 multiplier
        let displayMultiplier = self.cameraController.getDisplayZoomMultiplier()
        if displayMultiplier != 1.0 {
            level /= displayMultiplier
        }

        let ramp = call.getBool("ramp") ?? true
        let autoFocus = call.getBool("autoFocus") ?? true

        do {
            try self.cameraController.setZoom(level: CGFloat(level), ramp: ramp, autoFocus: autoFocus)
            call.resolve()
        } catch {
            call.reject("Failed to set zoom: \(error.localizedDescription)")
        }
    }

    @objc func getFlashMode(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            let flashMode = try self.cameraController.getFlashMode()
            call.resolve(["flashMode": flashMode])
        } catch {
            call.reject("Failed to get flash mode: \(error.localizedDescription)")
        }
    }

    @objc func setDeviceId(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        guard let deviceId = call.getString("deviceId") else {
            call.reject("deviceId parameter is required")
            return
        }

        // Ensure UI operations happen on main thread
        DispatchQueue.main.async {
            // Disable user interaction during device swap
            self.previewView.isUserInteractionEnabled = false

            do {
                try self.cameraController.swapToDevice(deviceId: deviceId)

                // Update preview layer frame without animation
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.cameraController.previewLayer?.frame = self.previewView.bounds
                // Set videoGravity based on aspectMode
                self.cameraController.previewLayer?.videoGravity = self.cameraController.requestedAspectMode == "cover" ? .resizeAspectFill : .resizeAspect
                CATransaction.commit()

                self.previewView.isUserInteractionEnabled = true

                // Ensure webview remains transparent after device switch
                self.makeWebViewTransparent()

                call.resolve()
            } catch {
                self.previewView.isUserInteractionEnabled = true
                call.reject("Failed to swap to device \(deviceId): \(error.localizedDescription)")
            }
        }
    }

    @objc func getDeviceId(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            let deviceId = try self.cameraController.getCurrentDeviceId()
            call.resolve(["deviceId": deviceId])
        } catch {
            call.reject("Failed to get device ID: \(error.localizedDescription)")
        }
    }

    // MARK: - Capacitor Permissions

}
