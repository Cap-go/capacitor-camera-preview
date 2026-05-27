import AVFoundation
import UIKit
import CoreLocation
import UniformTypeIdentifiers
import CoreMotion

class CameraController: NSObject {
    func getVideoOrientation() -> AVCaptureVideoOrientation {
        var orientation: AVCaptureVideoOrientation = .portrait
        if Thread.isMainThread {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch windowScene.interfaceOrientation {
                case .portrait: orientation = .portrait
                case .landscapeLeft: orientation = .landscapeLeft
                case .landscapeRight: orientation = .landscapeRight
                case .portraitUpsideDown: orientation = .portraitUpsideDown
                case .unknown: fallthrough
                @unknown default: orientation = .portrait
                }
            }
        } else {
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    switch windowScene.interfaceOrientation {
                    case .portrait: orientation = .portrait
                    case .landscapeLeft: orientation = .landscapeLeft
                    case .landscapeRight: orientation = .landscapeRight
                    case .portraitUpsideDown: orientation = .portraitUpsideDown
                    case .unknown: fallthrough
                    @unknown default: orientation = .portrait
                    }
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 0.1) // Timeout after 100ms to prevent deadlocks
        }
        return orientation
    }

    // For capture only - uses accelerometer to detect physical orientation to properly position videos/images
    func getPhysicalOrientation() -> AVCaptureVideoOrientation {
        guard let accelerometerData = motionManager.accelerometerData else {
            return lastCaptureOrientation ?? getVideoOrientation() // Fallback to interface in case of accelerometer fail
        }

        let axisX = accelerometerData.acceleration.x
        let axisY = accelerometerData.acceleration.y

        if abs(axisX) > abs(axisY) {
            // Landscape
            return axisX > 0 ? .landscapeLeft : .landscapeRight
        } else {
            // Portrait
            return axisY > 0 ? .portraitUpsideDown : .portrait
        }
    }

    // Continuous focus with significant movement if focus was locked from setFocus earlier
    @objc func subjectAreaDidChange(notification: NSNotification) {
        guard let device = self.currentCameraPosition == .rear ? rearCamera : frontCamera else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // Reset Focus to the center and make it continuous
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }

            // 2. Reset Exposure to the center ONLY if it is not explicitly locked
            if device.exposureMode != .locked {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    }
                    device.setExposureTargetBias(0.0) { _ in }
                }
            }

            // 3. Turn off monitoring until the user taps to focus again
            device.isSubjectAreaChangeMonitoringEnabled = false

            print("[CameraPreview] Phone moved: Reset focus. Exposure reset skipped if locked.")

        } catch {
            print("[CameraPreview] Failed to reset focus after subject area change: \(error)")
        }
    }

    var captureSession: AVCaptureSession?
    var disableFocusIndicator: Bool = false

    var currentCameraPosition: CameraPosition?

    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?

    var dataOutput: AVCaptureVideoDataOutput?
    var metadataOutput: AVCaptureMetadataOutput?
    var photoOutput: AVCapturePhotoOutput?

    var rearCamera: AVCaptureDevice?
    var rearCameraInput: AVCaptureDeviceInput?

    var allDiscoveredDevices: [AVCaptureDevice] = []

    var fileVideoOutput: AVCaptureMovieFileOutput?

    var previewLayer: AVCaptureVideoPreviewLayer?
    var gridOverlayView: GridOverlayView?
    var focusIndicatorView: UIView?

    var flashMode = AVCaptureDevice.FlashMode.off
    var photoCaptureCompletionBlock: ((UIImage?, Data?, [AnyHashable: Any]?, Error?) -> Void)?

    var sampleBufferCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    var barcodeScannerCallback: (([[String: Any]]) -> Void)?
    let barcodeMetadataQueue = DispatchQueue(label: "com.camera.barcodeMetadataQueue", qos: .userInitiated)
    var barcodeDetectionInterval: TimeInterval = 0.5
    var lastBarcodeDetectionAt: TimeInterval = 0

    // Add callback for detecting when first frame is ready
    var firstFrameReadyCallback: (() -> Void)?
    var hasReceivedFirstFrame = false

    var audioDevice: AVCaptureDevice?
    var audioInput: AVCaptureDeviceInput?

    var zoomFactor: CGFloat = 1.0
    var lastZoomUpdateTime: TimeInterval = 0
    let zoomUpdateThrottle: TimeInterval = 1.0 / 60.0 // 60 FPS max
    let motionManager = CMMotionManager()
    var lastCaptureOrientation: AVCaptureVideoOrientation?

    var videoFileURL: URL?
    let saneMaxZoomFactor: CGFloat = 25.5

    var videoQuality: String = "high"

    // Track output preparation status
    var outputsPrepared: Bool = false

    // Capture/stop coordination
    var isCapturingPhoto: Bool = false
    var stopRequestedAfterCapture: Bool = false

    var isUsingMultiLensVirtualCamera: Bool {
        guard let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera else { return false }
        // A rear multi-lens virtual camera will have a min zoom of 1.0 but support wider angles
        return device.position == .back && device.isVirtualDevice && device.constituentDevices.count > 1
    }

    // Returns the display zoom multiplier introduced in iOS 18 to map between
    // native zoom factor and the UI-displayed zoom factor. Falls back to 1.0 on
    // older systems or if the property is unavailable.
    func getDisplayZoomMultiplier() -> Float {
        var multiplier: Float = 1.0
        // Use KVC to avoid compile-time dependency on the iOS 18 SDK symbol
        let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera
        if #available(iOS 18.0, *), let device = device {
            if let value = device.value(forKey: "displayVideoZoomFactorMultiplier") as? NSNumber {
                let multiplierValue = value.floatValue
                if multiplierValue > 0 { multiplier = multiplierValue }
            }
        }
        return multiplier
    }

    // Track whether an aspect ratio was explicitly requested
    var requestedAspectRatio: String?
    var requestedAspectMode: String = "contain"

    func calculateAspectRatioFrame(for aspectRatio: String, in bounds: CGRect) -> CGRect {
        guard let ratio = parseAspectRatio(aspectRatio) else {
            return bounds
        }

        let targetAspectRatio = ratio.width / ratio.height
        let viewAspectRatio = bounds.width / bounds.height

        var frame: CGRect

        if viewAspectRatio > targetAspectRatio {
            // View is wider than target - fit by height
            let targetWidth = bounds.height * targetAspectRatio
            let xOffset = (bounds.width - targetWidth) / 2
            frame = CGRect(x: xOffset, y: 0, width: targetWidth, height: bounds.height)
        } else {
            // View is taller than target - fit by width
            let targetHeight = bounds.width / targetAspectRatio
            let yOffset = (bounds.height - targetHeight) / 2
            frame = CGRect(x: 0, y: yOffset, width: bounds.width, height: targetHeight)
        }

        return frame
    }
    func parseAspectRatio(_ aspectRatio: String) -> (width: CGFloat, height: CGFloat)? {
        let components = aspectRatio.split(separator: ":").compactMap { Float(String($0)) }
        guard components.count == 2 else { return nil }

        // Get orientation in a thread-safe way
        let orientation = self.getVideoOrientation()
        let isPortrait = (orientation == .portrait || orientation == .portraitUpsideDown)

        let originalWidth = CGFloat(components[0])
        let originalHeight = CGFloat(components[1])
        print("[CameraPreview] parseAspectRatio - isPortrait: \(isPortrait) originalWidth: \(originalWidth) originalHeight: \(originalHeight)")

        let finalWidth: CGFloat
        let finalHeight: CGFloat

        if isPortrait {
            // For portrait mode, swap width and height to maintain portrait orientation
            // 4:3 becomes 3:4, 16:9 becomes 9:16
            finalWidth = originalHeight
            finalHeight = originalWidth
            print("[CameraPreview] parseAspectRatio - Portrait mode: \(aspectRatio) -> \(finalWidth):\(finalHeight) (ratio: \(finalWidth/finalHeight))")
        } else {
            // For landscape mode, keep original orientation
            finalWidth = originalWidth
            finalHeight = originalHeight
            print("[CameraPreview] parseAspectRatio - Landscape mode: \(aspectRatio) -> \(finalWidth):\(finalHeight) (ratio: \(finalWidth/finalHeight))")
        }

        return (width: finalWidth, height: finalHeight)
    }
}
