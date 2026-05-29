import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    @objc func getExposureModes(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }
        do {
            let modes = try self.cameraController.getExposureModes()
            call.resolve(["modes": modes])
        } catch {
            call.reject("Failed to get exposure modes: \(error.localizedDescription)")
        }
    }

    @objc func getExposureMode(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }
        do {
            let mode = try self.cameraController.getExposureMode()
            call.resolve(["mode": mode])
        } catch {
            call.reject("Failed to get exposure mode: \(error.localizedDescription)")
        }
    }

    @objc func setExposureMode(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }
        guard let mode = call.getString("mode") else {
            call.reject("mode parameter is required")
            return
        }
        // Validate against allowed exposure modes before delegating
        let normalized = mode.uppercased()
        let allowedModes: Set<String> = ["AUTO", "LOCK", "CONTINUOUS", "CUSTOM"]
        guard allowedModes.contains(normalized) else {
            let allowedList = Array(allowedModes).sorted().joined(separator: ", ")
            call.reject("Invalid exposure mode: \(mode). Allowed values: \(allowedList)")
            return
        }
        do {
            try self.cameraController.setExposureMode(mode: normalized)
            call.resolve()
        } catch {
            call.reject("Failed to set exposure mode: \(error.localizedDescription)")
        }
    }

    @objc func getExposureCompensationRange(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }
        do {
            let range = try self.cameraController.getExposureCompensationRange()
            call.resolve(["min": range.min, "max": range.max, "step": range.step])
        } catch {
            call.reject("Failed to get exposure compensation range: \(error.localizedDescription)")
        }
    }

    @objc func getExposureCompensation(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }
        do {
            let value = try self.cameraController.getExposureCompensation()
            call.resolve(["value": value])
        } catch {
            call.reject("Failed to get exposure compensation: \(error.localizedDescription)")
        }
    }

    @objc func setExposureCompensation(_ call: CAPPluginCall) {
        guard isInitialized else {
            call.reject("Camera not initialized")
            return
        }
        guard var value = call.getFloat("value") else {
            call.reject("value parameter is required")
            return
        }
        do {
            // Snap to valid range and step
            var range = try self.cameraController.getExposureCompensationRange()
            if range.step <= 0 { range.step = 0.1 }
            let minValue = min(range.min, range.max)
            let maxValue = max(range.min, range.max)
            // Clamp to [minValue, maxValue]
            value = max(minValue, min(maxValue, value))
            // Snap to nearest step
            let steps = round((value - minValue) / range.step)
            let snapped = minValue + steps * range.step

            try self.cameraController.setExposureCompensation(snapped)
            call.resolve()
        } catch {
            call.reject("Failed to set exposure compensation: \(error.localizedDescription)")
        }
    }
    @objc func handleOrientationChange() {
        let currentOrientation = self.currentOrientationString()
        if currentOrientation == "portrait-upside-down" || currentOrientation == lastOrientation {
            return
        }
        lastOrientation = currentOrientation
        DispatchQueue.main.async {
            let result = self.rawSetAspectRatio()
            self.notifyListeners("screenResize", data: result)
            self.notifyListeners("orientationChange", data: ["orientation": self.currentOrientationString()])
        }
    }

    @objc func deleteFile(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), !path.isEmpty else {
            call.reject("path parameter is required")
            return
        }
        let url: URL?
        if path.hasPrefix("file://") {
            url = URL(string: path)
        } else {
            url = URL(fileURLWithPath: path)
        }
        guard let fileURL = url else {
            call.reject("Invalid path")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                call.resolve(["success": true])
            } else {
                call.resolve(["success": false])
            }
        } catch {
            call.reject("Failed to delete file: \(error.localizedDescription)")
        }
    }

    // MARK: - Orientation
    func currentOrientationString() -> String {
        // Prefer interface orientation for UI-consistent results
        let orientation: UIInterfaceOrientation? = {
            if Thread.isMainThread {
                return (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
            } else {
                var value: UIInterfaceOrientation?
                DispatchQueue.main.sync {
                    value = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
                }
                return value
            }
        }()
        switch orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portrait-upside-down"
        case .landscapeLeft: return "landscape-left"
        case .landscapeRight: return "landscape-right"
        default: return "unknown"
        }
    }

    @objc func getOrientation(_ call: CAPPluginCall) {
        call.resolve(["orientation": self.currentOrientationString()])
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }
}
