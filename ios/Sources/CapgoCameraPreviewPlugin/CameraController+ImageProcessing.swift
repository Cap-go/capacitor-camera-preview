import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func addGPSMetadata(to image: UIImage, quality: CGFloat, location: CLLocation) -> Data? {
        guard let jpegData = image.jpegData(compressionQuality: quality),
              let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let uti = CGImageSourceGetType(source) else { return nil }

        var metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone(abbreviation: "UTC")

        let gpsDict: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSTimeStamp as String: formatter.string(from: location.timestamp),
            kCGImagePropertyGPSAltitude as String: location.altitude,
            kCGImagePropertyGPSAltitudeRef as String: location.altitude >= 0 ? 0 : 1
        ]

        metadata[kCGImagePropertyGPSDictionary as String] = gpsDict

        let destData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(destData, uti, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destData as Data
    }

    func resizeImage(image: UIImage, to size: CGSize) -> UIImage? {
        // Create a renderer with scale 1.0 to ensure we get exact pixel dimensions
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resizedImage = renderer.image { (_) in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resizedImage
    }

    func resizeImageToMaxDimensions(image: UIImage, maxWidth: Int?, maxHeight: Int?) -> UIImage? {
        let originalSize = image.size
        let originalAspectRatio = originalSize.width / originalSize.height

        var targetSize = originalSize

        if let maxWidth = maxWidth, let maxHeight = maxHeight {
            // Both dimensions specified - fit within both maximums
            let maxAspectRatio = CGFloat(maxWidth) / CGFloat(maxHeight)
            if originalAspectRatio > maxAspectRatio {
                // Original is wider - fit by width
                targetSize.width = CGFloat(maxWidth)
                targetSize.height = CGFloat(maxWidth) / originalAspectRatio
            } else {
                // Original is taller - fit by height
                targetSize.width = CGFloat(maxHeight) * originalAspectRatio
                targetSize.height = CGFloat(maxHeight)
            }
        } else if let maxWidth = maxWidth {
            // Only width specified - maintain aspect ratio
            targetSize.width = CGFloat(maxWidth)
            targetSize.height = CGFloat(maxWidth) / originalAspectRatio
        } else if let maxHeight = maxHeight {
            // Only height specified - maintain aspect ratio
            targetSize.width = CGFloat(maxHeight) * originalAspectRatio
            targetSize.height = CGFloat(maxHeight)
        }

        return resizeImage(image: image, to: targetSize)
    }

    func cropImageToAspectRatio(image: UIImage, aspectRatio: String) -> UIImage? {
        let components = aspectRatio.split(separator: ":").compactMap {Float(String($0))}
        guard components.count == 2 else {
            print("[CameraPreview] cropImageToAspectRatio - Failed to parse aspect ratio: \(aspectRatio)")
            return image
        }

        // Use physical orientation for capture works with portrait lock
        let orientation = self.lastCaptureOrientation ?? self.getPhysicalOrientation()
        let isPortrait = (orientation == .portrait || orientation == .portraitUpsideDown)

        let ratioWidth: CGFloat
        let ratioHeight: CGFloat
        if isPortrait {
            // For portrait 4:3 becomes 3:4, 16:9 becomes 9:16
            ratioWidth = CGFloat(components[1])
            ratioHeight = CGFloat(components[0])
        } else {
            // For landscape keep original
            ratioWidth = CGFloat(components[0])
            ratioHeight = CGFloat(components[1])
        }

        // Only normalize the image orientation if it's not already correct
        let normalizedImage: UIImage
        if image.imageOrientation == .up {
            normalizedImage = image
            print("[CameraPreview] cropImageToAspectRatio - Image already has correct orientation")
        } else {
            normalizedImage = image.fixedOrientation() ?? image
            print("[CameraPreview] cropImageToAspectRatio - Normalized image orientation from \(image.imageOrientation.rawValue) to .up")
        }

        let imageSize = normalizedImage.size
        let imageAspectRatio = imageSize.width / imageSize.height
        let targetAspectRatio = ratioWidth / ratioHeight

        print("[CameraPreview] cropImageToAspectRatio - Original image: \(imageSize.width)x\(imageSize.height) (ratio: \(imageAspectRatio))")
        print("[CameraPreview] cropImageToAspectRatio - Target ratio: \(ratioWidth):\(ratioHeight) (ratio: \(targetAspectRatio))")

        var cropRect: CGRect

        if imageAspectRatio > targetAspectRatio {
            // Image is wider than target - crop horizontally (center crop)
            let targetWidth = imageSize.height * targetAspectRatio
            let xOffset = (imageSize.width - targetWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: targetWidth, height: imageSize.height)
            print("[CameraPreview] cropImageToAspectRatio - Horizontal crop: \(cropRect)")
        } else {
            // Image is taller than target - crop vertically (center crop)
            let targetHeight = imageSize.width / targetAspectRatio
            let yOffset = (imageSize.height - targetHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: imageSize.width, height: targetHeight)
            print("[CameraPreview] cropImageToAspectRatio - Vertical crop: \(cropRect) - Target height: \(targetHeight)")
        }

        // Validate crop rect is within image bounds
        if cropRect.minX < 0 || cropRect.minY < 0 ||
            cropRect.maxX > imageSize.width || cropRect.maxY > imageSize.height {
            print("[CameraPreview] cropImageToAspectRatio - Warning: Crop rect \(cropRect) exceeds image bounds \(imageSize)")
            // Adjust crop rect to fit within image bounds
            cropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))
            print("[CameraPreview] cropImageToAspectRatio - Adjusted crop rect: \(cropRect)")
        }

        guard let cgImage = normalizedImage.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            print("[CameraPreview] cropImageToAspectRatio - Failed to crop image")
            return nil
        }

        let croppedImage = UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
        let finalAspectRatio = croppedImage.size.width / croppedImage.size.height
        print("[CameraPreview] cropImageToAspectRatio - Final cropped image: \(croppedImage.size.width)x\(croppedImage.size.height) (ratio: \(finalAspectRatio))")

        // Create the cropped image with normalized orientation
        return croppedImage
    }

    func cropImageToMatchPreview(image: UIImage, previewLayer: AVCaptureVideoPreviewLayer) -> UIImage? {
        // When using resizeAspectFill, the preview layer shows a cropped portion of the video
        // We need to calculate what portion of the captured image corresponds to what's visible

        let previewBounds = previewLayer.bounds
        let previewAspectRatio = previewBounds.width / previewBounds.height

        // Get the dimensions of the captured image
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height

        print("[CameraPreview] cropImageToMatchPreview - Preview bounds: \(previewBounds.width)x\(previewBounds.height) (ratio: \(previewAspectRatio))")
        print("[CameraPreview] cropImageToMatchPreview - Image size: \(imageSize.width)x\(imageSize.height) (ratio: \(imageAspectRatio))")

        // Since we're using resizeAspectFill, we need to calculate what portion of the image
        // is visible in the preview
        var cropRect: CGRect

        if imageAspectRatio > previewAspectRatio {
            // Image is wider than preview - crop horizontally
            let visibleWidth = imageSize.height * previewAspectRatio
            let xOffset = (imageSize.width - visibleWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: visibleWidth, height: imageSize.height)

        } else {
            // Image is taller than preview - crop vertically
            let visibleHeight = imageSize.width / previewAspectRatio
            let yOffset = (imageSize.height - visibleHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: imageSize.width, height: visibleHeight)

        }

        // Create the cropped image
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {

            return nil
        }

        let result = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

        return result
    }

    func captureSample(completion: @escaping (UIImage?, Error?) -> Void) {
        guard let captureSession = captureSession,
              captureSession.isRunning else {
            completion(nil, CameraControllerError.captureSessionIsMissing)
            return
        }

        self.sampleBufferCaptureCompletionBlock = completion
    }

}
