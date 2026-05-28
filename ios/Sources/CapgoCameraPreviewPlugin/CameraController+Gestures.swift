import AVFoundation
import Foundation
import UIKit

extension CameraController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc
    func handleTap(_ tap: UITapGestureRecognizer) {
        guard let device = self.currentCameraPosition == .rear ? rearCamera : frontCamera else { return }

        let point = tap.location(in: tap.view)
        let devicePoint = self.previewLayer?.captureDevicePointConverted(fromLayerPoint: point)
        let focusPoint = devicePoint ?? CGPoint(x: 0, y: 0)

        // Show focus indicator at the tap point if not disabled
        if !self.disableFocusIndicator, let view = tap.view {
            showFocusIndicator(at: point, in: view)
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let focusMode = AVCaptureDevice.FocusMode.autoFocus
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                device.focusPointOfInterest = focusPoint
                device.focusMode = focusMode
            }
            // Skip exposure point if locked
            if device.exposureMode != .locked {
                let exposureMode = AVCaptureDevice.ExposureMode.autoExpose
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = focusPoint
                    device.exposureMode = exposureMode
                    device.setExposureTargetBias(0.0) { _ in }
                }
            }

            // Turn on subject area monitor for switch to continuous focus if needed
            device.isSubjectAreaChangeMonitoringEnabled = true

        } catch {
            debugPrint(error)
        }
    }
    func showFocusIndicator(at point: CGPoint, in view: UIView) {
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
    func handlePinch(_ pinch: UIPinchGestureRecognizer) {
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
