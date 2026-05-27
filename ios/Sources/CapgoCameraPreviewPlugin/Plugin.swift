import Foundation
import AVFoundation
import Photos
import Capacitor
import CoreImage
import CoreLocation
import MobileCoreServices
import UIKit

extension UIWindow {
    static var isLandscape: Bool {
        // iOS 14+ only: derive from the active window scene's interface orientation
        let scene = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        return scene?.interfaceOrientation.isLandscape ?? false
    }
    static var isPortrait: Bool {
        // iOS 14+ only: derive from the active window scene's interface orientation
        let scene = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        return scene?.interfaceOrientation.isPortrait ?? false
    }
}

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(CameraPreview)
public class CameraPreview: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate {
    let pluginVersion: String = "8.3.8"
    public let identifier = "CameraPreviewPlugin"
    public let jsName = "CameraPreview"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "flip", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "capture", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "captureSample", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startBarcodeScanner", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopBarcodeScanner", returnType: CAPPluginReturnPromise),
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
        CAPPluginMethod(name: "getZoomButtonValues", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setZoom", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getFlashMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setDeviceId", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDeviceId", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setAspectRatio", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAspectRatio", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setGridMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getGridMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPreviewSize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setPreviewSize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setFocus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getOrientation", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSafeAreaInsets", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        // Exposure control methods
        CAPPluginMethod(name: "getExposureModes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getExposureMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setExposureMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getExposureCompensationRange", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getExposureCompensation", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setExposureCompensation", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]
    // Camera state tracking
    var isInitializing: Bool = false
    var isInitialized: Bool = false
    var backgroundSession: AVCaptureSession?
    var isGeneratingDeviceOrientationNotifications: Bool = false

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
    var disableAudio: Bool = false
    var disableFocusIndicator: Bool = false
    var locationManager: CLLocationManager?
    var currentLocation: CLLocation?
    var currentHeading: CLHeading?
    var aspectRatio: String?
    var aspectMode: String = "contain"
    var gridMode: String = "none"
    var positioning: String = "center"
    var permissionCallID: String?
    var waitingForLocation: Bool = false
    var isPresentingPermissionAlert: Bool = false
    var pendingStartBarcodeScannerOptions: (formats: [String], detectionInterval: Int)?
    var hasResolvedStartCall: Bool = false

    // Store original webview colors to restore them when stopping
    var originalWebViewBackgroundColor: UIColor?
    var originalWebViewSubviewColors: [UIView: UIColor] = [:]
    var permissionCompletion: ((Bool) -> Void)?
    var locationCompletion: ((CLLocation?) -> Void)?
    var lastOrientation: String?

}
