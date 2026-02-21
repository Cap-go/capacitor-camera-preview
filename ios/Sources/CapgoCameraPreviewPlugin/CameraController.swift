import AVFoundation
import UIKit
import CoreLocation
import UniformTypeIdentifiers
import CoreMotion
import Vision // المكتبة الأساسية للذكاء الاصطناعي

class CameraController: NSObject {
    // تحديد اتجاه الفيديو بناءً على اتجاه الشاشة
    private func getVideoOrientation() -> AVCaptureVideoOrientation {
        var orientation: AVCaptureVideoOrientation = .portrait
        if Thread.isMainThread {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch windowScene.interfaceOrientation {
                case .portrait: orientation = .portrait
                case .landscapeLeft: orientation = .landscapeLeft
                case .landscapeRight: orientation = .landscapeRight
                case .portraitUpsideDown: orientation = .portraitUpsideDown
                default: orientation = .portrait
                }
            }
        }
        return orientation
    }

    var captureSession: AVCaptureSession?
    var dataOutput: AVCaptureVideoDataOutput?
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var hasReceivedFirstFrame = false
    var firstFrameReadyCallback: (() -> Void)?
    private var outputsPrepared: Bool = false
    var requestedAspectRatio: String?
    var requestedAspectMode: String = "contain"
    var videoQuality: String = "high"

    // --- الضربة القاضية: دالة اكتشاف الوجوه وإرسالها للـ WebView ---
    func detectFaces(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { (request, error) in
            guard let results = request.results as? [VNFaceObservation] else { return }
            
            // تحويل نتائج الوجوه لتنسيق يفهمه الـ JavaScript
            let faces = results.map { face in
                return [
                    "bounds": [
                        "x": face.boundingBox.origin.x,
                        "y": face.boundingBox.origin.y,
                        "width": face.boundingBox.size.width,
                        "height": face.boundingBox.size.height
                    ],
                    "confidence": face.confidence,
                    "landmarks": true // إشارة لوجود معالم الوجه
                ]
            }
            
            // إرسال البيانات فوراً عبر NotificationCenter
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("onFaceDetected"), 
                    object: nil, 
                    userInfo: ["faces": faces]
                )
            }
        }
        
        // تشغيل الطلب باستخدام معالج الصور
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
}

// تنفيذ الـ Delegate لاستلام الفريمات الحية من الكاميرا
extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // تشغيل الذكاء الاصطناعي على كل فريم (Real-time)
        detectFaces(in: pixelBuffer)
        
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
                guard let captureSession = self.captureSession else { return }
                
                captureSession.beginConfiguration()
                
                // إعداد جودة الفيديو
                self.videoQuality = videoQuality
                if captureSession.canSetSessionPreset(.high) {
                    captureSession.sessionPreset = .high
                }
                
                // إعداد المدخلات (كاميرا أمامية أو خلفية)
                try self.configureDeviceInputs(cameraPosition: cameraPosition)
                
                // إعداد المخرجات (Data Output لاكتشاف الوجوه)
                self.prepareOutputs()
                
                if let dataOutput = self.dataOutput, captureSession.canAddOutput(dataOutput) {
                    captureSession.addOutput(dataOutput)
                    dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
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
            self.dataOutput = AVCaptureVideoDataOutput()
            // تنسيق BGRA هو الأسرع لعمليات الـ Vision AI
            self.dataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.outputsPrepared = true
        }
    }

    private func configureDeviceInputs(cameraPosition: String) throws {
        let position: AVCaptureDevice.Position = (cameraPosition == "front") ? .front : .back
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: position)
        
        guard let device = session.devices.first else {
            throw NSError(domain: "CameraController", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera found"])
        }
        
        let input = try AVCaptureDeviceInput(device: device)
        if captureSession!.canAddInput(input) {
            captureSession!.addInput(input)
        }
    }
}
