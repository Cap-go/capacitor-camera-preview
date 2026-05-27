import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func captureImage(width: Int?, height: Int?, quality: Float, gpsLocation: CLLocation?, embedTimestamp: Bool, embedLocation: Bool, photoQualityPrioritization: String, completion: @escaping (UIImage?, Data?, [AnyHashable: Any]?, Error?) -> Void) {
        guard let photoOutput = self.photoOutput else {
            completion(nil, nil, nil, NSError(domain: "Camera", code: 0, userInfo: [NSLocalizedDescriptionKey: "Photo output is not available"]))
            return
        }

        let captureContext = PhotoCaptureContext(
            width: width,
            height: height,
            quality: quality,
            gpsLocation: gpsLocation,
            embedTimestamp: embedTimestamp,
            embedLocation: embedLocation,
            completion: completion
        )

        configurePhotoOrientation(on: photoOutput)
        let settings = makePhotoSettings(
            width: width,
            height: height,
            photoQualityPrioritization: photoQualityPrioritization
        )
        applyFlashMode(to: settings, photoOutput: photoOutput)

        self.isCapturingPhoto = true

        self.photoCaptureCompletionBlock = { [weak self] (image, photoData, metadata, error) in
            guard let self = self else { return }
            self.handlePhotoCaptureResult(
                image: image,
                photoData: photoData,
                metadata: metadata,
                error: error,
                context: captureContext
            )
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    struct PhotoCaptureContext {
        let width: Int?
        let height: Int?
        let quality: Float
        let gpsLocation: CLLocation?
        let embedTimestamp: Bool
        let embedLocation: Bool
        let completion: (UIImage?, Data?, [AnyHashable: Any]?, Error?) -> Void
    }

    func configurePhotoOrientation(on photoOutput: AVCapturePhotoOutput) {
        guard let connection = photoOutput.connection(with: .video) else { return }

        let captureOrientation = self.getPhysicalOrientation()
        self.lastCaptureOrientation = captureOrientation
        connection.videoOrientation = captureOrientation
    }

    func makePhotoSettings(width: Int?, height: Int?, photoQualityPrioritization: String) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        let shouldUseHighRes = width.map { $0 > 1920 } ?? false || height.map { $0 > 1920 } ?? false
        settings.isHighResolutionPhotoEnabled = shouldUseHighRes

        if #available(iOS 15.0, *) {
            settings.photoQualityPrioritization = photoQualityPrioritizationMode(photoQualityPrioritization)
        }
        return settings
    }

    @available(iOS 15.0, *)
    func photoQualityPrioritizationMode(_ value: String) -> AVCapturePhotoOutput.QualityPrioritization {
        switch value {
        case "quality":
            return .quality
        case "balanced":
            return .balanced
        default:
            return .speed
        }
    }

    func applyFlashMode(to settings: AVCapturePhotoSettings, photoOutput: AVCapturePhotoOutput) {
        guard let device = currentCaptureDevice(),
              device.hasFlash,
              photoOutput.supportedFlashModes.contains(self.flashMode) else {
            return
        }
        settings.flashMode = self.flashMode
    }

    func currentCaptureDevice() -> AVCaptureDevice? {
        switch currentCameraPosition {
        case .front:
            return self.frontCamera
        case .rear:
            return self.rearCamera
        default:
            return nil
        }
    }

    func handlePhotoCaptureResult(image: UIImage?,
                                  photoData: Data?,
                                  metadata: [AnyHashable: Any]?,
                                  error: Error?,
                                  context: PhotoCaptureContext) {
        defer { finishPhotoCaptureIfNeeded() }

        if let error = error {
            context.completion(nil, nil, nil, error)
            return
        }

        guard let image = image else {
            context.completion(nil, nil, nil, NSError(domain: "Camera", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to capture image"]))
            return
        }

        var finalImage = imageForRequestedSize(image: image, width: context.width, height: context.height)
        finalImage = imageWithRequestedOverlays(
            image: finalImage,
            photoData: photoData,
            metadata: metadata,
            context: context
        )
        let finalPhotoData = imageDataForCaptureResult(image: finalImage, fallbackData: photoData, context: context)

        context.completion(finalImage, finalPhotoData, metadata, nil)
    }

    func imageDataForCaptureResult(image: UIImage, fallbackData: Data?, context: PhotoCaptureContext) -> Data? {
        let compressionQuality = normalizedCompressionQuality(context.quality)
        if let location = context.gpsLocation,
           let dataWithLocation = addGPSMetadata(to: image, quality: compressionQuality, location: location) {
            return dataWithLocation
        }
        return image.jpegData(compressionQuality: compressionQuality) ?? fallbackData
    }

    func normalizedCompressionQuality(_ quality: Float) -> CGFloat {
        if quality > 1 {
            return CGFloat(max(0, min(quality, 100)) / 100)
        }
        return CGFloat(max(0, min(quality, 1)))
    }

    func finishPhotoCaptureIfNeeded() {
        self.isCapturingPhoto = false
        guard self.stopRequestedAfterCapture else { return }

        DispatchQueue.main.async {
            self.cleanup()
            self.stopRequestedAfterCapture = false
        }
    }

    func imageForRequestedSize(image: UIImage, width: Int?, height: Int?) -> UIImage {
        var finalImage = image

        if let aspectRatio = self.requestedAspectRatio {
            finalImage = self.cropImageToAspectRatio(image: image, aspectRatio: aspectRatio) ?? image
            print("[CameraPreview] Applied aspect ratio cropping for \(aspectRatio): \(finalImage.size.width)x\(finalImage.size.height)")
        }

        guard width != nil || height != nil else {
            return finalImage
        }

        guard let resizedImage = self.resizeImageToMaxDimensions(image: finalImage, maxWidth: width, maxHeight: height) else {
            return finalImage
        }
        print("[CameraPreview] Resized to max dimensions: \(resizedImage.size.width)x\(resizedImage.size.height)")
        return resizedImage
    }

    func imageWithRequestedOverlays(image: UIImage,
                                    photoData: Data?,
                                    metadata: [AnyHashable: Any]?,
                                    context: PhotoCaptureContext) -> UIImage {
        guard context.embedTimestamp || context.embedLocation else { return image }

        let timestampText = context.embedTimestamp
            ? self.makeTimestampString(from: photoData, metadata: metadata)
            : nil
        let locationText = context.embedLocation
            ? self.makeLocationString(from: context.gpsLocation, photoData: photoData, metadata: metadata)
            : nil

        guard !(timestampText?.isEmpty ?? true) || !(locationText?.isEmpty ?? true) else {
            return image
        }
        return self.drawTimestampAndLocation(on: image, when: timestampText, where: locationText)
    }
}
