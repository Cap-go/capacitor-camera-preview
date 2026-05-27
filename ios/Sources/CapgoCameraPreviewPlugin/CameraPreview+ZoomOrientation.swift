import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    @objc func getZoomButtonValues(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }

        // Determine current device based on active position
        var currentDevice: AVCaptureDevice?
        switch self.cameraController.currentCameraPosition {
        case .front:
            currentDevice = self.cameraController.frontCamera
        case .rear:
            currentDevice = self.cameraController.rearCamera
        default:
            currentDevice = nil
        }

        guard let device = currentDevice else {
            call.reject("No active camera device")
            return
        }

        var hasUltraWide = false
        var hasWide = false
        var hasTele = false

        let lenses = device.isVirtualDevice ? device.constituentDevices : [device]
        for lens in lenses {
            switch lens.deviceType {
            case .builtInUltraWideCamera:
                hasUltraWide = true
            case .builtInWideAngleCamera:
                hasWide = true
            case .builtInTelephotoCamera:
                hasTele = true
            default:
                break
            }
        }

        var values: [Float] = []
        if hasUltraWide {
            values.append(0.5)
        }
        if hasWide {
            values.append(1.0)
            if self.isProModelSupportingOptical2x() {
                values.append(2.0)
            }
        }
        if hasTele {
            // Use the virtual device's switch-over zoom factors when available
            let displayMultiplier = self.cameraController.getDisplayZoomMultiplier()
            var teleStep: Float

            let switchFactors = device.virtualDeviceSwitchOverVideoZoomFactors
            if !switchFactors.isEmpty {
                // Choose the highest switch-over factor (typically the wide->tele threshold)
                let maxSwitch = switchFactors.map { $0.floatValue }.max() ?? Float(device.maxAvailableVideoZoomFactor)
                teleStep = maxSwitch * displayMultiplier
            } else {
                teleStep = Float(device.maxAvailableVideoZoomFactor) * displayMultiplier
            }
            values.append(teleStep)
        }

        // Deduplicate and sort
        let uniqueSorted = Array(Set(values)).sorted()
        call.resolve(["values": uniqueSorted])
    }
    func isProModelSupportingOptical2x() -> Bool {
        // Detects iPhone 14 Pro/Pro Max, 15 Pro/Pro Max, and 16 Pro/Pro Max
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { partialResult, element in
            guard let value = element.value as? Int8, value != 0 else { return partialResult }
            return partialResult + String(UnicodeScalar(UInt8(value)))
        }

        // Known identifiers: 14 Pro (iPhone15,2), 14 Pro Max (iPhone15,3),
        // 15 Pro (iPhone16,1), 15 Pro Max (iPhone16,2),
        // 16 Pro (iPhone17,1), 16 Pro Max (iPhone17,2),
        // 17 Pro (iPhone18,1), 17 Pro Max (iPhone18,2)
        let supportedIdentifiers: Set<String> = [
            "iPhone15,2", "iPhone15,3", // 14 Pro / 14 Pro Max
            "iPhone16,1", "iPhone16,2", // 15 Pro / 15 Pro Max
            "iPhone17,1", "iPhone17,2" // 16 Pro / 16 Pro Max
        ]
        return supportedIdentifiers.contains(identifier)
    }

    @objc func rotated() {
        guard let previewView = self.previewView else {
            return
        }

        // Handle auto-centering during rotation
        // Always use the factorized method for consistent positioning
        self.updateCameraFrame()

        // Centralize orientation update to use interface orientation consistently
        cameraController.updateVideoOrientation()

        // Update grid overlay frame if it exists - no animation
        if let gridOverlay = self.cameraController.gridOverlayView {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gridOverlay.frame = previewView.bounds
            CATransaction.commit()
        }

        // Ensure webview remains transparent after rotation
        if self.isInitialized {
            self.makeWebViewTransparent()
        }
    }

}
