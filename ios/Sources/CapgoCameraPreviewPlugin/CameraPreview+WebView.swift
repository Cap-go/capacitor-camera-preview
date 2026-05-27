import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    func parseAspectRatio(_ ratio: String, isPortrait: Bool) -> CGFloat {
        let parts = ratio.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return 1.0 }

        // For camera (portrait), we want portrait orientation: 4:3 becomes 3:4, 16:9 becomes 9:16
        return isPortrait ?
            CGFloat(parts[1] / parts[0]) :
            CGFloat(parts[0] / parts[1])
    }

    /// Calculates dimensions based on aspect ratio and available space
    func calculateDimensionsForAspectRatio(_ aspectRatio: String, availableWidth: CGFloat, availableHeight: CGFloat, isPortrait: Bool) -> (width: CGFloat, height: CGFloat) {
        let ratio = parseAspectRatio(aspectRatio, isPortrait: isPortrait)

        // Calculate maximum size that fits the aspect ratio in available space
        let maxWidthByHeight = availableHeight * ratio
        let maxHeightByWidth = availableWidth / ratio

        if maxWidthByHeight <= availableWidth {
            // Height is the limiting factor
            return (width: maxWidthByHeight, height: availableHeight)
        } else {
            // Width is the limiting factor
            return (width: availableWidth, height: maxHeightByWidth)
        }
    }

    // MARK: - Transparency Methods
    func makeWebViewTransparent() {
        guard let webView = self.webView else { return }

        // IMPORTANT: Save colors synchronously FIRST to prevent race condition
        // If we don't have saved colors yet, save them now (before going async)
        if self.originalWebViewBackgroundColor == nil {
            self.originalWebViewBackgroundColor = webView.backgroundColor
            self.originalWebViewSubviewColors.removeAll()

            // Define a recursive function to traverse and save colors
            func saveSubviewColors(_ view: UIView) {
                // Save the original background color before changing it
                if let bgColor = view.backgroundColor, bgColor != .clear {
                    self.originalWebViewSubviewColors[view] = bgColor
                }

                // Recurse for all subviews
                for subview in view.subviews {
                    saveSubviewColors(subview)
                }
            }

            // Save all subview colors synchronously
            saveSubviewColors(webView)
        }

        // Now make the changes asynchronously on main thread
        DispatchQueue.main.async {
            _ = CFAbsoluteTimeGetCurrent()

            // Define a recursive function to traverse the view hierarchy
            func makeSubviewsTransparent(_ view: UIView) {
                // Set the background color to clear
                view.backgroundColor = .clear

                // Recurse for all subviews
                for subview in view.subviews {
                    makeSubviewsTransparent(subview)
                }
            }

            // Set the main webView to be transparent
            webView.isOpaque = false
            webView.backgroundColor = .clear
            // Recursively make all subviews transparent
            makeSubviewsTransparent(webView)

            // Also ensure the webview's container is transparent
            webView.superview?.backgroundColor = .clear

            // Force a layout pass to apply changes
            webView.setNeedsLayout()
            webView.layoutIfNeeded()
        }
    }
    func restoreWebViewBackground(_ webView: UIView) {
        // Restore the saved background colors
        func restoreSubviewsBackground(_ view: UIView) {
            // Restore the saved background color for this view
            if let savedColor = self.originalWebViewSubviewColors[view] {
                view.backgroundColor = savedColor
            } else {
                // Fallback: If no saved color, intelligently restore based on view type
                let className = String(describing: type(of: view))
                if className.contains("WKScrollView") || className.contains("WKContentView") {
                    // Only restore if it's currently clear (meaning we likely made it transparent)
                    if view.backgroundColor == .clear || view.backgroundColor == nil {
                        view.backgroundColor = .white
                    }
                }
            }

            // Recurse for all subviews
            for subview in view.subviews {
                restoreSubviewsBackground(subview)
            }
        }

        // Restore the main webview background color
        if let originalColor = self.originalWebViewBackgroundColor {
            webView.backgroundColor = originalColor
        } else {
            // Fallback: If no saved color and webview is clear, restore to white
            if webView.backgroundColor == .clear || webView.backgroundColor == nil {
                webView.backgroundColor = .white
            }
        }

        // Restore all subviews
        restoreSubviewsBackground(webView)

        // Clear the saved colors dictionary
        self.originalWebViewSubviewColors.removeAll()
        self.originalWebViewBackgroundColor = nil

        // Force a layout pass to apply changes
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
    }
    func presentCameraPermissionAlert(title: String,
                                      message: String,
                                      openSettingsText: String,
                                      cancelText: String,
                                      completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let viewController = self.bridge?.viewController else {
                completion?()
                return
            }

            if self.isPresentingPermissionAlert {
                completion?()
                return
            }

            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)

            let cancelAction = UIAlertAction(title: cancelText, style: .cancel) { _ in
                self.isPresentingPermissionAlert = false
            }
            alert.addAction(cancelAction)

            let openSettingsAction = UIAlertAction(title: openSettingsText, style: .default) { _ in
                self.isPresentingPermissionAlert = false
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
            alert.addAction(openSettingsAction)

            self.isPresentingPermissionAlert = true
            viewController.present(alert, animated: true) {
                completion?()
            }
        }
    }
    func mapAuthorizationStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "granted"
        case .denied, .restricted:
            return "denied"
        case .notDetermined:
            fallthrough
        @unknown default:
            return "prompt"
        }
    }
    func mapAudioPermission(_ permission: AVAudioSession.RecordPermission) -> String {
        switch permission {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .undetermined:
            fallthrough
        @unknown default:
            return "prompt"
        }
    }

}
