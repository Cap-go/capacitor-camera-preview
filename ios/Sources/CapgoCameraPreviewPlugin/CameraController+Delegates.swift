import AVFoundation
import CoreGraphics
import Foundation
import UIKit

extension CameraController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            self.photoCaptureCompletionBlock?(nil, nil, nil, error)
            return
        }

        // Process photo in background to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Get the photo data using the modern API
            guard let imageData = photo.fileDataRepresentation() else {
                DispatchQueue.main.async {
                    self.photoCaptureCompletionBlock?(nil, nil, nil, CameraControllerError.unknown)
                }
                return
            }

            // Create image from data
            guard let image = UIImage(data: imageData) else {
                DispatchQueue.main.async {
                    self.photoCaptureCompletionBlock?(nil, nil, nil, CameraControllerError.unknown)
                }
                return
            }

            // Pass through original file data and metadata so callers can preserve EXIF
            // Don't call fixedOrientation() here - let the completion block handle it after cropping
            DispatchQueue.main.async {
                self.photoCaptureCompletionBlock?(image, imageData, photo.metadata, nil)
            }
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Check if we're waiting for the first frame
        if !hasReceivedFirstFrame, let firstFrameCallback = firstFrameReadyCallback {
            hasReceivedFirstFrame = true
            firstFrameCallback()
            firstFrameReadyCallback = nil
            // If no capture is in progress, we can return early
            if sampleBufferCaptureCompletionBlock == nil {
                return
            }
        }

        guard let completion = sampleBufferCaptureCompletionBlock else { return }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(nil, CameraControllerError.unknown)
            return
        }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue

        let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )

        guard let cgImage = context?.makeImage() else {
            completion(nil, CameraControllerError.unknown)
            return
        }

        let image = UIImage(cgImage: cgImage)
        completion(image.fixedOrientation(), nil)

        sampleBufferCaptureCompletionBlock = nil
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let callback = barcodeScannerCallback else { return }

        let now = Date().timeIntervalSince1970
        guard now - lastBarcodeDetectionAt >= barcodeDetectionInterval else { return }

        let barcodes: [[String: Any]] = metadataObjects.compactMap { object in
            guard let readableObject = object as? AVMetadataMachineReadableCodeObject,
                  let value = readableObject.stringValue,
                  !value.isEmpty else {
                return nil
            }

            return [
                "value": value,
                "format": barcodeFormat(from: readableObject.type)
            ]
        }

        guard !barcodes.isEmpty else { return }
        lastBarcodeDetectionAt = now

        DispatchQueue.main.async {
            callback(barcodes)
        }
    }
}

enum CameraControllerError: Swift.Error {
    case captureSessionAlreadyRunning
    case captureSessionIsMissing
    case inputsAreInvalid
    case invalidOperation
    case noCamerasAvailable
    case cannotFindDocumentsDirectory
    case fileVideoOutputNotFound
    case unknown
    case invalidZoomLevel(min: CGFloat, max: CGFloat, requested: CGFloat)
}

public enum CameraPosition {
    case front
    case rear
}

extension CameraControllerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .captureSessionAlreadyRunning:
            return NSLocalizedString("Capture Session is Already Running", comment: "Capture Session Already Running")
        case .captureSessionIsMissing:
            return NSLocalizedString("Capture Session is Missing", comment: "Capture Session Missing")
        case .inputsAreInvalid:
            return NSLocalizedString("Inputs Are Invalid", comment: "Inputs Are Invalid")
        case .invalidOperation:
            return NSLocalizedString("Invalid Operation", comment: "invalid Operation")
        case .noCamerasAvailable:
            return NSLocalizedString("Failed to access device camera(s)", comment: "No Cameras Available")
        case .unknown:
            return NSLocalizedString("Unknown", comment: "Unknown")
        case .cannotFindDocumentsDirectory:
            return NSLocalizedString("Cannot find documents directory", comment: "This should never happen")
        case .fileVideoOutputNotFound:
            return NSLocalizedString("Video recording is not available. Make sure the camera is properly initialized.", comment: "Video recording not available")
        case .invalidZoomLevel(let min, let max, let requested):
            return NSLocalizedString("Invalid zoom level. Must be between \(min) and \(max). Requested: \(requested)", comment: "Invalid Zoom Level")
        }
    }
}

extension UIImage {

    func fixedOrientation() -> UIImage? {

        guard imageOrientation != UIImage.Orientation.up else {
            // This is default orientation, don't need to do anything
            return self.copy() as? UIImage
        }

        guard let cgImage = self.cgImage else {
            // CGImage is not available
            return nil
        }

        guard let colorSpace = cgImage.colorSpace, let ctx = CGContext(data: nil,
                                                                       width: Int(size.width), height: Int(size.height),
                                                                       bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: 0,
                                                                       space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil // Not able to create CGContext
        }

        var transform: CGAffineTransform = CGAffineTransform.identity
        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: CGFloat.pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: CGFloat.pi / 2.0)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: CGFloat.pi / -2.0)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }

        // Flip image one more time if needed to, this is to prevent flipped image
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        @unknown default:
            break
        }

        ctx.concatenate(transform)

        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            if let cgImage = self.cgImage {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
            }
        default:
            if let cgImage = self.cgImage {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
        }
        guard let newCGImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: newCGImage, scale: 1, orientation: .up)
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let completion = self.videoRecordingCompletion
        self.videoRecordingCompletion = nil

        if let error = error {
            print("Error recording movie: \(error.localizedDescription)")
            completion?(nil, error)
        } else {
            print("Movie recorded successfully: \(outputFileURL)")
            completion?(outputFileURL, nil)
        }
    }
}
