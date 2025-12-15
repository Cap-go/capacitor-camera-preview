import AVFoundation
import UIKit
import CoreLocation
import UniformTypeIdentifiers

class CameraController: NSObject {
    private func getVideoOrientation() -> AVCaptureVideoOrientation {
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

    var captureSession: AVCaptureSession?
    var disableFocusIndicator: Bool = false

    var currentCameraPosition: CameraPosition?

    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?

    var dataOutput: AVCaptureVideoDataOutput?
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

    // Add callback for detecting when first frame is ready
    var firstFrameReadyCallback: (() -> Void)?
    var hasReceivedFirstFrame = false

    var audioDevice: AVCaptureDevice?
    var audioInput: AVCaptureDeviceInput?

    var zoomFactor: CGFloat = 1.0
    private var lastZoomUpdateTime: TimeInterval = 0
    private let zoomUpdateThrottle: TimeInterval = 1.0 / 60.0 // 60 FPS max

    var videoFileURL: URL?
    private let saneMaxZoomFactor: CGFloat = 25.5

    // Track output preparation status
    private var outputsPrepared: Bool = false

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
                let m = value.floatValue
                if m > 0 { multiplier = m }
            }
        }
        return multiplier
    }

    // Track whether an aspect ratio was explicitly requested
    var requestedAspectRatio: String?

    // Face Detection
    var faceDetectionManager: FaceDetectionManager?

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

    private func parseAspectRatio(_ aspectRatio: String) -> (width: CGFloat, height: CGFloat)? {
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

extension CameraController {
    func prepareFullSession() {
        // This function is now deprecated in favor of inline session creation in prepare()
        // Kept for backward compatibility
        guard self.captureSession == nil else { return }

        self.captureSession = AVCaptureSession()
    }

    private func ensureCamerasDiscovered() {
        // Rediscover cameras if the array is empty OR if the camera pointers are nil
        guard allDiscoveredDevices.isEmpty || (rearCamera == nil && frontCamera == nil) else { return }
        discoverAndConfigureCameras()
    }

    private func discoverAndConfigureCameras() {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera
        ]

        let session = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: .unspecified)
        let cameras = session.devices.compactMap { $0 }

        // Store all discovered devices for fast lookup later
        self.allDiscoveredDevices = cameras

        // Log all found devices for debugging

        for camera in cameras {
            _ = camera.isVirtualDevice ? camera.constituentDevices.count : 1

        }

        // Set front camera (usually just one option)
        self.frontCamera = cameras.first(where: { $0.position == .front })

        // Find rear camera - prefer tripleCamera for multi-lens support
        let rearCameras = cameras.filter { $0.position == .back }

        // First try to find built-in triple camera (provides access to all lenses)
        if let tripleCamera = rearCameras.first(where: {
            $0.deviceType == .builtInTripleCamera
        }) {
            self.rearCamera = tripleCamera
        } else if let dualWideCamera = rearCameras.first(where: {
            $0.deviceType == .builtInDualWideCamera
        }) {
            // Fallback to dual wide camera
            self.rearCamera = dualWideCamera
        } else if let dualCamera = rearCameras.first(where: {
            $0.deviceType == .builtInDualCamera
        }) {
            // Fallback to dual camera
            self.rearCamera = dualCamera
        } else if let wideAngleCamera = rearCameras.first(where: {
            $0.deviceType == .builtInWideAngleCamera
        }) {
            // Fallback to wide angle camera
            self.rearCamera = wideAngleCamera
        } else if let firstRearCamera = rearCameras.first {
            // Final fallback to any rear camera
            self.rearCamera = firstRearCamera
        }

        // Pre-configure focus modes
        configureCameraFocus(camera: self.rearCamera)
        configureCameraFocus(camera: self.frontCamera)
    }

    private func configureCameraFocus(camera: AVCaptureDevice?) {
        guard let camera = camera else { return }

        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            camera.unlockForConfiguration()
        } catch {
            print("[CameraPreview] Could not configure focus for \(camera.localizedName): \(error)")
        }
    }

    private func prepareOutputs() {
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
                            fallthrough
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
                                fallthrough
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

    func prepare(cameraPosition: String, deviceId: String? = nil, disableAudio: Bool, cameraMode: Bool, aspectRatio: String? = nil, initialZoomLevel: Float?, disableFocusIndicator: Bool = false, completionHandler: @escaping (Error?) -> Void) {
        print("[CameraPreview] 🎬 Starting prepare - position: \(cameraPosition), deviceId: \(deviceId ?? "nil"), disableAudio: \(disableAudio), cameraMode: \(cameraMode), aspectRatio: \(aspectRatio ?? "nil"), zoom: \(initialZoomLevel ?? 1)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completionHandler(CameraControllerError.unknown)
                }
                return
            }

            do {
                // Create session if needed
                if self.captureSession == nil {
                    self.captureSession = AVCaptureSession()
                }

                guard let captureSession = self.captureSession else {
                    throw CameraControllerError.captureSessionIsMissing
                }

                // Prepare outputs early
                self.prepareOutputs()

                // Single configuration block for all initial setup
                captureSession.beginConfiguration()

                // Set aspect ratio preset and remember requested ratio
                self.requestedAspectRatio = aspectRatio
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
                DispatchQueue.main.async {
                    completionHandler(error)
                }
            }
        }
    }

    private func configureSessionPreset(for aspectRatio: String?) {
        guard let captureSession = self.captureSession else { return }

        // For face detection, prioritize 720p for optimal performance
        // Higher resolutions (1080p, 4K) slow down Vision framework without improving accuracy
        var targetPreset: AVCaptureSession.Preset = .hd1280x720
        
        if let aspectRatio = aspectRatio {
            switch aspectRatio {
            case "16:9":
                // Use 720p for face detection - best balance of quality and performance
                if captureSession.canSetSessionPreset(.hd1280x720) {
                    targetPreset = .hd1280x720
                } else if captureSession.canSetSessionPreset(.hd1920x1080) {
                    targetPreset = .hd1920x1080
                } else if captureSession.canSetSessionPreset(.high) {
                    targetPreset = .high
                }
            case "4:3":
                // For 4:3, use medium preset which is typically 480p-720p range
                if captureSession.canSetSessionPreset(.medium) {
                    targetPreset = .medium
                } else if captureSession.canSetSessionPreset(.photo) {
                    targetPreset = .photo
                } else if captureSession.canSetSessionPreset(.high) {
                    targetPreset = .high
                } else {
                    targetPreset = captureSession.sessionPreset
                }
            default:
                if captureSession.canSetSessionPreset(.hd1280x720) {
                    targetPreset = .hd1280x720
                } else if captureSession.canSetSessionPreset(.high) {
                    targetPreset = .high
                } else {
                    targetPreset = captureSession.sessionPreset
                }
            }
        }

        if captureSession.canSetSessionPreset(targetPreset) {
            captureSession.sessionPreset = targetPreset
        }
        
        // Configure frame rate for face detection (20-25 FPS)
        configureFrameRateForFaceDetection()
    }

    /// Update the requested aspect ratio at runtime and reconfigure session/preview accordingly
    func updateAspectRatio(_ aspectRatio: String?) {
        // Update internal state
        self.requestedAspectRatio = aspectRatio

        // Preserve current zoom level before session reconfiguration
        var currentZoom: CGFloat?
        if let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera {
            currentZoom = device.videoZoomFactor
        }

        // Reconfigure session preset to match the new ratio for optimal capture resolution
        if let captureSession = self.captureSession {
            captureSession.beginConfiguration()
            self.configureSessionPreset(for: aspectRatio)
            captureSession.commitConfiguration()
        }

        // Restore zoom level after session reconfiguration
        if let zoom = currentZoom, let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
                self.zoomFactor = zoom
                print("[CameraPreview] Preserved zoom level \(zoom) after aspect ratio change")
            } catch {
                print("[CameraPreview] Failed to restore zoom level after aspect ratio change: \(error)")
            }
        }

        // Update preview layer geometry on the main thread
        DispatchQueue.main.async { [weak self, aspectRatio] in
            guard let self = self, let previewLayer = self.previewLayer else { return }
            
            // Reconfigure preview layer frame based on aspect ratio
            if let view = previewLayer.superlayer as? UIView {
                if let aspectRatio = aspectRatio {
                    let frame = self.calculateAspectRatioFrame(for: aspectRatio, in: view.bounds)
                    previewLayer.frame = frame
                    previewLayer.videoGravity = .resizeAspectFill
                } else {
                    previewLayer.frame = view.bounds
                    previewLayer.videoGravity = .resizeAspect
                }
                
                // Keep grid overlay in sync
                self.gridOverlayView?.frame = previewLayer.frame
            }
        }
    }
    
    /// Configure frame rate for optimal face detection performance (20-25 FPS)
    private func configureFrameRateForFaceDetection() {
        guard let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Find format that supports our target frame rate
            var targetFormat: AVCaptureDevice.Format?
            var targetFrameRateRange: AVFrameRateRange?
            
            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let width = dimensions.width
                let height = dimensions.height
                
                // Look for 720p or similar resolution
                if width >= 1280 && width <= 1920 && height >= 720 && height <= 1080 {
                    for range in format.videoSupportedFrameRateRanges {
                        // Find range that includes 20-25 FPS
                        if range.minFrameRate <= 25 && range.maxFrameRate >= 20 {
                            targetFormat = format
                            targetFrameRateRange = range
                            break
                        }
                    }
                    if targetFormat != nil {
                        break
                    }
                }
            }
            
            // Apply the optimized format and frame rate
            if let format = targetFormat {
                device.activeFormat = format
                
                if let range = targetFrameRateRange {
                    // Set to 25 FPS (balanced performance)
                    let targetFPS = min(25.0, range.maxFrameRate)
                    let frameDuration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
                    device.activeVideoMinFrameDuration = frameDuration
                    device.activeVideoMaxFrameDuration = frameDuration
                    print("[CameraController] Configured frame rate: \\(targetFPS) FPS")
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            print("[CameraController] Failed to configure frame rate: \\(error)")
        }
    }

    private func setInitialZoom(level: Float?) {
        guard let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera else {
            print("[CameraPreview] No device available for initial zoom")
            return
        }

        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, saneMaxZoomFactor)

        // Compute UI-level default (1×) when not provided
        let multiplier = self.getDisplayZoomMultiplier()
        // If level is nil, fall back to a UI zoom of 1.0×
        let uiLevel: Float = level ?? 1.0
        // Map UI/display zoom to native zoom using iOS 18+ multiplier
        let adjustedLevel = multiplier != 1.0 ? (uiLevel / multiplier) : uiLevel

        guard CGFloat(adjustedLevel) >= minZoom && CGFloat(adjustedLevel) <= maxZoom else {
            print("[CameraPreview] Initial zoom level \(adjustedLevel) out of range (\(minZoom)-\(maxZoom))")
            return
        }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(adjustedLevel)
            device.unlockForConfiguration()
            self.zoomFactor = CGFloat(adjustedLevel)
        } catch {
            print("[CameraPreview] Failed to set initial zoom: \(error)")
        }
    }

    private func configureDeviceInputs(cameraPosition: String, deviceId: String?, disableAudio: Bool) throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

        // Ensure cameras are discovered before configuring inputs
        ensureCamerasDiscovered()

        var selectedDevice: AVCaptureDevice?

        // If deviceId is specified, find that specific device from discovered devices
        if let deviceId = deviceId {
            selectedDevice = self.allDiscoveredDevices.first(where: { $0.uniqueID == deviceId })
            guard selectedDevice != nil else {
                throw CameraControllerError.noCamerasAvailable
            }
        } else {
            // Use position-based selection from discovered cameras
            if cameraPosition == "rear" {
                selectedDevice = self.rearCamera
            } else if cameraPosition == "front" {
                selectedDevice = self.frontCamera
            }
        }

        guard let finalDevice = selectedDevice else {
            throw CameraControllerError.noCamerasAvailable
        }

        let deviceInput = try AVCaptureDeviceInput(device: finalDevice)

        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)

            if finalDevice.position == .front {
                self.frontCameraInput = deviceInput
                self.currentCameraPosition = .front
            } else {
                self.rearCameraInput = deviceInput
                self.currentCameraPosition = .rear
            }
        } else {
            throw CameraControllerError.inputsAreInvalid
        }

        // Add audio input if needed
        if !disableAudio {
            if self.audioDevice == nil {
                self.audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
            }
            if let audioDevice = self.audioDevice {
                self.audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(self.audioInput!) {
                    captureSession.addInput(self.audioInput!)
                } else {
                    throw CameraControllerError.inputsAreInvalid
                }
            }
        }

        // Set default exposure mode to CONTINUOUS when starting the camera
        do {
            try finalDevice.lockForConfiguration()
            if finalDevice.isExposureModeSupported(.continuousAutoExposure) {
                finalDevice.exposureMode = .continuousAutoExposure
                if finalDevice.isExposurePointOfInterestSupported {
                    finalDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            // Reset exposure compensation so sessions start neutral
            let minBias = finalDevice.minExposureTargetBias
            let maxBias = finalDevice.maxExposureTargetBias
            let neutralBias = max(minBias, min(0.0, maxBias))
            finalDevice.setExposureTargetBias(neutralBias) { _ in }
            finalDevice.unlockForConfiguration()
        } catch {
            // Non-fatal; continue without setting default exposure
        }
    }

    func displayPreview(on view: UIView) throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }

        print("[CameraPreview] ⏱ Guard check took \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
        let layerStartTime = CFAbsoluteTimeGetCurrent()

        // Get preview layer - should already be created in prepareOutputs
        guard let previewLayer = self.previewLayer else {
            throw CameraControllerError.captureSessionIsMissing
        }

        // Session should already be set during configuration

        print("[CameraPreview] ⏱ Layer session update took \(CFAbsoluteTimeGetCurrent() - layerStartTime) seconds")

        let configStartTime = CFAbsoluteTimeGetCurrent()
        // Optimize layer configuration with explicit transaction
        CATransaction.begin()
        CATransaction.setDisableActions(true) // Disable implicit animations for faster setup
        CATransaction.setAnimationDuration(0) // No animation duration

        // Start with zero alpha for smooth fade-in
        previewLayer.opacity = 0

        // Configure video gravity and frame based on aspect ratio
        if let aspectRatio = requestedAspectRatio {
            // Calculate the frame based on requested aspect ratio
            let frame = calculateAspectRatioFrame(for: aspectRatio, in: view.bounds)
            previewLayer.frame = frame
            previewLayer.videoGravity = .resizeAspectFill
        } else {
            // No specific aspect ratio requested - fill the entire view
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspect
        }
        print("[CameraPreview] ⏱ Layer configuration took \(CFAbsoluteTimeGetCurrent() - configStartTime) seconds")

        let insertStartTime = CFAbsoluteTimeGetCurrent()
        // Set additional performance optimizations
        previewLayer.shouldRasterize = false // Avoid unnecessary rasterization
        previewLayer.drawsAsynchronously = true // Enable async rendering
        previewLayer.allowsGroupOpacity = true // Enable group opacity animations

        // Insert layer immediately (only if new)
        if previewLayer.superlayer != view.layer {
            view.layer.insertSublayer(previewLayer, at: 0)

            // Fade in the preview layer smoothly
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            previewLayer.opacity = 1.0
            CATransaction.commit()
        }

        CATransaction.commit()
        print("[CameraPreview] ⏱ Layer insertion took \(CFAbsoluteTimeGetCurrent() - insertStartTime) seconds")
        print("[CameraPreview] ⏱ Total display preview took \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
    }

    func addGridOverlay(to view: UIView, gridMode: String) {
        removeGridOverlay()

        // Disable animation for grid overlay creation and positioning
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Use preview layer frame if aspect ratio is specified, otherwise use full view bounds
        let gridFrame: CGRect
        if requestedAspectRatio != nil, let previewLayer = previewLayer {
            gridFrame = previewLayer.frame
        } else {
            gridFrame = view.bounds
        }

        gridOverlayView = GridOverlayView(frame: gridFrame)
        gridOverlayView?.gridMode = gridMode
        view.addSubview(gridOverlayView!)
        CATransaction.commit()
    }

    func removeGridOverlay() {
        gridOverlayView?.removeFromSuperview()
        gridOverlayView = nil
    }

    func updateVideoOrientation() {
        // Get orientation in a thread-safe way
        let videoOrientation = self.getVideoOrientation()

        // Apply orientation asynchronously on main thread
        let updateBlock = { [weak self] in
            guard let self = self else { return }
            self.previewLayer?.connection?.videoOrientation = videoOrientation
            self.dataOutput?.connections.forEach { $0.videoOrientation = videoOrientation }
            self.photoOutput?.connections.forEach { $0.videoOrientation = videoOrientation }
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    private func setDefaultZoomAfterFlip() {
        let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera
        guard let device = device else {
            print("[CameraPreview] No device available for default zoom after flip")
            return
        }

        // Set zoom to 1.0x in UI terms, accounting for display multiplier
        let multiplier = self.getDisplayZoomMultiplier()
        let targetUIZoom: Float = 1.0  // We want 1.0x in the UI
        let nativeZoom = multiplier != 1.0 ? (targetUIZoom / multiplier) : targetUIZoom

        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, saneMaxZoomFactor)
        let clampedZoom = max(minZoom, min(CGFloat(nativeZoom), maxZoom))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            self.zoomFactor = clampedZoom
            print("[CameraPreview] Set default zoom after flip: UI=\(targetUIZoom)x, native=\(clampedZoom), multiplier=\(multiplier)")
        } catch {
            print("[CameraPreview] Failed to set default zoom after flip: \(error)")
        }
    }

    // Helper: pick the best preset the TARGET device supports for a given aspect ratio
    private func bestPreset(for aspectRatio: String?, on device: AVCaptureDevice) -> AVCaptureSession.Preset {
        // Preference order depends on aspect ratio
        if aspectRatio == "16:9" {
            // Prefer 4K → 1080p → 720p → high → photo → vga
            if device.supportsSessionPreset(.hd4K3840x2160) { return .hd4K3840x2160 }
            if device.supportsSessionPreset(.hd1920x1080) { return .hd1920x1080 }
            if device.supportsSessionPreset(.hd1280x720) { return .hd1280x720 }
            if device.supportsSessionPreset(.high) { return .high }
            if device.supportsSessionPreset(.photo) { return .photo } // safe, though 4:3
            return .vga640x480
        } else {
            // 4:3 or unknown: prefer photo → high → 1080p → 720p → vga
            if device.supportsSessionPreset(.photo) { return .photo }
            if device.supportsSessionPreset(.high) { return .high }
            if device.supportsSessionPreset(.hd1920x1080) { return .hd1920x1080 }
            if device.supportsSessionPreset(.hd1280x720) { return .hd1280x720 }
            return .vga640x480
        }
    }

    func switchCameras() throws {
        guard let currentCameraPosition = currentCameraPosition,
              let captureSession = self.captureSession else {
            throw CameraControllerError.captureSessionIsMissing
        }

        // Determine the device we’re switching TO
        let targetDevice: AVCaptureDevice
        switch currentCameraPosition {
        case .front:
            guard let rear = rearCamera else { throw CameraControllerError.invalidOperation }
            targetDevice = rear
        case .rear:
            guard let front = frontCamera else { throw CameraControllerError.invalidOperation }
            targetDevice = front
        }

        // Compute the desired preset for the TARGET device up front
        let desiredPreset = bestPreset(for: self.requestedAspectRatio, on: targetDevice)

        // Keep the preview layer visually stable during the swap
        let savedPreviewFrame = self.previewLayer?.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.previewLayer?.connection?.isEnabled = false  // reduce visible glitching

        // No need to stopRunning; Apple recommends reconfiguring within begin/commit
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            self.previewLayer?.connection?.isEnabled = true
            // Restore frame (it shouldn't change, but this ensures zero animation)
            if let f = savedPreviewFrame { self.previewLayer?.frame = f }
            CATransaction.commit()
            DispatchQueue.main.async { [weak self] in
                self?.setDefaultZoomAfterFlip()   // normalize zoom (UI 1.0x)
            }
        }

        // Preserve audio input (if any)
        let existingAudioInput = captureSession.inputs.first {
            ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) ?? false
        }

        // Remove ONLY video inputs
        for input in captureSession.inputs {
            if (input as? AVCaptureDeviceInput)?.device.hasMediaType(.video) ?? false {
                captureSession.removeInput(input)
            }
        }

        // Only downgrade to a safe preset if the TARGET cannot support the CURRENT one
        let currentPreset = captureSession.sessionPreset
        let targetSupportsCurrent = targetDevice.supportsSessionPreset(currentPreset)
        if !targetSupportsCurrent {
            // Choose the first preset supported by BOTH the target device and the session
            let fallbacks: [AVCaptureSession.Preset] =
                (self.requestedAspectRatio == "16:9")
                ? [.hd4K3840x2160, .hd1920x1080, .hd1280x720, .high, .photo, .vga640x480]
                : [.photo, .high, .hd1920x1080, .hd1280x720, .vga640x480]
            for p in fallbacks {
                if targetDevice.supportsSessionPreset(p), captureSession.canSetSessionPreset(p) {
                    captureSession.sessionPreset = p
                    break
                }
            }
        }

        // Add the new video input
        let newInput = try AVCaptureDeviceInput(device: targetDevice)
        guard captureSession.canAddInput(newInput) else {
            throw CameraControllerError.invalidOperation
        }
        captureSession.addInput(newInput)

        // Update pointers / focus defaults
        if targetDevice.position == .front {
            self.frontCameraInput = newInput
            self.currentCameraPosition = .front
        } else {
            self.rearCameraInput = newInput
            self.currentCameraPosition = .rear
        }
        // (Lightweight focus config; non-fatal on failure)
        try? targetDevice.lockForConfiguration()
        if targetDevice.isFocusModeSupported(.continuousAutoFocus) {
            targetDevice.focusMode = .continuousAutoFocus
        }
        targetDevice.unlockForConfiguration()

        // Restore audio input if it existed
        if let audioInput = existingAudioInput, captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Now apply the BEST preset for the target device & requested AR
        if captureSession.sessionPreset != desiredPreset,
           targetDevice.supportsSessionPreset(desiredPreset),
           captureSession.canSetSessionPreset(desiredPreset) {
            captureSession.sessionPreset = desiredPreset
        }

        // Keep orientation correct
        self.updateVideoOrientation()
    }

    func captureImage(width: Int?, height: Int?, quality: Float, gpsLocation: CLLocation?, embedTimestamp: Bool, embedLocation: Bool, photoQualityPrioritization: String, completion: @escaping (UIImage?, Data?, [AnyHashable: Any]?, Error?) -> Void) {
        guard let photoOutput = self.photoOutput else {
            completion(nil, nil, nil, NSError(domain: "Camera", code: 0, userInfo: [NSLocalizedDescriptionKey: "Photo output is not available"]))
            return
        }

        let settings = AVCapturePhotoSettings()
        // Configure photo capture settings optimized for speed
        // Only use high res if explicitly requesting large dimensions
        let shouldUseHighRes = width.map { $0 > 1920 } ?? false || height.map { $0 > 1920 } ?? false
        settings.isHighResolutionPhotoEnabled = shouldUseHighRes
        if #available(iOS 15.0, *) {
            if photoQualityPrioritization == "quality" {
                settings.photoQualityPrioritization = .quality
            } else if photoQualityPrioritization == "balanced" {
                settings.photoQualityPrioritization = .balanced
            } else {
                // Default Prioritize speed over quality
                settings.photoQualityPrioritization = .speed
            }
        }

        // Apply the current flash mode to the photo settings
        // Check if the current device supports flash
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        // Only apply flash if the device has flash and the flash mode is supported
        if let device = currentCamera, device.hasFlash {
            let supportedFlashModes = photoOutput.supportedFlashModes
            if supportedFlashModes.contains(self.flashMode) {
                settings.flashMode = self.flashMode
            }
        }

        self.isCapturingPhoto = true

        self.photoCaptureCompletionBlock = { [weak self] (image, photoData, metadata, error) in
            guard let self = self else { return }
            if let error = error {
                completion(nil, nil, nil, error)
                // End capture lifecycle
                self.isCapturingPhoto = false
                if self.stopRequestedAfterCapture {
                    DispatchQueue.main.async { self.cleanup(); self.stopRequestedAfterCapture = false }
                }
                return
            }

            guard let image = image else {
                completion(nil, nil, nil, NSError(domain: "Camera", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to capture image"]))
                // End capture lifecycle
                self.isCapturingPhoto = false
                if self.stopRequestedAfterCapture {
                    DispatchQueue.main.async { self.cleanup(); self.stopRequestedAfterCapture = false }
                }
                return
            }

            if let location = gpsLocation {
                self.addGPSMetadata(to: image, location: location)
            }

            var finalImage = image

            // Determine what to do based on parameters
            if width != nil || height != nil {
                // When max dimensions are specified, we used high-res capture
                // First crop to aspect ratio if needed, then resize to max dimensions
                if let aspectRatio = self.requestedAspectRatio {
                    finalImage = self.cropImageToAspectRatio(image: image, aspectRatio: aspectRatio) ?? image
                    print("[CameraPreview] Cropped high-res image to aspect ratio \(aspectRatio)")
                }
                // Then resize to fit within maximum dimensions while maintaining aspect ratio
                finalImage = self.resizeImageToMaxDimensions(image: finalImage, maxWidth: width, maxHeight: height)!
                print("[CameraPreview] Resized to max dimensions: \(finalImage.size.width)x\(finalImage.size.height)")
            } else if let aspectRatio = self.requestedAspectRatio {
                // No max dimensions specified, but aspect ratio is specified
                // Always apply aspect ratio cropping to ensure correct orientation
                finalImage = self.cropImageToAspectRatio(image: image, aspectRatio: aspectRatio) ?? image
                print("[CameraPreview] Applied aspect ratio cropping for \(aspectRatio): \(finalImage.size.width)x\(finalImage.size.height)")
            }

            // Draw overlays if either flag is set (timestamp and/or location)
            if embedTimestamp || embedLocation {
                let when: String? = embedTimestamp
                    ? self.makeTimestampString(from: photoData, metadata: metadata)
                    : nil

                let whereStr: String? = embedLocation
                    ? self.makeLocationString(from: gpsLocation, photoData: photoData, metadata: metadata)
                    : nil

                if (when?.isEmpty ?? true) && (whereStr?.isEmpty ?? true) {
                    // Nothing to draw (e.g., embedLocation=true but no GPS present) → skip
                } else {
                    finalImage = self.drawTimestampAndLocation(on: finalImage, when: when, where: whereStr)
                }
            }

            completion(finalImage, photoData, metadata, nil)

            // End capture lifecycle
            self.isCapturingPhoto = false
            if self.stopRequestedAfterCapture {
                DispatchQueue.main.async { self.cleanup(); self.stopRequestedAfterCapture = false }
            }
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Draws timestamp and/or location pills at the top-right. Pass nil to skip either line.
    func drawTimestampAndLocation(on image: UIImage, when: String?, where whereStr: String?) -> UIImage {
        let base = image.fixedOrientation() ?? image
        let scale = base.scale
        let size  = base.size

        // Style (match drawTimestamp)
        let textColor: UIColor = .white
        let backgroundColor = UIColor(white: 0.12, alpha: 0.22)
        let paddingH: CGFloat = 16
        let paddingV: CGFloat = 10
        let cornerRadius: CGFloat = 10
        let margin: CGFloat = 12
        let gap: CGFloat = 8

        // ≈3.5% of image width (≥10pt)
        let fontPointSize = max(10, size.width * 0.035)
        let font: UIFont = .systemFont(ofSize: fontPointSize, weight: .semibold)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))

            func drawPill(_ text: String, top: CGFloat) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let textSize = (text as NSString).size(withAttributes: attrs)
                let bgSize  = CGSize(width: textSize.width + paddingH * 2,
                                     height: textSize.height + paddingV * 2)
                let origin  = CGPoint(x: size.width - bgSize.width - margin, y: top)
                let rect    = CGRect(origin: origin, size: bgSize)

                // shadowed rounded bg
                let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
                ctx.cgContext.saveGState()
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 2),
                                        blur: 6,
                                        color: UIColor.black.withAlphaComponent(0.25).cgColor)
                backgroundColor.setFill()
                path.fill()
                ctx.cgContext.restoreGState()

                // high-quality text
                let g = ctx.cgContext
                g.setAllowsAntialiasing(true)
                g.setShouldAntialias(true)
                g.setAllowsFontSmoothing(true)
                g.setShouldSmoothFonts(true)
                g.setShouldSubpixelPositionFonts(true)
                g.interpolationQuality = .high

                (text as NSString).draw(at: CGPoint(x: rect.minX + paddingH, y: rect.minY + paddingV),
                                        withAttributes: attrs)

                return rect.maxY
            }

            var top = margin
            if let w = when, !w.isEmpty {
                top = drawPill(w, top: top) + gap
            }
            if let loc = whereStr, !loc.isEmpty {
                _ = drawPill(loc, top: (top == margin ? margin : top))
            }
        }
    }

    func makeTimestampString(from photoData: Data?, metadata: [AnyHashable: Any]?) -> String {
        func extractDateString(from meta: [String: Any]) -> String? {
            if let exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                if let s = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String { return s }
                if let s = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String { return s }
            }
            if let tiff = meta[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                if let s = tiff[kCGImagePropertyTIFFDateTime as String] as? String { return s }
            }
            return nil
        }

        var raw: String?
        if let metadata = metadata as? [String: Any] {
            raw = extractDateString(from: metadata)
        }
        if raw == nil, let data = photoData,
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            raw = extractDateString(from: props)
        }

        let outFmt = DateFormatter()
        outFmt.locale = .current
        outFmt.timeZone = .current
        outFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        if let raw = raw {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = .current
            df.dateFormat = raw.contains(".") ? "yyyy:MM:dd HH:mm:ss.SSS" : "yyyy:MM:dd HH:mm:ss"
            if let d = df.date(from: raw) {
                return outFmt.string(from: d)
            }
        }

        return outFmt.string(from: Date())
    }

    func makeLocationString(from location: CLLocation?,
                            photoData: Data?,
                            metadata: [AnyHashable: Any]?) -> String? {
        // 1) Prefer the explicit CLLocation that was just provided
        if let loc = location {
            let lat = String(format: "%.5f", loc.coordinate.latitude)
            let lon = String(format: "%.5f", loc.coordinate.longitude)
            return "\(lat), \(lon)"
        }

        // 2) Fall back to EXIF GPS in metadata / photo data
        func extractGPS(_ meta: [String: Any]) -> (Double, Double)? {
            guard let gps = meta[kCGImagePropertyGPSDictionary as String] as? [String: Any] else { return nil }
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
               let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                let signedLat = (latRef.uppercased() == "S") ? -lat : lat
                let signedLon = (lonRef.uppercased() == "W") ? -lon : lon
                return (signedLat, signedLon)
            }
            return nil
        }

        if let md = metadata as? [String: Any], let (lat, lon) = extractGPS(md) {
            return String(format: "%.5f, %.5f", lat, lon)
        }

        if let data = photoData,
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
           let (lat, lon) = extractGPS(props) {
            return String(format: "%.5f, %.5f", lat, lon)
        }

        return nil
    }

    // Create JPEG data from `image`, merging the original EXIF/GPS/etc. and forcing Orientation=1.
    func jpegDataPreservingMetadata(from image: UIImage,
                                    originalPhotoData: Data?,
                                    originalMetadata: [AnyHashable: Any]?,
                                    quality: CGFloat = 0.9) -> Data? {
        // Encode pixels first
        guard let cgImg = image.cgImage else { return image.jpegData(compressionQuality: quality) }
        let uiImageData = UIImage(cgImage: cgImg, scale: image.scale, orientation: .up)
            .jpegData(compressionQuality: quality)

        // If we don’t have source metadata, just return the new JPEG
        guard let srcData = originalPhotoData, let newJPEG = uiImageData else { return uiImageData }

        // Load base metadata from source, then overlay any explicit metadata dict we were given
        let cgSrc = CGImageSourceCreateWithData(srcData as CFData, nil)
        let baseMetadata: [String: Any]
        if let src = cgSrc,
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            var merged = props
            if let explicit = originalMetadata as? [String: Any] {
                for (k, v) in explicit { merged[k] = v }
            }
            baseMetadata = merged
        } else if let explicit = originalMetadata as? [String: Any] {
            baseMetadata = explicit
        } else {
            return newJPEG
        }

        // Prepare destination
        let dstData = NSMutableData()
        guard let cgDst = CGImageDestinationCreateWithData(dstData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return newJPEG
        }

        // Force normalized orientation (pixels are already .up)
        var metaOut = baseMetadata
        if var tiff = metaOut[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metaOut[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        metaOut[kCGImagePropertyOrientation as String] = 1

        // Write the new pixels + merged metadata
        if let cgImage = UIImage(data: newJPEG)?.cgImage {
            CGImageDestinationAddImage(cgDst, cgImage, metaOut as CFDictionary)
            CGImageDestinationFinalize(cgDst)
            return (dstData as Data)
        }

        return newJPEG
    }

    func addGPSMetadata(to image: UIImage, location: CLLocation) {
        guard let jpegData = image.jpegData(compressionQuality: 1.0),
              let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let uti = CGImageSourceGetType(source) else { return }

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
        guard let destination = CGImageDestinationCreateWithData(destData, uti, 1, nil) else { return }
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        CGImageDestinationFinalize(destination)
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
        guard let ratio = parseAspectRatio(aspectRatio) else {
            print("[CameraPreview] cropImageToAspectRatio - Failed to parse aspect ratio: \(aspectRatio)")
            return image
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
        let targetAspectRatio = ratio.width / ratio.height

        print("[CameraPreview] cropImageToAspectRatio - Original image: \(imageSize.width)x\(imageSize.height) (ratio: \(imageAspectRatio))")
        print("[CameraPreview] cropImageToAspectRatio - Target ratio: \(ratio.width):\(ratio.height) (ratio: \(targetAspectRatio))")

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

    func getSupportedFlashModes() throws -> [String] {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard
            let device = currentCamera
        else {
            throw CameraControllerError.noCamerasAvailable
        }

        var supportedFlashModesAsStrings: [String] = []
        if device.hasFlash {
            guard let supportedFlashModes: [AVCaptureDevice.FlashMode] = self.photoOutput?.supportedFlashModes else {
                throw CameraControllerError.noCamerasAvailable
            }

            for flashMode in supportedFlashModes {
                var flashModeValue: String?
                switch flashMode {
                case AVCaptureDevice.FlashMode.off:
                    flashModeValue = "off"
                case AVCaptureDevice.FlashMode.on:
                    flashModeValue = "on"
                case AVCaptureDevice.FlashMode.auto:
                    flashModeValue = "auto"
                default: break
                }
                if flashModeValue != nil {
                    supportedFlashModesAsStrings.append(flashModeValue!)
                }
            }
        }
        if device.hasTorch {
            supportedFlashModesAsStrings.append("torch")
        }
        return supportedFlashModesAsStrings

    }

    func getHorizontalFov() throws -> Float {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard
            let device = currentCamera
        else {
            throw CameraControllerError.noCamerasAvailable
        }

        // Get the active format and field of view
        let activeFormat = device.activeFormat
        let fov = activeFormat.videoFieldOfView

        // Adjust for current zoom level
        let zoomFactor = device.videoZoomFactor
        let adjustedFov = fov / Float(zoomFactor)

        return adjustedFov
    }

    func setFlashMode(flashMode: AVCaptureDevice.FlashMode) throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        guard let supportedFlashModes: [AVCaptureDevice.FlashMode] = self.photoOutput?.supportedFlashModes else {
            throw CameraControllerError.invalidOperation
        }
        if supportedFlashModes.contains(flashMode) {
            do {
                try device.lockForConfiguration()

                if device.hasTorch && device.isTorchAvailable && device.torchMode == AVCaptureDevice.TorchMode.on {
                    device.torchMode = AVCaptureDevice.TorchMode.off
                }
                self.flashMode = flashMode
                let photoSettings = AVCapturePhotoSettings()
                photoSettings.flashMode = flashMode
                self.photoOutput?.photoSettingsForSceneMonitoring = photoSettings

                device.unlockForConfiguration()
            } catch {
                throw CameraControllerError.invalidOperation
            }
        } else {
            throw CameraControllerError.invalidOperation
        }
    }

    func setTorchMode() throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera!
        case .rear:
            currentCamera = self.rearCamera!
        default: break
        }

        guard
            let device = currentCamera,
            device.hasTorch,
            device.isTorchAvailable
        else {
            throw CameraControllerError.invalidOperation
        }

        do {
            try device.lockForConfiguration()
            if device.isTorchModeSupported(AVCaptureDevice.TorchMode.on) {
                device.torchMode = AVCaptureDevice.TorchMode.on
            } else if device.isTorchModeSupported(AVCaptureDevice.TorchMode.auto) {
                device.torchMode = AVCaptureDevice.TorchMode.auto
            } else {
                device.torchMode = AVCaptureDevice.TorchMode.off
            }
            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }

    func getZoom() throws -> (min: Float, max: Float, current: Float) {
        var currentCamera: AVCaptureDevice?

        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        let effectiveMaxZoom = min(device.maxAvailableVideoZoomFactor, self.saneMaxZoomFactor)

        return (
            min: Float(device.minAvailableVideoZoomFactor),
            max: Float(effectiveMaxZoom),
            current: Float(device.videoZoomFactor)
        )
    }

    func setZoom(level: CGFloat, ramp: Bool, autoFocus: Bool = true) throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        let effectiveMaxZoom = min(device.maxAvailableVideoZoomFactor, self.saneMaxZoomFactor)
        let zoomLevel = max(device.minAvailableVideoZoomFactor, min(level, effectiveMaxZoom))

        do {
            try device.lockForConfiguration()

            if ramp {
                // Use a very fast ramp rate for immediate response
                device.ramp(toVideoZoomFactor: zoomLevel, withRate: 8.0)
            } else {
                device.videoZoomFactor = zoomLevel
            }

            device.unlockForConfiguration()

            // Update our internal zoom factor tracking
            self.zoomFactor = zoomLevel

            // Trigger autofocus after zoom if requested
            if autoFocus {
                self.triggerAutoFocus()
            }
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }

    private func triggerAutoFocus() {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            return
        }

        // Focus on the center of the preview (0.5, 0.5)
        let centerPoint = CGPoint(x: 0.5, y: 0.5)

        do {
            try device.lockForConfiguration()

            // Set focus mode to auto if supported
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = centerPoint
                }
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = centerPoint
                }
            }

            if device.isExposurePointOfInterestSupported {
                let exposureMode = try getExposureMode()
                if exposureMode == "AUTO" || exposureMode == "CONTINUOUS" {
                    device.exposurePointOfInterest = centerPoint
                }
            }
            device.unlockForConfiguration()
        } catch {
            // Silently ignore errors during autofocus
        }
    }

    func setFocus(at point: CGPoint, showIndicator: Bool = false, in view: UIView? = nil) throws {
        // Validate that coordinates are within bounds (0-1 range for device coordinates)
        if point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1 {
            print("setFocus: Coordinates out of bounds - x: \(point.x), y: \(point.y)")
            throw CameraControllerError.invalidOperation
        }

        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default: break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        guard device.isFocusPointOfInterestSupported else {
            // Device doesn't support focus point of interest
            return
        }

        // Show focus indicator if enabled, requested and view is provided - only after validation
        if showIndicator, let view = view, let previewLayer = self.previewLayer {
            // Convert the device point to layer point for indicator display
            let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: point)
            showFocusIndicator(at: layerPoint, in: view)
        }

        do {
            try device.lockForConfiguration()

            // Set focus mode to auto if supported
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            // Set the focus point
            device.focusPointOfInterest = point

            // Also set exposure point if supported
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
                device.setExposureTargetBias(0.0) { _ in }
                device.exposurePointOfInterest = point
            }

            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.unknown
        }
    }

    func getFlashMode() throws -> String {
        switch self.flashMode {
        case .off:
            return "off"
        case .on:
            return "on"
        case .auto:
            return "auto"
        @unknown default:
            return "off"
        }
    }

    func getCurrentDeviceId() throws -> String {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        return device.uniqueID
    }

    func getCurrentLensInfo() throws -> (focalLength: Float, deviceType: String, baseZoomRatio: Float) {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        var deviceType = "wideAngle"
        var baseZoomRatio: Float = 1.0

        switch device.deviceType {
        case .builtInWideAngleCamera:
            deviceType = "wideAngle"
            baseZoomRatio = 1.0
        case .builtInUltraWideCamera:
            deviceType = "ultraWide"
            baseZoomRatio = 0.5
        case .builtInTelephotoCamera:
            deviceType = "telephoto"
            baseZoomRatio = 2.0
        case .builtInDualCamera:
            deviceType = "dual"
            baseZoomRatio = 1.0
        case .builtInDualWideCamera:
            deviceType = "dualWide"
            baseZoomRatio = 1.0
        case .builtInTripleCamera:
            deviceType = "triple"
            baseZoomRatio = 1.0
        case .builtInTrueDepthCamera:
            deviceType = "trueDepth"
            baseZoomRatio = 1.0
        default:
            deviceType = "wideAngle"
            baseZoomRatio = 1.0
        }

        // Approximate focal length for mobile devices
        let focalLength: Float = 4.25

        return (focalLength: focalLength, deviceType: deviceType, baseZoomRatio: baseZoomRatio)
    }

    func swapToDevice(deviceId: String) throws {
        guard let captureSession = self.captureSession else {
            throw CameraControllerError.captureSessionIsMissing
        }

        // Find the device with the specified deviceId
        let allDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        ).devices

        guard let targetDevice = allDevices.first(where: { $0.uniqueID == deviceId }) else {
            throw CameraControllerError.noCamerasAvailable
        }

        // Store the current running state
        let wasRunning = captureSession.isRunning
        if wasRunning {
            captureSession.stopRunning()
        }

        // Begin configuration
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            // Restart the session if it was running before
            if wasRunning {
                captureSession.startRunning()
            }
        }

        // Store audio input if it exists
        let audioInput = captureSession.inputs.first { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) ?? false }

        // Remove only video inputs
        captureSession.inputs.forEach { input in
            if (input as? AVCaptureDeviceInput)?.device.hasMediaType(.video) ?? false {
                captureSession.removeInput(input)
            }
        }

        // Configure the new device
        let newInput = try AVCaptureDeviceInput(device: targetDevice)

        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)

            // Update camera references based on device position
            if targetDevice.position == .front {
                self.frontCameraInput = newInput
                self.frontCamera = targetDevice
                self.currentCameraPosition = .front
            } else {
                self.rearCameraInput = newInput
                self.rearCamera = targetDevice
                self.currentCameraPosition = .rear

                // Configure rear camera
                try targetDevice.lockForConfiguration()
                if targetDevice.isFocusModeSupported(.continuousAutoFocus) {
                    targetDevice.focusMode = .continuousAutoFocus
                }
                targetDevice.unlockForConfiguration()
            }
        } else {
            throw CameraControllerError.invalidOperation
        }

        // Re-add audio input if it existed
        if let audioInput = audioInput, captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Update video orientation
        self.updateVideoOrientation()
    }

    func cleanup() {
        if let captureSession = self.captureSession {
            captureSession.stopRunning()
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            captureSession.outputs.forEach { captureSession.removeOutput($0) }
        }

        self.previewLayer?.removeFromSuperlayer()
        self.previewLayer = nil

        self.focusIndicatorView?.removeFromSuperview()
        self.focusIndicatorView = nil

        self.frontCameraInput = nil
        self.rearCameraInput = nil
        self.audioInput = nil

        self.frontCamera = nil
        self.rearCamera = nil
        self.audioDevice = nil
        self.allDiscoveredDevices = []

        self.dataOutput = nil
        self.photoOutput = nil
        self.fileVideoOutput = nil

        self.captureSession = nil
        self.currentCameraPosition = nil

        // Reset output preparation status
        self.outputsPrepared = false

        // Reset first frame detection
        self.hasReceivedFirstFrame = false
        self.firstFrameReadyCallback = nil
    }

    // MARK: - Exposure Controls

    func getExposureModes() throws -> [String] {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        var modes: [String] = []
        if device.isExposureModeSupported(.locked) { modes.append("LOCK") }
        if device.isExposureModeSupported(.autoExpose) { modes.append("AUTO") }
        if device.isExposureModeSupported(.continuousAutoExposure) { modes.append("CONTINUOUS") }
        if device.isExposureModeSupported(.custom) { modes.append("CUSTOM") }
        return modes
    }

    func getExposureMode() throws -> String {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        switch device.exposureMode {
        case .locked:
            return "LOCK"
        case .autoExpose:
            return "AUTO"
        case .continuousAutoExposure:
            return "CONTINUOUS"
        case .custom:
            return "CUSTOM"
        @unknown default:
            return "CONTINUOUS"
        }
    }

    func setExposureMode(mode: String) throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        let normalized = mode.uppercased()
        let desiredMode: AVCaptureDevice.ExposureMode?
        switch normalized {
        case "LOCK":
            desiredMode = .locked
        case "AUTO":
            desiredMode = .autoExpose
        case "CONTINUOUS":
            desiredMode = .continuousAutoExposure
        case "CUSTOM":
            desiredMode = .custom
        default:
            desiredMode = .continuousAutoExposure
        }

        guard let finalMode = desiredMode, device.isExposureModeSupported(finalMode) else {
            throw CameraControllerError.invalidOperation
        }

        do {
            try device.lockForConfiguration()
            device.exposureMode = finalMode
            // Reset EV to 0 when switching to AUTO or CONTINUOUS
            if finalMode == .autoExpose || finalMode == .continuousAutoExposure {
                device.setExposureTargetBias(0.0) { _ in }
            }
            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }

    func getExposureCompensationRange() throws -> (min: Float, max: Float, step: Float) {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        // iOS reports EV bias directly; typical step is 0.1 or 0.125 depending on device
        // There's no direct API for step; approximate as 0.1 for compatibility
        let step: Float = 0.1
        return (min: device.minExposureTargetBias, max: device.maxExposureTargetBias, step: step)
    }

    func getExposureCompensation() throws -> Float {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        return device.exposureTargetBias
    }

    func setExposureCompensation(_ value: Float) throws {
        var currentCamera: AVCaptureDevice?
        switch currentCameraPosition {
        case .front:
            currentCamera = self.frontCamera
        case .rear:
            currentCamera = self.rearCamera
        default:
            break
        }

        guard let device = currentCamera else {
            throw CameraControllerError.noCamerasAvailable
        }

        let clamped = max(device.minExposureTargetBias, min(value, device.maxExposureTargetBias))

        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped) { _ in }
            device.unlockForConfiguration()
        } catch {
            throw CameraControllerError.invalidOperation
        }
    }

    func captureVideo() throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CameraControllerError.cannotFindDocumentsDirectory
        }

        guard let fileVideoOutput = self.fileVideoOutput else {
            throw CameraControllerError.fileVideoOutputNotFound
        }

        // Ensure the movie file output is attached to the active session.
        // If the camera was started without cameraMode=true, the output may not have been added yet.
        if !captureSession.outputs.contains(where: { $0 === fileVideoOutput }) {
            captureSession.beginConfiguration()
            if captureSession.canAddOutput(fileVideoOutput) {
                captureSession.addOutput(fileVideoOutput)
            } else {
                captureSession.commitConfiguration()
                throw CameraControllerError.invalidOperation
            }
            captureSession.commitConfiguration()
        }

        // cpcp_video_A6C01203 - portrait
        //
        if let connection = fileVideoOutput.connection(with: .video) {
            if connection.isEnabled == false { connection.isEnabled = true }
            switch UIDevice.current.orientation {
            case .landscapeRight:
                connection.videoOrientation = .landscapeLeft
            case .landscapeLeft:
                connection.videoOrientation = .landscapeRight
            case .portrait:
                connection.videoOrientation = .portrait
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            default:
                connection.videoOrientation = .portrait
            }
        }

        let identifier = UUID()
        let randomIdentifier = identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let finalIdentifier = String(randomIdentifier.prefix(8))
        let fileName="cpcp_video_"+finalIdentifier+".mp4"

        let fileUrl = documentsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileUrl)

        // Start recording video
        fileVideoOutput.startRecording(to: fileUrl, recordingDelegate: self)

        // Save the file URL for later use
        self.videoFileURL = fileUrl
    }

    func stopRecording(completion: @escaping (URL?, Error?) -> Void) {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            completion(nil, CameraControllerError.captureSessionIsMissing)
            return
        }
        guard let fileVideoOutput = self.fileVideoOutput else {
            completion(nil, CameraControllerError.fileVideoOutputNotFound)
            return
        }

        // Stop recording video
        fileVideoOutput.stopRecording()

        // Return the video file URL in the completion handler
        completion(self.videoFileURL, nil)
    }
}

