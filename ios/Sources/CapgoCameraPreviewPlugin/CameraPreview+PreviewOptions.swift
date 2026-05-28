import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    @objc func setAspectRatio(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("camera not started")
            return
        }

        guard let newAspectRatio = call.getString("aspectRatio") else {
            call.reject("aspectRatio parameter is required")
            return
        }

        self.aspectRatio = newAspectRatio

        // Propagate to camera controller so capture output and preview align
        self.cameraController.updateAspectRatio(newAspectRatio)

        DispatchQueue.main.async {
            call.resolve(self.rawSetAspectRatio())
        }
    }

    func rawSetAspectRatio() -> JSObject {
        // When aspect ratio changes, always auto-center the view
        // This ensures consistent behavior where changing aspect ratio recenters the view
        self.posX = -1
        self.posY = -1

        // Calculate maximum size based on aspect ratio
        let webViewWidth = self.webView?.frame.width ?? UIScreen.main.bounds.width
        let webViewHeight = self.webView?.frame.height ?? UIScreen.main.bounds.height
        let paddingBottom = self.paddingBottom ?? 0
        let isPortrait = self.isPortrait()

        // Auto-centering mode - use full dimensions
        let availableWidth = webViewWidth
        let availableHeight = webViewHeight - paddingBottom

        // Parse aspect ratio - convert to portrait orientation for camera use
        // Use the centralized calculation method
        if let aspectRatio = self.aspectRatio {
            let dimensions = calculateDimensionsForAspectRatio(aspectRatio, availableWidth: availableWidth, availableHeight: availableHeight, isPortrait: isPortrait)
            self.width = dimensions.width
            self.height = dimensions.height
        }

        self.updateCameraFrame()

        // Return the actual preview bounds
        var result = JSObject()
        result["x"] = Double(self.previewView.frame.origin.x)
        result["y"] = Double(self.previewView.frame.origin.y)
        result["width"] = Double(self.previewView.frame.width)
        result["height"] = Double(self.previewView.frame.height)
        return result
    }

    @objc func getAspectRatio(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("camera not started")
            return
        }
        call.resolve(["aspectRatio": self.aspectRatio ?? "4:3"])
    }

    @objc func setGridMode(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("camera not started")
            return
        }

        guard let gridMode = call.getString("gridMode") else {
            call.reject("gridMode parameter is required")
            return
        }

        self.gridMode = gridMode

        // Update grid overlay
        DispatchQueue.main.async {
            if gridMode == "none" {
                self.cameraController.removeGridOverlay()
            } else {
                self.cameraController.addGridOverlay(to: self.previewView, gridMode: gridMode)
            }
        }

        call.resolve()
    }

    @objc func getGridMode(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("camera not started")
            return
        }
        call.resolve(["gridMode": self.gridMode])
    }

    @objc func appDidBecomeActive() {
        if self.isInitialized {
            DispatchQueue.main.async {
                self.makeWebViewTransparent()
            }
        }
    }

    @objc func appWillEnterForeground() {
        if self.isInitialized {
            DispatchQueue.main.async {
                self.makeWebViewTransparent()
            }
        }
    }

    struct CameraInfo {
        let deviceID: String
        let position: String
        let pictureSizes: [CGSize]
    }

    func getSupportedPictureSizes() -> [CameraInfo] {
        var cameraInfos = [CameraInfo]()

        // Discover all available cameras
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

        let devices = session.devices

        for device in devices {
            // Determine the position of the camera
            var position = "Unknown"
            switch device.position {
            case .front:
                position = "Front"
            case .back:
                position = "Back"
            case .unspecified:
                position = "Unspecified"
            @unknown default:
                position = "Unknown"
            }

            var pictureSizes = [CGSize]()

            // Get supported formats
            for format in device.formats {
                let description = format.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                let size = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
                if !pictureSizes.contains(size) {
                    pictureSizes.append(size)
                }
            }

            // Sort sizes in descending order (largest to smallest)
            pictureSizes.sort { $0.width * $0.height > $1.width * $1.height }

            let cameraInfo = CameraInfo(deviceID: device.uniqueID, position: position, pictureSizes: pictureSizes)
            cameraInfos.append(cameraInfo)
        }

        return cameraInfos
    }

    @objc func getSupportedPictureSizes(_ call: CAPPluginCall) {
        let cameraInfos = getSupportedPictureSizes()
        call.resolve([
            "supportedPictureSizes": cameraInfos.map {
                return [
                    "facing": $0.position,
                    "supportedPictureSizes": $0.pictureSizes.map { size in
                        return [
                            "width": String(describing: size.width),
                            "height": String(describing: size.height)
                        ]
                    }
                ]
            }
        ])
    }

}
