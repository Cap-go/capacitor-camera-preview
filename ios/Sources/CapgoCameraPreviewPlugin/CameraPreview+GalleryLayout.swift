import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    func saveImageDataToGallery(imageData: Data, completion: @escaping (Bool, Error?) -> Void) {
        // Check if NSPhotoLibraryUsageDescription is present in Info.plist
        guard Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") != nil else {
            let error = NSError(domain: "CameraPreview", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "NSPhotoLibraryUsageDescription key missing from Info.plist. Add this key with a description of how your app uses photo library access."
            ])
            completion(false, error)
            return
        }

        let status = PHPhotoLibrary.authorizationStatus()

        switch status {
        case .authorized:
            performSaveDataToGallery(imageData: imageData, completion: completion)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                if newStatus == .authorized {
                    self.performSaveDataToGallery(imageData: imageData, completion: completion)
                } else {
                    completion(false, NSError(domain: "CameraPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                }
            }
        case .denied, .restricted:
            completion(false, NSError(domain: "CameraPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
        case .limited:
            performSaveDataToGallery(imageData: imageData, completion: completion)
        @unknown default:
            completion(false, NSError(domain: "CameraPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown photo library authorization status"]))
        }
    }
    func performSaveDataToGallery(imageData: Data, completion: @escaping (Bool, Error?) -> Void) {
        // Create a temporary file to write the JPEG data with EXIF
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")

        do {
            try imageData.write(to: tempURL)

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
            }, completionHandler: { success, error in
                // Clean up temporary file
                try? FileManager.default.removeItem(at: tempURL)

                completion(success, error)
            })
        } catch {
            completion(false, error)
        }
    }
    func isPortrait() -> Bool {
        let interfaceOrientation: UIInterfaceOrientation? = {
            let lookup: () -> UIInterfaceOrientation? = {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                let activeScene = scenes.first { $0.activationState == .foregroundActive }
                return (activeScene ?? scenes.first)?.interfaceOrientation
            }
            if Thread.isMainThread {
                return lookup()
            } else {
                var value: UIInterfaceOrientation?
                DispatchQueue.main.sync {
                    value = lookup()
                }
                return value
            }
        }()
        return interfaceOrientation?.isPortrait ?? true
    }
    func calculateCameraFrame(xPosition: CGFloat? = nil, yPosition: CGFloat? = nil, width: CGFloat? = nil, height: CGFloat? = nil, aspectRatio: String? = nil) -> CGRect {
        // Use provided values or existing ones
        let currentWidth = width ?? self.width ?? UIScreen.main.bounds.size.width
        let currentHeight = height ?? self.height ?? UIScreen.main.bounds.size.height
        let currentX = xPosition ?? self.posX ?? -1
        let currentY = yPosition ?? self.posY ?? -1
        let currentAspectRatio = aspectRatio ?? self.aspectRatio

        let paddingBottom = self.paddingBottom ?? 0
        let adjustedHeight = currentHeight - CGFloat(paddingBottom)

        // Cache webView dimensions for performance
        let webViewWidth = self.webView?.frame.width ?? UIScreen.main.bounds.width
        let webViewHeight = self.webView?.frame.height ?? UIScreen.main.bounds.height

        let isPortrait = self.isPortrait()

        var finalX = currentX
        var finalY = currentY
        var finalWidth = currentWidth
        var finalHeight = adjustedHeight

        // Handle auto-centering when position is -1
        if currentX == -1 || currentY == -1 {
            // Only override dimensions if aspect ratio is provided and no explicit dimensions given
            if let ratio = currentAspectRatio,
               currentWidth == UIScreen.main.bounds.size.width &&
                currentHeight == UIScreen.main.bounds.size.height {
                finalWidth = webViewWidth

                // width: 428.0 height: 926.0 - portrait

                print("[CameraPreview] width: \(UIScreen.main.bounds.size.width) height: \(UIScreen.main.bounds.size.height)")

                // Calculate dimensions using centralized method
                let dimensions = calculateDimensionsForAspectRatio(ratio, availableWidth: finalWidth, availableHeight: webViewHeight - paddingBottom, isPortrait: isPortrait)
                if isPortrait {
                    finalHeight = dimensions.height
                    finalWidth = dimensions.width
                } else {
                    // In landscape, recalculate based on available space
                    let landscapeDimensions = calculateDimensionsForAspectRatio(ratio, availableWidth: webViewWidth, availableHeight: webViewHeight - paddingBottom, isPortrait: isPortrait)
                    finalWidth = landscapeDimensions.width
                    finalHeight = landscapeDimensions.height
                }
            }

            // Center horizontally if x is -1
            if currentX == -1 {
                finalX = (webViewWidth - finalWidth) / 2
            } else {
                finalX = currentX
            }

            // Position vertically if y is -1
            // TODO: fix top, bottom for landscape
            if currentY == -1 {
                // Use full screen height for positioning
                let screenHeight = UIScreen.main.bounds.size.height
                let screenWidth = UIScreen.main.bounds.size.width
                switch self.positioning {
                case "top":
                    finalY = 0
                    print("[CameraPreview] Positioning at top: finalY=0")
                case "bottom":
                    finalY = screenHeight - finalHeight
                    print("[CameraPreview] Positioning at bottom: screenHeight=\(screenHeight), finalHeight=\(finalHeight), finalY=\(finalY)")
                default: // "center"
                    if isPortrait {
                        finalY = (screenHeight - finalHeight) / 2
                        print("[CameraPreview] Centering vertically: screenHeight=\(screenHeight), finalHeight=\(finalHeight), finalY=\(finalY)")
                    } else {
                        // In landscape, center both horizontally and vertically
                        finalY = (screenHeight - finalHeight) / 2
                        finalX = (screenWidth - finalWidth) / 2
                    }
                }
            } else {
                finalY = currentY
            }
        }

        return CGRect(x: finalX, y: finalY, width: finalWidth, height: finalHeight)
    }
    func updateCameraFrame() {
        guard let posX = self.posX, let posY = self.posY else {
            return
        }

        // Ensure UI operations happen on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.updateCameraFrame()
            }
            return
        }

        // Calculate the base frame using the factorized method
        var frame = calculateCameraFrame()

        // Apply aspect ratio adjustments only if not auto-centering
        if posX != -1 && posY != -1, let aspectRatio = self.aspectRatio {
            let isPortrait = self.isPortrait()
            let ratio = parseAspectRatio(aspectRatio, isPortrait: isPortrait)
            let currentRatio = frame.width / frame.height

            if currentRatio > ratio {
                let newWidth = frame.height * ratio
                frame.origin.x += (frame.width - newWidth) / 2
                frame.size.width = newWidth
            } else {
                let newHeight = frame.width / ratio
                frame.origin.y += (frame.height - newHeight) / 2
                frame.size.height = newHeight
            }
        }

        // Disable ALL animations for frame updates - we want instant positioning
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Batch UI updates for better performance
        if self.previewView == nil {
            self.previewView = UIView(frame: frame)
            self.previewView.backgroundColor = UIColor.clear
        } else {
            self.previewView.frame = frame
        }

        // Update preview layer frame efficiently
        if let previewLayer = self.cameraController.previewLayer {
            previewLayer.frame = self.previewView.bounds
        }

        // Update grid overlay frame if it exists
        if let gridOverlay = self.cameraController.gridOverlayView {
            gridOverlay.frame = self.previewView.bounds
        }

        CATransaction.commit()
    }

    @objc func getPreviewSize(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("camera not started")
            return
        }

        DispatchQueue.main.async {
            var result = JSObject()
            result["x"] = Double(self.previewView.frame.origin.x)
            result["y"] = Double(self.previewView.frame.origin.y)
            result["width"] = Double(self.previewView.frame.width)
            result["height"] = Double(self.previewView.frame.height)
            call.resolve(result)
        }
    }

    @objc func setPreviewSize(_ call: CAPPluginCall) {
        guard self.isInitialized else {
            call.reject("camera not started")
            return
        }

        // Always set to -1 for auto-centering if not explicitly provided
        if let xValue = call.getInt("x") {
            self.posX = CGFloat(xValue)
        } else {
            self.posX = -1 // Auto-center if X not provided
        }

        if let yValue = call.getInt("y") {
            self.posY = CGFloat(yValue)
        } else {
            self.posY = -1 // Auto-center if Y not provided
        }

        if let width = call.getInt("width") { self.width = CGFloat(width) }
        if let height = call.getInt("height") { self.height = CGFloat(height) }

        DispatchQueue.main.async {
            // Direct update without animation for better performance
            self.updateCameraFrame()
            self.makeWebViewTransparent()

            // Return the actual preview bounds
            var result = JSObject()
            result["x"] = Double(self.previewView.frame.origin.x)
            result["y"] = Double(self.previewView.frame.origin.y)
            result["width"] = Double(self.previewView.frame.width)
            result["height"] = Double(self.previewView.frame.height)
            call.resolve(result)
        }
    }

    @objc func setFocus(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        guard let xCoord = call.getFloat("x"), let yCoord = call.getFloat("y") else {
            call.reject("x and y parameters are required")
            return
        }

        // Reject if values are outside 0-1 range
        if xCoord < 0 || xCoord > 1 || yCoord < 0 || yCoord > 1 {
            call.reject("Focus coordinates must be between 0 and 1")
            return
        }

        DispatchQueue.main.async {
            do {
                // Convert normalized coordinates to view coordinates
                let viewX = CGFloat(xCoord) * self.previewView.bounds.width
                let viewY = CGFloat(yCoord) * self.previewView.bounds.height
                let focusPoint = CGPoint(x: viewX, y: viewY)

                // Convert view coordinates to device coordinates
                guard let previewLayer = self.cameraController.previewLayer else {
                    call.reject("Preview layer not available")
                    return
                }
                let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: focusPoint)

                try self.cameraController.setFocus(at: devicePoint, showIndicator: !self.disableFocusIndicator, in: self.previewView)
                call.resolve()
            } catch {
                call.reject("Failed to set focus: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Exposure Bridge

}
