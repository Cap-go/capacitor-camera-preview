import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func startBarcodeScanner(formats: [String], detectionIntervalMs: Int, callback: @escaping ([[String: Any]]) -> Void) throws {
        guard let captureSession = captureSession,
              captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }

        stopBarcodeScanner()

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            throw CameraControllerError.invalidOperation
        }

        self.barcodeScannerCallback = callback
        self.barcodeDetectionInterval = TimeInterval(max(100, detectionIntervalMs)) / 1000.0
        self.lastBarcodeDetectionAt = 0

        captureSession.beginConfiguration()
        captureSession.addOutput(output)
        captureSession.commitConfiguration()

        let requestedTypes = metadataObjectTypes(for: formats)
        let availableTypes = output.availableMetadataObjectTypes
        let enabledTypes = requestedTypes.isEmpty ? availableTypes : requestedTypes.filter { availableTypes.contains($0) }

        guard !enabledTypes.isEmpty else {
            captureSession.beginConfiguration()
            captureSession.removeOutput(output)
            captureSession.commitConfiguration()
            self.barcodeScannerCallback = nil
            throw CameraControllerError.invalidOperation
        }

        output.metadataObjectTypes = enabledTypes
        output.setMetadataObjectsDelegate(self, queue: barcodeMetadataQueue)
        self.metadataOutput = output
    }

    func stopBarcodeScanner() {
        metadataOutput?.setMetadataObjectsDelegate(nil, queue: nil)
        if let output = metadataOutput,
           let captureSession = captureSession,
           captureSession.outputs.contains(output) {
            captureSession.beginConfiguration()
            captureSession.removeOutput(output)
            captureSession.commitConfiguration()
        }
        metadataOutput = nil
        barcodeScannerCallback = nil
        lastBarcodeDetectionAt = 0
    }
    func metadataObjectTypes(for formats: [String]) -> [AVMetadataObject.ObjectType] {
        guard !formats.isEmpty else { return [] }

        var result: [AVMetadataObject.ObjectType] = []
        for format in formats {
            let mappedTypes = metadataObjectTypes(for: format)
            for type in mappedTypes where !result.contains(type) {
                result.append(type)
            }
        }
        return result
    }
    func metadataObjectTypes(for format: String) -> [AVMetadataObject.ObjectType] {
        switch format {
        case "aztec":
            return [.aztec]
        case "code_39":
            return [.code39, .code39Mod43]
        case "code_93":
            return [.code93]
        case "code_128":
            return [.code128]
        case "data_matrix":
            return [.dataMatrix]
        case "ean_8":
            return [.ean8]
        case "ean_13", "upc_a":
            return [.ean13]
        case "itf":
            return [.interleaved2of5, .itf14]
        case "pdf417":
            return [.pdf417]
        case "qr_code":
            return [.qr]
        case "upc_e":
            return [.upce]
        case "codabar":
            if #available(iOS 15.4, *) {
                return [.codabar]
            }
            return []
        default:
            return []
        }
    }
    func barcodeFormat(from type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .aztec:
            return "aztec"
        case .code39, .code39Mod43:
            return "code_39"
        case .code93:
            return "code_93"
        case .code128:
            return "code_128"
        case .dataMatrix:
            return "data_matrix"
        case .ean8:
            return "ean_8"
        case .ean13:
            return "ean_13"
        case .interleaved2of5, .itf14:
            return "itf"
        case .pdf417:
            return "pdf417"
        case .qr:
            return "qr_code"
        case .upce:
            return "upc_e"
        default:
            if #available(iOS 15.4, *), type == .codabar {
                return "codabar"
            }
            return "unknown"
        }
    }

}
