import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    @objc func getTempFilePath() -> URL {
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let identifier = UUID()
        let randomIdentifier = identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let finalIdentifier = String(randomIdentifier.prefix(8))
        let fileName="cpcp_capture_"+finalIdentifier+".jpg"
        let fileUrl=path.appendingPathComponent(fileName)
        return fileUrl
    }

    @objc func capture(_ call: CAPPluginCall) {
        print("[CameraPreview] capture called with options: \(call.options ?? [:])")
        let withExifLocation = call.getBool("withExifLocation", false)
        print("[CameraPreview] capture called, withExifLocation: \(withExifLocation)")

        if withExifLocation {
            print("[CameraPreview] Location required for capture")

            // Check location services before main thread dispatch
            guard CLLocationManager.locationServicesEnabled() else {
                print("[CameraPreview] Location services are disabled")
                call.reject("Location services are disabled")
                return
            }

            // Check if Info.plist has the required key
            guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
                print("[CameraPreview] ERROR: NSLocationWhenInUseUsageDescription key missing from Info.plist")
                call.reject("NSLocationWhenInUseUsageDescription key missing from Info.plist. Add this key with a description of how your app uses location.")
                return
            }

            // Ensure location manager setup happens on main thread
            DispatchQueue.main.async {
                if self.locationManager == nil {
                    self.locationManager = CLLocationManager()
                    self.locationManager?.delegate = self
                    self.locationManager?.desiredAccuracy = kCLLocationAccuracyBest
                }

                // Check current authorization status
                let currentStatus = self.locationManager?.authorizationStatus ?? .notDetermined

                switch currentStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    // Already authorized, get location and capture
                    self.getCurrentLocation { _ in
                        self.performCapture(call: call)
                    }

                case .denied, .restricted:
                    // Permission denied
                    print("[CameraPreview] Location permission denied")
                    call.reject("Location permission denied")

                case .notDetermined:
                    // Need to request permission
                    print("[CameraPreview] Location permission not determined, requesting...")
                    // Save the call for the delegate callback
                    print("[CameraPreview] Saving call for location authorization flow")
                    self.bridge?.saveCall(call)
                    self.permissionCallID = call.callbackId
                    self.waitingForLocation = true

                    // Request authorization - this will trigger locationManagerDidChangeAuthorization
                    print("[CameraPreview] Requesting location authorization...")
                    self.locationManager?.requestWhenInUseAuthorization()
                // The delegate will handle the rest

                @unknown default:
                    print("[CameraPreview] Unknown authorization status")
                    call.reject("Unknown location permission status")
                }
            }
        } else {
            print("[CameraPreview] No location required, performing capture directly")
            self.performCapture(call: call)
        }
    }
    func performCapture(call: CAPPluginCall) {
        print("[CameraPreview] performCapture called")
        print("[CameraPreview] Call parameters: \(call.options ?? [:])")
        let quality = call.getFloat("quality", 85)
        let saveToGallery = call.getBool("saveToGallery", false)
        let withExifLocation = call.getBool("withExifLocation", false)
        let embedTimestamp = call.getBool("embedTimestamp", false) ?? false
        let embedLocationRequested = call.getBool("embedLocation", false) ?? false
        let effectiveEmbedLocation = (withExifLocation ?? false) && embedLocationRequested
        let width = call.getInt("width")
        let height = call.getInt("height")
        let photoQualityPrioritization = call.getString("photoQualityPrioritization", "speed")

        print("[CameraPreview] Raw parameter values - width: \(String(describing: width)), height: \(String(describing: height))")

        print("[CameraPreview] Capture params - quality: \(quality), saveToGallery: \(saveToGallery), withExifLocation: \(withExifLocation ?? false), embedTimestamp: \(embedTimestamp), embedLocation: \(effectiveEmbedLocation) (requested=\(embedLocationRequested)), width: \(width ?? -1), height: \(height ?? -1)")
        print("[CameraPreview] Current location: \(self.currentLocation?.description ?? "nil")")
        // Safely read frame from main thread for logging
        let (previewWidth, previewHeight): (CGFloat, CGFloat) = {
            if Thread.isMainThread {
                return (self.previewView.frame.width, self.previewView.frame.height)
            }
            var width: CGFloat = 0
            var height: CGFloat = 0
            DispatchQueue.main.sync {
                width = self.previewView.frame.width
                height = self.previewView.frame.height
            }
            return (width, height)
        }()
        print("[CameraPreview] Preview dimensions: \(previewWidth)x\(previewHeight)")

        let gpsForThisCapture = (withExifLocation ?? false) ? self.currentLocation : nil
        self.cameraController.captureImage(width: width, height: height, quality: quality, gpsLocation: gpsForThisCapture, embedTimestamp: embedTimestamp, embedLocation: effectiveEmbedLocation, photoQualityPrioritization: photoQualityPrioritization) { (image, originalPhotoData, _, error) in
            print("[CameraPreview] captureImage callback received")
            DispatchQueue.main.async {
                print("[CameraPreview] Processing capture on main thread")
                // Ensure heading updates are stopped on all exit paths (error, guard failure, or success)
                defer {
                    if withExifLocation ?? false {
                        self.locationManager?.stopUpdatingHeading()
                        self.currentHeading = nil
                    }
                }
                if let error = error {
                    print("[CameraPreview] Capture error: \(error.localizedDescription)")
                    call.reject(error.localizedDescription)
                    return
                }

                guard let image = image,
                      let imageDataWithExif = self.createImageDataWithExif(
                        from: image,
                        quality: Int(quality),
                        location: withExifLocation ? self.currentLocation : nil,
                        heading: withExifLocation ? self.currentHeading : nil,
                        originalPhotoData: originalPhotoData
                      )
                else {
                    print("[CameraPreview] Failed to create image data with EXIF")
                    call.reject("Failed to create image data with EXIF")
                    return
                }

                print("[CameraPreview] Image data created, size: \(imageDataWithExif.count) bytes")

                // Prepare the result first
                let exifData = self.getExifData(from: imageDataWithExif)

                var result = JSObject()
                result["exif"] = exifData

                if self.storeToFile == false {
                    let base64Image = imageDataWithExif.base64EncodedString()
                    result["value"] = base64Image
                } else {
                    do {
                        let fileUrl = self.getTempFilePath()
                        try imageDataWithExif.write(to: fileUrl)
                        result["value"] = fileUrl.absoluteString
                    } catch {
                        call.reject("Error writing image to file")
                        return
                    }
                }

                // Save to gallery asynchronously if requested
                if saveToGallery {
                    print("[CameraPreview] Saving to gallery asynchronously...")
                    DispatchQueue.global(qos: .utility).async {
                        self.saveImageDataToGallery(imageData: imageDataWithExif) { success, error in
                            print("[CameraPreview] Save to gallery completed, success: \(success), error: \(error?.localizedDescription ?? "none")")
                        }
                    }
                }

                print("[CameraPreview] Resolving capture call immediately")
                call.resolve(result)
            }
        }
    }
    func getExifData(from imageData: Data) -> JSObject {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let exifDict = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return [:]
        }

        var exifData = JSObject()
        for (key, value) in exifDict {
            // Convert value to JSValue-compatible type
            if let stringValue = value as? String {
                exifData[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                exifData[key] = numberValue
            } else if let boolValue = value as? Bool {
                exifData[key] = boolValue
            } else if let arrayValue = value as? [Any] {
                exifData[key] = arrayValue
            } else if let dictValue = value as? [String: Any] {
                exifData[key] = JSObject(_immutableCocoaDictionary: NSMutableDictionary(dictionary: dictValue))
            } else {
                // Convert other types to string as fallback
                exifData[key] = String(describing: value)
            }
        }

        return exifData
    }

    @objc func getSafeAreaInsets(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            var notchInset: CGFloat = 0
            var orientation: Int = 0

            // Get the current interface orientation
            let interfaceOrientation: UIInterfaceOrientation? = {
                return (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
            }()

            // Convert to orientation number (matching Android values for consistency)
            switch interfaceOrientation {
            case .portrait, .portraitUpsideDown:
                orientation = 1 // Portrait
            case .landscapeLeft, .landscapeRight:
                orientation = 2 // Landscape
            default:
                orientation = 0 // Unknown
            }

            // Get safe area insets
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                let safeAreaInsets = window.safeAreaInsets

                switch interfaceOrientation {
                case .portrait:
                    // Portrait: notch is at the top
                    notchInset = safeAreaInsets.top
                case .portraitUpsideDown:
                    // Portrait upside down: notch is at the bottom (but we still call it "top" for consistency)
                    notchInset = safeAreaInsets.bottom
                case .landscapeLeft:
                    // Landscape left: notch is typically on the left
                    notchInset = safeAreaInsets.left
                case .landscapeRight:
                    // Landscape right: notch is typically on the right (but we use left for consistency with Android)
                    notchInset = safeAreaInsets.right
                default:
                    // Unknown orientation, default to top
                    notchInset = safeAreaInsets.top
                }
            } else {
                // Fallback for iOS 14+: try to derive from any available window's safe area
                let anyWindow = UIApplication.shared
                    .connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first
                notchInset = anyWindow?.safeAreaInsets.top ?? 0
            }

            let result: [String: Any] = [
                "orientation": orientation,
                "top": Double(notchInset)
            ]

            call.resolve(result)
        }
    }
    func createImageDataWithExif(from image: UIImage, quality: Int, location: CLLocation?, heading: CLHeading?, originalPhotoData: Data?) -> Data? {
        guard let jpegDataAtQuality = image.jpegData(compressionQuality: CGFloat(Double(quality) / 100.0)) else {
            return nil
        }

        // Prefer metadata from the original AVCapturePhoto file data to preserve lens/EXIF
        let sourceDataForMetadata = (originalPhotoData ?? jpegDataAtQuality) as CFData
        guard let imageSource = CGImageSourceCreateWithData(sourceDataForMetadata, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let cgImage = image.cgImage else {
            return jpegDataAtQuality
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) else {
            return jpegDataAtQuality
        }

        var finalProperties = imageProperties

        // Ensure orientation reflects the pixel data (we pass an orientation-fixed UIImage)
        finalProperties[kCGImagePropertyOrientation as String] = 1

        // Add GPS location if available
        if let location = location {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            formatter.timeZone = TimeZone(abbreviation: "UTC")

            var gpsDict: [String: Any] = [
                kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSTimeStamp as String: formatter.string(from: location.timestamp),
                kCGImagePropertyGPSAltitude as String: location.altitude,
                kCGImagePropertyGPSAltitudeRef as String: location.altitude >= 0 ? 0 : 1
            ]

            // Add image direction (compass heading) when available
            if let heading = heading {
                let directionDegrees: Double
                let directionRef: String
                if heading.trueHeading >= 0 {
                    directionDegrees = heading.trueHeading
                    directionRef = "T"
                } else {
                    directionDegrees = heading.magneticHeading
                    directionRef = "M"
                }
                gpsDict[kCGImagePropertyGPSImgDirection as String] = directionDegrees
                gpsDict[kCGImagePropertyGPSImgDirectionRef as String] = directionRef
            }

            finalProperties[kCGImagePropertyGPSDictionary as String] = gpsDict
        }

        // Create or update TIFF dictionary for device info and set orientation to Up
        var tiffDict = finalProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiffDict[kCGImagePropertyTIFFMake as String] = "Apple"
        tiffDict[kCGImagePropertyTIFFModel as String] = UIDevice.current.model
        tiffDict[kCGImagePropertyTIFFOrientation as String] = 1
        finalProperties[kCGImagePropertyTIFFDictionary as String] = tiffDict

        CGImageDestinationAddImage(destination, cgImage, finalProperties as CFDictionary)

        if CGImageDestinationFinalize(destination) {
            return mutableData as Data
        }

        return jpegDataAtQuality
    }

    @objc func captureSample(_ call: CAPPluginCall) {
        let quality: Int = call.getInt("quality") ?? 85

        self.cameraController.captureSample { image, error in
            guard let image = image else {
                print("Image capture error: \(String(describing: error))")
                call.reject("Image capture error: \(String(describing: error))")
                return
            }

            let imageData: Data?
            if self.cameraPosition == "front" {
                let flippedImage = image.withHorizontallyFlippedOrientation()
                imageData = flippedImage.jpegData(compressionQuality: CGFloat(quality)/100)
            } else {
                imageData = image.jpegData(compressionQuality: CGFloat(quality)/100)
            }

            if self.storeToFile == false {
                guard let imageBase64 = imageData?.base64EncodedString() else {
                    call.reject("Failed to encode image to base64")
                    return
                }
                call.resolve(["value": imageBase64])
            } else {
                do {
                    let fileUrl = self.getTempFilePath()
                    try imageData?.write(to: fileUrl)
                    call.resolve(["value": fileUrl.absoluteString])
                } catch {
                    call.reject("Error writing image to file")
                }
            }
        }
    }

}
