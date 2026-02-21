import AVFoundation
import UIKit
import CoreLocation
import UniformTypeIdentifiers
import CoreMotion
import Vision // المكتبة السحرية لاكتشاف الوجوه

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
            _ = semaphore.wait(timeout: .now() + 0.1)
        }
        return orientation
    }

    private func getPhysicalOrientation() -> AVCaptureVideoOrientation {
        guard let accelerometerData = motionManager.accelerometerData else {
            return lastCaptureOrientation ?? getVideoOrientation()
        }
        let x = accelerometerData.acceleration.x
        let y = accelerometerData.acceleration.y
        if abs(x) > abs(y) {
            return x > 0 ? .landscapeLeft : .landscapeRight
        } else {
            return y > 0 ? .portraitUpsideDown : .portrait
        }
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
    var firstFrameReadyCallback: (() -> Void)?
    var hasReceivedFirstFrame = false
    var audioDevice: AVCaptureDevice?
    var audioInput: AVCaptureDeviceInput?
    var zoomFactor: CGFloat = 1.0
    private let motionManager = CMMotionManager()
    private var lastCaptureOrientation: AVCaptureVideoOrientation?
    var videoFileURL: URL?
    private let saneMaxZoomFactor: CGFloat = 25.5
    var videoQuality: String = "high"
    private var outputsPrepared: Bool = false
    var isCapturingPhoto: Bool = false
    var stopRequestedAfterCapture: Bool = false
    var requestedAspectRatio: String?
    var requestedAspectMode: String = "contain"

    // دالة اكتشاف الوجوه (The $1000 Logic)
    func detectFaces(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { (request, error) in
            guard let results = request.results as? [VNFaceObservation] else { return }
            let faces = results.map { face in
                return [
                    "x": face.boundingBox.origin.x,
                    "y": face.boundingBox.origin.y,
                    "width": face.boundingBox.size.width,
                    "height": face.boundingBox.size.height,
                    "confidence": face.confidence
                ]
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("onFaceDetected"), object: nil, userInfo: ["faces": faces])
            }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        detectFaces(in: pixelBuffer) // تشغيل الذكاء الاصطناعي على كل فريم
        
        if !hasReceivedFirstFrame {
            hasReceivedFirstFrame = true
            DispatchQueue.main.async { self.firstFrameReadyCallback?() }
        }
    }
}

extension CameraController {
    func prepare(cameraPosition: String, deviceId: String? = nil, disableAudio: Bool, cameraMode: Bool, aspectRatio: String? = nil, aspectMode: String = "contain", initialZoomLevel: Float?, disableFocusIndicator: Bool = false, videoQuality: String = "high", completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                if self.captureSession == nil { self.captureSession = AVCaptureSession() }
                guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
                
                self.videoQuality = videoQuality
                self.prepareOutputs()
                
                captureSession.beginConfiguration()
                self.requestedAspectRatio = aspectRatio
                self.requestedAspectMode = aspectMode
                
                try self.configureDeviceInputs(cameraPosition: cameraPosition, deviceId: deviceId, disableAudio: disableAudio)
                
                let videoOrientation = self.getVideoOrientation()
                
                if let dataOutput = self.dataOutput, captureSession.canAddOutput(dataOutput) {
                    captureSession.addOutput(dataOutput)
                    dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
                    dataOutput.connections.forEach { $0.videoOrientation = videoOrientation }
                }
                
                if let photoOutput = self.photoOutput, captureSession.canAddOutput(photoOutput) {
                    captureSession.addOutput(photoOutput)
                }
                
                captureSession.commitConfiguration()
                captureSession.startRunning()
                
                DispatchQueue.main.async { completionHandler(nil) }
            } catch {
                DispatchQueue.main.async { completionHandler(error) }
            }
        }
    }
    
    private func prepareOutputs() {
        if !outputsPrepared {
            self.photoOutput = AVCapturePhotoOutput()
            self.dataOutput = AVCaptureVideoDataOutput()
            self.dataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.outputsPrepared = true
        }
    }

    private func configureDeviceInputs(cameraPosition: String, deviceId: String?, disableAudio: Bool) throws {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        let cameras = session.devices
        let finalDevice = (cameraPosition == "front") ? cameras.first(where: { $0.position == .front }) : cameras.first(where: { $0.position == .back })
        guard let device = finalDevice else { throw CameraControllerError.noCamerasAvailable }
        let input = try AVCaptureDeviceInput(device: device)
        if captureSession!.canAddInput(input) { captureSession!.addInput(input) }
    }
}
