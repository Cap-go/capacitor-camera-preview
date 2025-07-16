//
//  CameraController.swift
//  Plugin
//
//  Created by Ariel Hernandez Musa on 7/14/19.
//  Copyright © 2019 Max Lynch. All rights reserved.
//

import AVFoundation
import UIKit

class CameraController: NSObject {
    var captureSession: AVCaptureSession?

    var currentCameraPosition: CameraPosition?

    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?

    var dataOutput: AVCaptureVideoDataOutput?
    var photoOutput: AVCapturePhotoOutput?

    var rearCamera: AVCaptureDevice?
    var rearCameraInput: AVCaptureDeviceInput?

    var fileVideoOutput: AVCaptureMovieFileOutput?

    var previewLayer: AVCaptureVideoPreviewLayer?

    var flashMode = AVCaptureDevice.FlashMode.off
    var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?

    var sampleBufferCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?

    var highResolutionOutput: Bool = false

    var audioDevice: AVCaptureDevice?
    var audioInput: AVCaptureDeviceInput?

    var zoomFactor: CGFloat = 1.0

    var videoFileURL: URL?
    private let saneMaxZoomFactor: CGFloat = 25.5

    var isUsingMultiLensVirtualCamera: Bool {
        guard let device = (currentCameraPosition == .rear) ? rearCamera : frontCamera else { return false }
        // A rear multi-lens virtual camera will have a min zoom of 1.0 but support wider angles
        return device.position == .back && device.isVirtualDevice && device.constituentDevices.count > 1
    }
}

extension CameraController {
    func prepare(cameraPosition: String, deviceId: String? = nil, disableAudio: Bool, cameraMode: Bool, completionHandler: @escaping (Error?) -> Void) {
        func createCaptureSession() {
            self.captureSession = AVCaptureSession()
        }

        func configureCaptureDevices() throws {
            // Expanded device types to support more camera configurations
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

            // Log all found devices for debugging
            print("[CameraPreview] Found \(cameras.count) devices:")
            for camera in cameras {
                let constituentCount = camera.isVirtualDevice ? camera.constituentDevices.count : 1
                print("[CameraPreview] - \(camera.localizedName) (Position: \(camera.position.rawValue), Virtual: \(camera.isVirtualDevice), Lenses: \(constituentCount), Zoom: \(camera.minAvailableVideoZoomFactor)-\(camera.maxAvailableVideoZoomFactor))")
            }

            guard !cameras.isEmpty else {
                print("[CameraPreview] ERROR: No cameras found.")
                throw CameraControllerError.noCamerasAvailable
            }

            // --- Corrected Device Selection Logic ---
            // Find the virtual device with the most constituent cameras (this is the most capable one)
            let rearVirtualDevices = cameras.filter { $0.position == .back && $0.isVirtualDevice }
            let bestRearVirtualDevice = rearVirtualDevices.max { $0.constituentDevices.count < $1.constituentDevices.count }

            self.frontCamera = cameras.first(where: { $0.position == .front })

            if let bestCamera = bestRearVirtualDevice {
                self.rearCamera = bestCamera
                print("[CameraPreview] Selected best virtual rear camera: \(bestCamera.localizedName) with \(bestCamera.constituentDevices.count) physical cameras.")
            } else if let firstRearCamera = cameras.first(where: { $0.position == .back }) {
                // Fallback for devices without a virtual camera system
                self.rearCamera = firstRearCamera
                print("[CameraPreview] WARN: No virtual rear camera found. Selected first available: \(firstRearCamera.localizedName)")
            }
            // --- End of Correction ---

            if let rearCamera = self.rearCamera {
                do {
                    try rearCamera.lockForConfiguration()
                    if rearCamera.isFocusModeSupported(.continuousAutoFocus) {
                        rearCamera.focusMode = .continuousAutoFocus
                    }
                    rearCamera.unlockForConfiguration()
                } catch {
                    print("[CameraPreview] WARN: Could not set focus mode on rear camera. \(error)")
                }
            }

            if disableAudio == false {
                self.audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
            }
        }

        func configureDeviceInputs() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

            var selectedDevice: AVCaptureDevice?

            // If deviceId is specified, use that specific device
            if let deviceId = deviceId {
                let allDevices = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera],
                    mediaType: .video,
                    position: .unspecified
                ).devices