extension CameraController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc
    func handleTap(_ tap: UITapGestureRecognizer) {
        guard let device = self.currentCameraPosition == .rear ? rearCamera : frontCamera else { return }

        let point = tap.location(in: tap.view)
        let devicePoint = self.previewLayer?.captureDevicePointConverted(fromLayerPoint: point)

        // Show focus indicator at the tap point if not disabled
        if !self.disableFocusIndicator, let view = tap.view {
            showFocusIndicator(at: point, in: view)
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let focusMode = AVCaptureDevice.FocusMode.autoFocus
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                device.focusPointOfInterest = CGPoint(x: CGFloat(devicePoint?.x ?? 0), y: CGFloat(devicePoint?.y ?? 0))
                device.focusMode = focusMode
            }

            let exposureMode = AVCaptureDevice.ExposureMode.autoExpose
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = CGPoint(x: CGFloat(devicePoint?.x ?? 0), y: CGFloat(devicePoint?.y ?? 0))
                device.exposureMode = exposureMode
                device.setExposureTargetBias(0.0) { _ in }
            }
        } catch {
            debugPrint(error)
        }
    }

    private func showFocusIndicator(at point: CGPoint, in view: UIView) {
        // Remove any existing focus indicator
        focusIndicatorView?.removeFromSuperview()

        // Create a new focus indicator (iOS Camera style): square with mid-edge ticks
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        indicator.center = point
        indicator.layer.borderColor = UIColor.yellow.cgColor
        indicator.layer.borderWidth = 2.0
        indicator.layer.cornerRadius = 0
        indicator.backgroundColor = UIColor.clear
        indicator.alpha = 0
        indicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)

        // Add 4 tiny mid-edge ticks inside the square
        let stroke: CGFloat = 2.0
        let tickLen: CGFloat = 12.0
        let inset: CGFloat = stroke // ticks should touch the sides
        // Top tick (perpendicular): vertical inward from top edge
        let topTick = UIView(frame: CGRect(x: (indicator.bounds.width - stroke)/2,
                                           y: inset,
                                           width: stroke,
                                           height: tickLen))
        topTick.backgroundColor = .yellow
        indicator.addSubview(topTick)
        // Bottom tick (perpendicular): vertical inward from bottom edge
        let bottomTick = UIView(frame: CGRect(x: (indicator.bounds.width - stroke)/2,
                                              y: indicator.bounds.height - inset - tickLen,
                                              width: stroke,
                                              height: tickLen))
        bottomTick.backgroundColor = .yellow
        indicator.addSubview(bottomTick)
        // Left tick (perpendicular): horizontal inward from left edge
        let leftTick = UIView(frame: CGRect(x: inset,
                                            y: (indicator.bounds.height - stroke)/2,
                                            width: tickLen,
                                            height: stroke))
        leftTick.backgroundColor = .yellow
        indicator.addSubview(leftTick)
        // Right tick (perpendicular): horizontal inward from right edge
        let rightTick = UIView(frame: CGRect(x: indicator.bounds.width - inset - tickLen,
                                             y: (indicator.bounds.height - stroke)/2,
                                             width: tickLen,
                                             height: stroke))
        rightTick.backgroundColor = .yellow
        indicator.addSubview(rightTick)

        view.addSubview(indicator)
        focusIndicatorView = indicator

        // Animate the focus indicator
        UIView.animate(withDuration: 0.15, animations: {
            indicator.alpha = 1.0
            indicator.transform = CGAffineTransform.identity
        }) { _ in
            // Keep the indicator visible briefly
            UIView.animate(withDuration: 0.2, delay: 0.5, options: [], animations: {
                indicator.alpha = 0.3
            }) { _ in
                // Fade out and remove
                UIView.animate(withDuration: 0.3, delay: 0.2, options: [], animations: {
                    indicator.alpha = 0
                    indicator.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                }) { _ in
                    indicator.removeFromSuperview()
                    if self.focusIndicatorView == indicator {
                        self.focusIndicatorView = nil
                    }
                }
            }
        }
    }

    @objc
    private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        guard let device = self.currentCameraPosition == .rear ? rearCamera : frontCamera else { return }

        let effectiveMaxZoom = min(device.maxAvailableVideoZoomFactor, self.saneMaxZoomFactor)
        func minMaxZoom(_ factor: CGFloat) -> CGFloat { return max(device.minAvailableVideoZoomFactor, min(factor, effectiveMaxZoom)) }

        switch pinch.state {
        case .began:
            // Store the initial zoom factor when pinch begins
            zoomFactor = device.videoZoomFactor

        case .changed:
            // Throttle zoom updates to prevent excessive CPU usage
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastZoomUpdateTime >= zoomUpdateThrottle else { return }
            lastZoomUpdateTime = currentTime

            // Calculate new zoom factor based on pinch scale
            let newScaleFactor = minMaxZoom(pinch.scale * zoomFactor)

            // Use ramping for smooth zoom transitions during pinch
            // This provides much smoother performance than direct setting
            do {
                try device.lockForConfiguration()
                // Use a very fast ramp rate for immediate response
                device.ramp(toVideoZoomFactor: newScaleFactor, withRate: 5.0)
                device.unlockForConfiguration()
            } catch {
                debugPrint("Failed to set zoom: \(error)")
            }

        case .ended:
            // Update our internal zoom factor tracking
            zoomFactor = device.videoZoomFactor

        default: break
        }
    }
}

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

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Check if we're waiting for the first frame
        if !hasReceivedFirstFrame, let firstFrameCallback = firstFrameReadyCallback {
            hasReceivedFirstFrame = true
            firstFrameCallback()
            firstFrameReadyCallback = nil
            // If no capture is in progress, we can return early
            if sampleBufferCaptureCompletionBlock == nil {
                // Process face detection even if no capture is happening
                if let faceDetectionManager = faceDetectionManager, faceDetectionManager.isRunning() {
                    faceDetectionManager.processSampleBuffer(sampleBuffer)
                }
                return
            }
        }

        // Process face detection if active
        if let faceDetectionManager = faceDetectionManager, faceDetectionManager.isRunning() {
            faceDetectionManager.processSampleBuffer(sampleBuffer)
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
            print("down")
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: CGFloat.pi / 2.0)
            print("left")
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: CGFloat.pi / -2.0)
            print("right")
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }

        // Flip image one more time if needed to, this is to prevent flipped image
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            _ = transform.translatedBy(x: size.width, y: 0)
            _ = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            _ = transform.translatedBy(x: size.height, y: 0)
            _ = transform.scaledBy(x: -1, y: 1)
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
        return UIImage.init(cgImage: newCGImage, scale: 1, orientation: .up)
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error recording movie: \(error.localizedDescription)")
        } else {
            print("Movie recorded successfully: \(outputFileURL)")
            // You can save the file to the library, upload it, etc.
        }
    }
}
