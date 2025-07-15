import Foundation
import Capacitor
import AVFoundation

extension UIWindow {
    static var isLandscape: Bool {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.windows
                .first?
                .windowScene?
                .interfaceOrientation
                .isLandscape ?? false
        } else {
            return UIApplication.shared.statusBarOrientation.isLandscape
        }
    }
    static var isPortrait: Bool {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.windows
                .first?
                .windowScene?
                .interfaceOrientation
                .isPortrait ?? false
        } else {
            return UIApplication.shared.statusBarOrientation.isPortrait
        }
    }
}

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(CameraPreview)
public class CameraPreview: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CameraPreviewPlugin"
    public let jsName = "CameraPreview"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "flip", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "capture", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "captureSample", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSupportedFlashModes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getHorizontalFov", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setFlashMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startRecordVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecordVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getTempFilePath", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSupportedPictureSizes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isRunning", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAvailableDevices", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getZoom", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setZoom", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getFlashMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setDeviceId", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDeviceId", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAvailableLenses", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentLens", returnType: CAPPluginReturnPromise)
    ]
    // Camera state tracking
    private var isInitializing: Bool = false
    private var isInitialized: Bool = false

    var previewView: UIView!
    var cameraPosition = String()
    let cameraController = CameraController()
    var posX: CGFloat?
    var posY: CGFloat?
    var width: CGFloat?
    var height: CGFloat?
    var paddingBottom: CGFloat?
    var rotateWhenOrientationChanged: Bool?
    var toBack: Bool?
    var storeToFile: Bool?
    var enableZoom: Bool?
    var highResolutionOutput: Bool = false
    var disableAudio: Bool = false

    // MARK: - Transparency Methods
    
    private func makeWebViewTransparent() {
        guard let webView = self.webView else { return }
        
        // Set basic transparency properties
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        // Make all subviews transparent
        webView.subviews.forEach { subview in
            if subview != webView.scrollView {
                subview.backgroundColor = UIColor.clear
            }
        }
        
        // Specifically handle the scroll view's subviews
        webView.scrollView.subviews.forEach { subview in
            subview.backgroundColor = UIColor.clear
        }
        
        // Set the superview background to clear if it exists
        webView.superview?.backgroundColor = UIColor.clear
        
        // Force a layout pass to apply changes
        DispatchQueue.main.async {
            webView.setNeedsLayout()
            webView.layoutIfNeeded()
        }
    }

    @objc func rotated() {
        guard let previewView = self.previewView,
              let posX = self.posX,
              let posY = self.posY,
              let width = self.width,
              let heightValue = self.height else {
            return
        }
        let paddingBottom = self.paddingBottom ?? 0
        let height = heightValue - paddingBottom

        if UIWindow.isLandscape {
            previewView.frame = CGRect(x: posY, y: posX, width: max(height, width), height: min(height, width))
            self.cameraController.previewLayer?.frame = previewView.frame
        }

        if UIWindow.isPortrait {
            previewView.frame = CGRect(x: posX, y: posY, width: min(height, width), height: max(height, width))
            self.cameraController.previewLayer?.frame = previewView.frame
        }

        if let connection = self.cameraController.fileVideoOutput?.connection(with: .video) {
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

        cameraController.updateVideoOrientation()
        
        // Ensure webview remains transparent after rotation
        if self.isInitialized {
            self.makeWebViewTransparent()
        }
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

    @objc func start(_ call: CAPPluginCall) {
        if self.isInitializing {
            call.reject("camera initialization in progress")
            return
        }
        if self.isInitialized {
            call.reject("camera already started")
            return
        }
        self.isInitializing = true

        self.cameraPosition = call.getString("position") ?? "rear"
        let deviceId = call.getString("deviceId")
        let cameraMode = call.getBool("cameraMode") ?? false
        self.highResolutionOutput = call.getBool("enableHighResolution") ?? false
        self.cameraController.highResolutionOutput = self.highResolutionOutput

        if call.getInt("width") != nil {
            self.width = CGFloat(call.getInt("width")!)
        } else {
            self.width = UIScreen.main.bounds.size.width
        }
        if call.getInt("height") != nil {
            self.height = CGFloat(call.getInt("height")!)
        } else {
            self.height = UIScreen.main.bounds.size.height
        }
        self.posX = call.getInt("x") != nil ? CGFloat(call.getInt("x")!)/UIScreen.main.scale: 0
        self.posY = call.getInt("y") != nil ? CGFloat(call.getInt("y")!) / (call.getBool("includeSafeAreaInsets") ?? false ? 1.0 : UIScreen.main.scale) + (call.getBool("includeSafeAreaInsets") ?? false ? UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0 : 0) : 0
        if call.getInt("paddingBottom") != nil {
            self.paddingBottom = CGFloat(call.getInt("paddingBottom")!)
        }

        self.rotateWhenOrientationChanged = call.getBool("rotateWhenOrientationChanged") ?? true
        self.toBack = call.getBool("toBack") ?? false
        self.storeToFile = call.getBool("storeToFile") ?? false
        self.enableZoom = call.getBool("enableZoom") ?? false
        self.disableAudio = call.getBool("disableAudio") ?? false

        AVCaptureDevice.requestAccess(for: .video, completionHandler: { (granted: Bool) in
            guard granted else {
                call.reject("permission failed")
                return
            }

            DispatchQueue.main.async {
                if self.cameraController.captureSession?.isRunning ?? false {
                    call.reject("camera already started")
                } else {
                    self.cameraController.prepare(cameraPosition: self.cameraPosition, deviceId: deviceId, disableAudio: self.disableAudio, cameraMode: cameraMode) {error in
                        if let error = error {
                            print(error)
                            call.reject(error.localizedDescription)
                            return
                        }
                        let height = self.paddingBottom != nil ? self.height! - self.paddingBottom!: self.height!
                        self.previewView = UIView(frame: CGRect(x: self.posX ?? 0, y: self.posY ?? 0, width: self.width!, height: height))
                        
                        // Make webview transparent - comprehensive approach
                        self.makeWebViewTransparent()
                        
                        self.webView?.superview?.addSubview(self.previewView)
                        if self.toBack! {
                            self.webView?.superview?.bringSubviewToFront(self.webView!)
                        }
                        try? self.cameraController.displayPreview(on: self.previewView)

                        let frontView = self.toBack! ? self.webView : self.previewView
                        self.cameraController.setupGestures(target: frontView ?? self.previewView, enableZoom: self.enableZoom!)

                        if self.rotateWhenOrientationChanged == true {
                            NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
                        }
                        
                        // Add observers for app state changes to maintain transparency
                        NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
                        NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

                        self.isInitializing = false
                        self.isInitialized = true
                        call.resolve()

                    }
                }
            }
        })

    }

    @objc func flip(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Camera controller deallocated")
                return
            }

            // Disable user interaction during flip
            self.previewView.isUserInteractionEnabled = false

            // Perform camera switch on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                var retryCount = 0
                let maxRetries = 3

                func attemptFlip() {
                    do {
                        try self.cameraController.switchCameras()

                        DispatchQueue.main.async {
                            self.cameraController.previewLayer?.frame = self.previewView.bounds
                            self.cameraController.previewLayer?.videoGravity = .resizeAspectFill
                            self.previewView.isUserInteractionEnabled = true
                            
                            // Ensure webview remains transparent after flip
                            self.makeWebViewTransparent()
                            
                            call.resolve()
                        }
                    } catch {
                        retryCount += 1

                        if retryCount < maxRetries {
                            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                                attemptFlip()
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.previewView.isUserInteractionEnabled = true
                                print("Failed to flip camera after \(maxRetries) attempts: \(error.localizedDescription)")
                                call.reject("Failed to flip camera: \(error.localizedDescription)")
                            }
                        }
                    }
                }

                attemptFlip()
            }
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.isInitializing {
                call.reject("cannot stop camera while initialization is in progress")
                return
            }
            if !self.isInitialized {
                call.reject("camera not initialized")
                return
            }

            // Always attempt to stop and clean up, regardless of captureSession state
            if let previewView = self.previewView {
                previewView.removeFromSuperview()
                self.previewView = nil
            }

            self.webView?.isOpaque = true
            self.isInitialized = false
            self.isInitializing = false
            self.cameraController.cleanup()
            
            // Remove notification observers
            NotificationCenter.default.removeObserver(self)

            call.resolve()
        }
    }
    // Get user's cache directory path
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
        DispatchQueue.main.async {

            let quality: Int? = call.getInt("quality", 85)

            self.cameraController.captureImage { (image, error) in

                guard let image = image else {
                    print(error ?? "Image capture error")
                    guard let error = error else {
                        call.reject("Image capture error")
                        return
                    }
                    call.reject(error.localizedDescription)
                    return
                }
                let imageData: Data?
                if self.cameraController.currentCameraPosition == .front {
                    let flippedImage = image.withHorizontallyFlippedOrientation()
                    imageData = flippedImage.jpegData(compressionQuality: CGFloat(quality!/100))
                } else {
                    imageData = image.jpegData(compressionQuality: CGFloat(quality!/100))
                }

                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve(["value": imageBase64!])
                } else {
                    do {
                        let fileUrl=self.getTempFilePath()
                        try imageData?.write(to: fileUrl)
                        call.resolve(["value": fileUrl.absoluteString])
                    } catch {
                        call.reject("error writing image to file")
                    }
                }
            }
        }
    }

    @objc func captureSample(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let quality: Int? = call.getInt("quality", 85)

            self.cameraController.captureSample { image, error in
                guard let image = image else {
                    print("Image capture error: \(String(describing: error))")
                    call.reject("Image capture error: \(String(describing: error))")
                    return
                }

                let imageData: Data?
                if self.cameraPosition == "front" {
                    let flippedImage = image.withHorizontallyFlippedOrientation()
                    imageData = flippedImage.jpegData(compressionQuality: CGFloat(quality!/100))
                } else {
                    imageData = image.jpegData(compressionQuality: CGFloat(quality!/100))
                }

                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve(["value": imageBase64!])
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

    @objc func getSupportedFlashModes(_ call: CAPPluginCall) {
        do {
            let supportedFlashModes = try self.cameraController.getSupportedFlashModes()
            call.resolve(["result": supportedFlashModes])
        } catch {
            call.reject("failed to get supported flash modes")
        }
    }

    @objc func getHorizontalFov(_ call: CAPPluginCall) {
        do {
            let horizontalFov = try self.cameraController.getHorizontalFov()
            call.resolve(["result": horizontalFov])
        } catch {
            call.reject("failed to get FOV")
        }
    }

    @objc func setFlashMode(_ call: CAPPluginCall) {
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
            if flashModeAsEnum != nil {
                try self.cameraController.setFlashMode(flashMode: flashModeAsEnum!)
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
        DispatchQueue.main.async {
            do {
                try self.cameraController.captureVideo()
                call.resolve()
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func stopRecordVideo(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
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

        let devices = session.devices.map { device in
            var position = "rear"
            switch device.position {
            case .front:
                position = "front"
            case .back:
                position = "rear"
            case .unspecified:
                position = "unspecified"
            @unknown default:
                position = "unknown"
            }

            var deviceType = "wideAngle"
            switch device.deviceType {
            case .builtInWideAngleCamera:
                deviceType = "wideAngle"
            case .builtInUltraWideCamera:
                deviceType = "ultraWide"
            case .builtInTelephotoCamera:
                deviceType = "telephoto"
            case .builtInDualCamera:
                deviceType = "dual"
            case .builtInDualWideCamera:
                deviceType = "dualWide"
            case .builtInTripleCamera:
                deviceType = "triple"
            case .builtInTrueDepthCamera:
                deviceType = "trueDepth"
            default:
                deviceType = "wideAngle"
            }

            return [
                "deviceId": device.uniqueID,
                "label": device.localizedName,
                "position": position,
                "deviceType": deviceType
            ]
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
            call.resolve([
                "min": zoomInfo.min,
                "max": zoomInfo.max,
                "current": zoomInfo.current
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

        guard let level = call.getFloat("level") else {
            call.reject("level parameter is required")
            return
        }

        let ramp = call.getBool("ramp") ?? true

        do {
            try self.cameraController.setZoom(level: CGFloat(level), ramp: ramp)
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

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Camera controller deallocated")
                return
            }

            // Disable user interaction during device swap
            self.previewView.isUserInteractionEnabled = false

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.cameraController.swapToDevice(deviceId: deviceId)

                    DispatchQueue.main.async {
                        self.cameraController.previewLayer?.frame = self.previewView.bounds
                        self.cameraController.previewLayer?.videoGravity = .resizeAspectFill
                        self.previewView.isUserInteractionEnabled = true
                        
                        // Ensure webview remains transparent after device switch
                        self.makeWebViewTransparent()
                        
                        call.resolve()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.previewView.isUserInteractionEnabled = true
                        call.reject("Failed to swap to device \(deviceId): \(error.localizedDescription)")
                    }
                }
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

    @objc func getAvailableLenses(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            let lenses = try self.cameraController.getAvailableLenses()
            call.resolve(["lenses": lenses])
        } catch {
            call.reject("Failed to get available lenses: \(error.localizedDescription)")
        }
    }

    @objc func getCurrentLens(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        do {
            let lens = try self.cameraController.getCurrentLens()
            call.resolve(["lens": lens])
        } catch {
            call.reject("Failed to get current lens: \(error.localizedDescription)")
        }
    }

}