                selectedDevice = allDevices.first(where: { $0.uniqueID == deviceId })
                guard selectedDevice != nil else {
                    throw CameraControllerError.noCamerasAvailable
                }
            } else {
                // Use position-based selection
                if cameraPosition == "rear" {
                    selectedDevice = self.rearCamera
                } else if cameraPosition == "front" {
                    selectedDevice = self.frontCamera
                }
            }

            guard let finalDevice = selectedDevice else {
                print("[CameraPreview] ERROR: No camera device selected for position: \(cameraPosition)")
                throw CameraControllerError.noCamerasAvailable
            }

            print("[CameraPreview] Configuring device: \(finalDevice.localizedName)")
            let deviceInput = try AVCaptureDeviceInput(device: finalDevice)

            if captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)

                if finalDevice.position == .front {
                    self.frontCameraInput = deviceInput
                    self.frontCamera = finalDevice
                    self.currentCameraPosition = .front
                } else {
                    self.rearCameraInput = deviceInput
                    self.rearCamera = finalDevice
                    self.currentCameraPosition = .rear

                    // --- Corrected Initial Zoom Logic ---
                    try finalDevice.lockForConfiguration()
                    if finalDevice.isFocusModeSupported(.continuousAutoFocus) {
                        finalDevice.focusMode = .continuousAutoFocus
                    }

                    // On a multi-camera system, a zoom factor of 2.0 often corresponds to the standard "1x" wide-angle lens.
                    // We set this as the default to provide a familiar starting point for users.
                    let defaultWideAngleZoom: CGFloat = 2.0
                    if finalDevice.isVirtualDevice && finalDevice.constituentDevices.count > 1 && finalDevice.videoZoomFactor != defaultWideAngleZoom {
                        // Check if 2.0 is a valid zoom factor before setting it.
                        if defaultWideAngleZoom >= finalDevice.minAvailableVideoZoomFactor && defaultWideAngleZoom <= finalDevice.maxAvailableVideoZoomFactor {
                             print("[CameraPreview] Multi-camera system detected. Setting initial zoom to \(defaultWideAngleZoom) (standard wide-angle).")
                             finalDevice.videoZoomFactor = defaultWideAngleZoom
                        }
                    }
                    finalDevice.unlockForConfiguration()
                    // --- End of Correction ---
                }
            } else {
                print("[CameraPreview] ERROR: Cannot add device input to session.")
                throw CameraControllerError.inputsAreInvalid
            }

            // Add audio input
            if disableAudio == false {
                if let audioDevice = self.audioDevice {
                    self.audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if captureSession.canAddInput(self.audioInput!) {
                        captureSession.addInput(self.audioInput!)
                    } else {
                        throw CameraControllerError.inputsAreInvalid
                    }
                }
            }
        }

        func configurePhotoOutput(cameraMode: Bool) throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

            //  TODO: check if that really useful
            if !cameraMode && self.highResolutionOutput && captureSession.canSetSessionPreset(.photo) {
                captureSession.sessionPreset = .photo
            } else if cameraMode && self.highResolutionOutput && captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
            }

            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])], completionHandler: nil)
            self.photoOutput?.isHighResolutionCaptureEnabled = self.highResolutionOutput
            if captureSession.canAddOutput(self.photoOutput!) { captureSession.addOutput(self.photoOutput!) }

            let fileVideoOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(fileVideoOutput) {
                captureSession.addOutput(fileVideoOutput)
                self.fileVideoOutput = fileVideoOutput
            }
            captureSession.startRunning()
        }

        func configureDataOutput() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

            self.dataOutput = AVCaptureVideoDataOutput()
            self.dataOutput?.videoSettings = [
                (kCVPixelBufferPixelFormatTypeKey as String): NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)
            ]
            self.dataOutput?.alwaysDiscardsLateVideoFrames = true
            if captureSession.canAddOutput(self.dataOutput!) {
                captureSession.addOutput(self.dataOutput!)
            }

            captureSession.commitConfiguration()

            let queue = DispatchQueue(label: "DataOutput", attributes: [])
            self.dataOutput?.setSampleBufferDelegate(self, queue: queue)
        }

        DispatchQueue(label: "prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configurePhotoOutput(cameraMode: cameraMode)
                try configureDataOutput()
                // try configureVideoOutput()
            } catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }

                return
            }

            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }

    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }

        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill

        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame

        updateVideoOrientation()
    }

    func setupGestures(target: UIView, enableZoom: Bool) {
        setupTapGesture(target: target, selector: #selector(handleTap(_:)), delegate: self)
        if enableZoom {
            setupPinchGesture(target: target, selector: #selector(handlePinch(_:)), delegate: self)
        }
    }

    func setupTapGesture(target: UIView, selector: Selector, delegate: UIGestureRecognizerDelegate?) {
        let tapGesture = UITapGestureRecognizer(target: self, action: selector)
        tapGesture.delegate = delegate
        target.addGestureRecognizer(tapGesture)
    }

    func setupPinchGesture(target: UIView, selector: Selector, delegate: UIGestureRecognizerDelegate?) {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: selector)
        pinchGesture.delegate = delegate
        target.addGestureRecognizer(pinchGesture)
    }

    func updateVideoOrientation() {
        if Thread.isMainThread {
            updateVideoOrientationOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateVideoOrientationOnMainThread()
            }
        }
    }

    private func updateVideoOrientationOnMainThread() {
        let videoOrientation: AVCaptureVideoOrientation

        // Use window scene interface orientation
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            switch windowScene.interfaceOrientation {
            case .portrait:
                videoOrientation = .portrait
            case .landscapeLeft:
                videoOrientation = .landscapeLeft
            case .landscapeRight:
                videoOrientation = .landscapeRight
            case .portraitUpsideDown:
                videoOrientation = .portraitUpsideDown
            case .unknown:
                fallthrough
            @unknown default:
                videoOrientation = .portrait
            }
        } else {
            videoOrientation = .portrait
        }

        previewLayer?.connection?.videoOrientation = videoOrientation
        dataOutput?.connections.forEach { $0.videoOrientation = videoOrientation }
        photoOutput?.connections.forEach { $0.videoOrientation = videoOrientation }
    }

    func switchCameras() throws {
        guard let currentCameraPosition = currentCameraPosition,
              let captureSession = self.captureSession else {
            throw CameraControllerError.captureSessionIsMissing
        }

        // Ensure we have the necessary cameras
        guard (currentCameraPosition == .front && rearCamera != nil) ||
              (currentCameraPosition == .rear && frontCamera != nil) else {
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
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.captureSession?.startRunning()
                }
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

        // Configure new camera
        switch currentCameraPosition {
        case .front:
            guard let rearCamera = rearCamera else {
                throw CameraControllerError.invalidOperation
            }

            // Configure rear camera
            try rearCamera.lockForConfiguration()
            if rearCamera.isFocusModeSupported(.continuousAutoFocus) {
                rearCamera.focusMode = .continuousAutoFocus
            }
            rearCamera.unlockForConfiguration()

            if let newInput = try? AVCaptureDeviceInput(device: rearCamera),
                captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                rearCameraInput = newInput
                self.currentCameraPosition = .rear
            } else {
                throw CameraControllerError.invalidOperation
            }
        case .rear:
            guard let frontCamera = frontCamera else {
                throw CameraControllerError.invalidOperation
            }

            // Configure front camera
            try frontCamera.lockForConfiguration()
            if frontCamera.isFocusModeSupported(.continuousAutoFocus) {
                frontCamera.focusMode = .continuousAutoFocus
            }
            frontCamera.unlockForConfiguration()

            if let newInput = try? AVCaptureDeviceInput(device: frontCamera),
                captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                frontCameraInput = newInput
                self.currentCameraPosition = .front
            } else {
                throw CameraControllerError.invalidOperation
            }
        }

        // Re-add audio input if it existed
        if let audioInput = audioInput, captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Update video orientation
        DispatchQueue.main.async { [weak self] in
            self?.updateVideoOrientation()
        }
    }

    func captureImage(completion: @escaping (UIImage?, Error?) -> Void) {
        guard let captureSession = captureSession, captureSession.isRunning else { completion(nil, CameraControllerError.captureSessionIsMissing); return }
        let settings = AVCapturePhotoSettings()

        settings.flashMode = self.flashMode
        settings.isHighResolutionPhotoEnabled = self.highResolutionOutput

        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
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

    func setZoom(level: CGFloat, ramp: Bool) throws {
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
                device.ramp(toVideoZoomFactor: zoomLevel, withRate: 1.0)
            } else {
                device.videoZoomFactor = zoomLevel
            }

            device.unlockForConfiguration()

            // Update our internal zoom factor tracking
            self.zoomFactor = zoomLevel
        } catch {
            throw CameraControllerError.invalidOperation
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
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.captureSession?.startRunning()
                }
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
        DispatchQueue.main.async { [weak self] in
            self?.updateVideoOrientation()
        }
    }



    func cleanup() {
        if let captureSession = self.captureSession {
            captureSession.stopRunning()
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            captureSession.outputs.forEach { captureSession.removeOutput($0) }
        }

        self.previewLayer?.removeFromSuperlayer()
        self.previewLayer = nil

        self.frontCameraInput = nil
        self.rearCameraInput = nil
        self.audioInput = nil

        self.frontCamera = nil
        self.rearCamera = nil
        self.audioDevice = nil

        self.dataOutput = nil
        self.photoOutput = nil
        self.fileVideoOutput = nil

        self.captureSession = nil
        self.currentCameraPosition = nil
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

        // cpcp_video_A6C01203 - portrait
        //
        if let connection = fileVideoOutput.connection(with: .video) {
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
            }
        } catch {
            debugPrint(error)
        }
    }

    @objc
    private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        guard let device = self.currentCameraPosition == .rear ? rearCamera : frontCamera else { return }

        let effectiveMaxZoom = min(device.maxAvailableVideoZoomFactor, self.saneMaxZoomFactor)
        func minMaxZoom(_ factor: CGFloat) -> CGFloat { return max(device.minAvailableVideoZoomFactor, min(factor, effectiveMaxZoom)) }

        func update(scale factor: CGFloat) {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                device.videoZoomFactor = factor
            } catch {
                debugPrint(error)
            }
        }

        switch pinch.state {
        case .began: fallthrough
        case .changed:
            let newScaleFactor = minMaxZoom(pinch.scale * zoomFactor)
            update(scale: newScaleFactor)
        case .ended:
            zoomFactor = device.videoZoomFactor
        default: break
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?, previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                            resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Swift.Error?) {
        if let error = error {
            self.photoCaptureCompletionBlock?(nil, error)
        } else if let buffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer, previewPhotoSampleBuffer: nil),
                  let image = UIImage(data: data) {
            self.photoCaptureCompletionBlock?(image.fixedOrientation(), nil)
        } else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
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
        }

        // Flip image one more time if needed to, this is to prevent flipped image
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform.translatedBy(x: size.width, y: 0)
            transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform.translatedBy(x: size.height, y: 0)
            transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        }

        ctx.concatenate(transform)

        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            ctx.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            ctx.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
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
