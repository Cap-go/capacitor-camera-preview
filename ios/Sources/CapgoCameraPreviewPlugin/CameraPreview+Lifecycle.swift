import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    @objc func start(_ call: CAPPluginCall) {
        startOnMain(call)
    }

    func startOnMain(_ call: CAPPluginCall) {
        logStartSettings(call)

        let force = call.getBool("force") ?? false
        guard prepareForCameraStart(force: force, call: call) else { return }

        self.isInitializing = true
        self.hasResolvedStartCall = false

        let options = applyStartOptions(from: call)
        guard validateStartSizing(call) else { return }

        let beginStart = {
            self.beginCameraStart(call: call, options: options, force: force)
        }

        let handleDenied: (AVAuthorizationStatus) -> Void = { _ in
            DispatchQueue.main.async {
                self.isInitializing = false
                self.pendingStartBarcodeScannerOptions = nil
                call.reject("camera permission denied. enable camera access in Settings.", "cameraPermissionDenied")
            }
        }

        requestCameraAuthorization(beginStart: beginStart, handleDenied: handleDenied)
    }

    struct CameraStartOptions {
        let deviceId: String?
        let cameraMode: Bool
        let videoQuality: String
        let initialZoomLevel: Float?
    }

    func logStartSettings(_ call: CAPPluginCall) {
        print("[CameraPreview] 🚀 START CALLED at \(Date())")
        print("[CameraPreview] 📋 Settings received:")

        let entries = [
            "position: \(call.getString("position") ?? "rear")",
            "deviceId: \(call.getString("deviceId") ?? "nil")",
            "cameraMode: \(call.getBool("cameraMode") ?? false)",
            "width: \(call.getInt("width") ?? 0)",
            "height: \(call.getInt("height") ?? 0)",
            "x: \(call.getInt("x") ?? -1)",
            "y: \(call.getInt("y") ?? -1)",
            "paddingBottom: \(call.getInt("paddingBottom") ?? 0)",
            "rotateWhenOrientationChanged: \(call.getBool("rotateWhenOrientationChanged") ?? true)",
            "toBack: \(call.getBool("toBack") ?? true)",
            "storeToFile: \(call.getBool("storeToFile") ?? false)",
            "disableAudio: \(call.getBool("disableAudio") ?? true)",
            "aspectRatio: \(call.getString("aspectRatio") ?? "4:3")",
            "gridMode: \(call.getString("gridMode") ?? "none")",
            "positioning: \(call.getString("positioning") ?? "top")",
            "initialZoomLevel: \(call.getFloat("initialZoomLevel") ?? 1.0)",
            "disableFocusIndicator: \(call.getBool("disableFocusIndicator") ?? false)",
            "force: \(call.getBool("force") ?? false)",
            "videoQuality: \(call.getString("videoQuality") ?? "high")"
        ]
        entries.forEach { print("  - \($0)") }
    }

    func prepareForCameraStart(force: Bool, call: CAPPluginCall) -> Bool {
        if force {
            forceStopIfNeeded()
            return true
        }

        if self.isInitializing {
            call.reject("camera initialization in progress")
            return false
        }
        if self.isInitialized {
            call.reject("camera already started")
            return false
        }
        if self.cameraController.isCapturingPhoto || self.cameraController.stopRequestedAfterCapture {
            call.reject("camera is stopping or busy, please retry shortly")
            return false
        }
        return true
    }

    func forceStopIfNeeded() {
        guard self.isInitializing ||
                self.isInitialized ||
                self.cameraController.isCapturingPhoto ||
                self.cameraController.stopRequestedAfterCapture else {
            return
        }

        let teardown = {
            self.cameraController.removeGridOverlay()
            if let previewView = self.previewView {
                previewView.removeFromSuperview()
                self.previewView = nil
            }

            if let webView = self.webView {
                webView.isOpaque = true
                self.restoreWebViewBackground(webView)
            }

            self.cameraController.stopRequestedAfterCapture = false
            self.cameraController.cleanup()
            NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
            self.stopOrientationNotificationsIfNeeded()
            self.isInitialized = false
            self.isInitializing = false
        }

        if Thread.isMainThread {
            teardown()
        } else {
            DispatchQueue.main.sync(execute: teardown)
        }
    }

    func stopOrientationNotificationsIfNeeded() {
        guard self.isGeneratingDeviceOrientationNotifications else { return }

        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        self.isGeneratingDeviceOrientationNotifications = false
    }

    func applyStartOptions(from call: CAPPluginCall) -> CameraStartOptions {
        self.cameraPosition = call.getString("position") ?? "rear"
        applyStartFrameOptions(from: call)

        self.rotateWhenOrientationChanged = call.getBool("rotateWhenOrientationChanged") ?? true
        self.toBack = call.getBool("toBack") ?? true
        self.storeToFile = call.getBool("storeToFile") ?? false
        self.disableAudio = call.getBool("disableAudio") ?? true
        self.aspectRatio = call.getString("aspectRatio") ?? "4:3"
        self.aspectMode = call.getString("aspectMode") ?? "contain"
        self.gridMode = call.getString("gridMode") ?? "none"
        self.positioning = call.getString("positioning") ?? "top"
        self.disableFocusIndicator = call.getBool("disableFocusIndicator") ?? false
        self.pendingStartBarcodeScannerOptions = self.barcodeScannerStartOptions(from: call)

        return CameraStartOptions(
            deviceId: call.getString("deviceId"),
            cameraMode: call.getBool("cameraMode") ?? false,
            videoQuality: call.getString("videoQuality") ?? "high",
            initialZoomLevel: call.getFloat("initialZoomLevel")
        )
    }

    func applyStartFrameOptions(from call: CAPPluginCall) {
        if let width = call.getInt("width"), width > 0 {
            self.width = CGFloat(width)
        } else {
            self.width = UIScreen.main.bounds.size.width
        }

        if let height = call.getInt("height"), height > 0 {
            self.height = CGFloat(height)
        } else {
            self.height = UIScreen.main.bounds.size.height
        }

        if let xPosition = call.getInt("x") {
            self.posX = CGFloat(xPosition)
        } else {
            self.posX = -1
        }

        if let yPosition = call.getInt("y") {
            self.posY = CGFloat(yPosition)
        } else {
            self.posY = -1
        }
        if let paddingBottomValue = call.getInt("paddingBottom") {
            self.paddingBottom = CGFloat(paddingBottomValue)
        }
    }

    func validateStartSizing(_ call: CAPPluginCall) -> Bool {
        let hasAspectRatio = call.getString("aspectRatio") != nil
        let hasWidth = call.getInt("width") != nil
        let hasHeight = call.getInt("height") != nil

        guard hasAspectRatio && (hasWidth || hasHeight) else {
            return true
        }

        self.isInitializing = false
        self.pendingStartBarcodeScannerOptions = nil
        call.reject("Cannot set both aspectRatio and size (width/height). Use setPreviewSize after start.")
        return false
    }

    func beginCameraStart(call: CAPPluginCall, options: CameraStartOptions, force: Bool) {
        if (self.cameraController.captureSession?.isRunning ?? false) && !force {
            DispatchQueue.main.async {
                self.isInitializing = false
                self.pendingStartBarcodeScannerOptions = nil
                call.reject("camera already started")
            }
            return
        }

        self.cameraController.prepare(
            cameraPosition: self.cameraPosition,
            deviceId: options.deviceId,
            disableAudio: self.disableAudio,
            cameraMode: options.cameraMode,
            aspectRatio: self.aspectRatio,
            aspectMode: self.aspectMode,
            initialZoomLevel: options.initialZoomLevel,
            disableFocusIndicator: self.disableFocusIndicator,
            videoQuality: options.videoQuality
        ) { error in
            self.handleCameraPrepared(call: call, error: error)
        }
    }

    func handleCameraPrepared(call: CAPPluginCall, error: Error?) {
        if let error = error {
            print(error)
            DispatchQueue.main.async {
                self.isInitializing = false
                self.pendingStartBarcodeScannerOptions = nil
                call.reject(error.localizedDescription)
            }
            return
        }

        DispatchQueue.main.async {
            self.startOrientationNotificationsIfNeeded()
            self.completeStartCamera(call: call)
        }
    }

    func startOrientationNotificationsIfNeeded() {
        guard self.rotateWhenOrientationChanged == true else { return }

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        self.isGeneratingDeviceOrientationNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleOrientationChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }

    func requestCameraAuthorization(beginStart: @escaping () -> Void,
                                    handleDenied: @escaping (AVAuthorizationStatus) -> Void) {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            beginStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    beginStart()
                } else {
                    let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    handleDenied(currentStatus)
                }
            }
        case .denied, .restricted:
            handleDenied(authorizationStatus)
        @unknown default:
            handleDenied(authorizationStatus)
        }
    }
    func completeStartCamera(call: CAPPluginCall) {
        // Create and configure the preview view first
        self.updateCameraFrame()

        // Add preview view to hierarchy first
        self.webView?.addSubview(self.previewView)
        if self.toBack == true {
            self.webView?.sendSubviewToBack(self.previewView)
        }

        // Make webview transparent
        self.makeWebViewTransparent()

        // Don't block on orientation update - it's already set during layer creation
        // Just update asynchronously if needed for future rotations
        DispatchQueue.main.async { [weak self] in
            self?.cameraController.updateVideoOrientation()
        }

        // Configure preview layer - it's already hidden from CameraController
        try? self.cameraController.displayPreview(on: self.previewView)
        // Do not attach native gestures; focus/zoom are controlled from JS for parity

        // Add grid overlay if enabled
        if self.gridMode != "none" {
            self.cameraController.addGridOverlay(to: self.previewView, gridMode: self.gridMode)
        }

        // Setup observers for device rotation and app state changes
        if self.rotateWhenOrientationChanged == true {
            NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

        self.isInitializing = false
        self.isInitialized = true

        // Set up callback to wait for first frame before resolving
        self.cameraController.firstFrameReadyCallback = { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                var returnedObject = JSObject()
                returnedObject["width"] = self.previewView.frame.width as any JSValue
                returnedObject["height"] = self.previewView.frame.height as any JSValue
                returnedObject["x"] = self.previewView.frame.origin.x as any JSValue
                returnedObject["y"] = self.previewView.frame.origin.y as any JSValue
                self.resolveStartCall(call, returnedObject: returnedObject)
            }
        }

        // If already received first frame (unlikely but possible), resolve immediately on main thread
        if self.cameraController.hasReceivedFirstFrame {
            DispatchQueue.main.async {
                var returnedObject = JSObject()
                returnedObject["width"] = self.previewView.frame.width as any JSValue
                returnedObject["height"] = self.previewView.frame.height as any JSValue
                returnedObject["x"] = self.previewView.frame.origin.x as any JSValue
                returnedObject["y"] = self.previewView.frame.origin.y as any JSValue
                self.resolveStartCall(call, returnedObject: returnedObject)
            }
        }
    }
    func barcodeScannerStartOptions(from call: CAPPluginCall) -> (formats: [String], detectionInterval: Int)? {
        if call.getBool("barcodeScanner") == true {
            return (formats: [], detectionInterval: 500)
        }

        guard let options = call.getObject("barcodeScanner") else {
            return nil
        }

        let formats = options["formats"] as? [String] ?? []
        let detectionInterval = (options["detectionInterval"] as? Int) ?? (options["detectionInterval"] as? NSNumber)?.intValue ?? 500
        return (formats: formats, detectionInterval: detectionInterval)
    }
    func resolveStartCall(_ call: CAPPluginCall, returnedObject: JSObject) {
        guard !hasResolvedStartCall else { return }
        hasResolvedStartCall = true
        cameraController.firstFrameReadyCallback = nil

        if let options = pendingStartBarcodeScannerOptions {
            do {
                try self.cameraController.startBarcodeScanner(formats: options.formats, detectionIntervalMs: options.detectionInterval) { [weak self] barcodes in
                    self?.notifyListeners("barcodeScanned", data: ["barcodes": barcodes])
                }
            } catch {
                self.pendingStartBarcodeScannerOptions = nil
                call.reject("Failed to start barcode scanner: \(error.localizedDescription)")
                return
            }
            self.pendingStartBarcodeScannerOptions = nil
        }

        call.resolve(returnedObject)
    }

}
