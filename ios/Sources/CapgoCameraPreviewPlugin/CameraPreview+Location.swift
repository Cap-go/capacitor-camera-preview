import AVFoundation
import Capacitor
import CoreImage
import CoreLocation
import Foundation
import MobileCoreServices
import Photos
import UIKit

extension CameraPreview {
    func requestLocationPermission(completion: @escaping (Bool) -> Void) {
        print("[CameraPreview] requestLocationPermission called")
        if self.locationManager == nil {
            print("[CameraPreview] Creating location manager")
            self.locationManager = CLLocationManager()
            self.locationManager?.delegate = self
        }

        let authStatus = self.locationManager?.authorizationStatus
        print("[CameraPreview] Current authorization status: \(String(describing: authStatus))")

        switch authStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("[CameraPreview] Location already authorized")
            completion(true)
        case .notDetermined:
            print("[CameraPreview] Location not determined, requesting authorization...")
            self.permissionCompletion = completion
            self.locationManager?.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("[CameraPreview] Location denied or restricted")
            completion(false)
        case .none:
            print("[CameraPreview] Location manager authorization status is nil")
            completion(false)
        @unknown default:
            print("[CameraPreview] Unknown authorization status")
            completion(false)
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("[CameraPreview] locationManagerDidChangeAuthorization called, status: \(status.rawValue), thread: \(Thread.current)")

        // Handle pending capture call if we have one
        if let callID = self.permissionCallID, self.waitingForLocation {
            print("[CameraPreview] Found pending capture call ID: \(callID)")

            let handleAuthorization = {
                print("[CameraPreview] Getting saved call on thread: \(Thread.current)")
                guard let call = self.bridge?.savedCall(withID: callID) else {
                    print("[CameraPreview] ERROR: Could not retrieve saved call")
                    self.permissionCallID = nil
                    self.waitingForLocation = false
                    return
                }
                print("[CameraPreview] Successfully retrieved saved call")

                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    print("[CameraPreview] Location authorized, getting location for capture")
                    self.getCurrentLocation { _ in
                        self.performCapture(call: call)
                        self.bridge?.releaseCall(call)
                        self.permissionCallID = nil
                        self.waitingForLocation = false
                    }
                case .denied, .restricted:
                    print("[CameraPreview] Location denied, rejecting capture")
                    call.reject("Location permission denied")
                    self.bridge?.releaseCall(call)
                    self.permissionCallID = nil
                    self.waitingForLocation = false
                case .notDetermined:
                    print("[CameraPreview] Authorization not determined yet")
                // Don't do anything, wait for user response
                @unknown default:
                    print("[CameraPreview] Unknown status, rejecting capture")
                    call.reject("Unknown location permission status")
                    self.bridge?.releaseCall(call)
                    self.permissionCallID = nil
                    self.waitingForLocation = false
                }
            }

            // Check if we're already on main thread
            if Thread.isMainThread {
                print("[CameraPreview] Already on main thread")
                handleAuthorization()
            } else {
                print("[CameraPreview] Not on main thread, dispatching")
                DispatchQueue.main.async(execute: handleAuthorization)
            }
        } else {
            print("[CameraPreview] No pending capture call")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[CameraPreview] locationManager didFailWithError: \(error.localizedDescription)")
    }
    func getCurrentLocation(completion: @escaping (CLLocation?) -> Void) {
        print("[CameraPreview] getCurrentLocation called")
        self.currentHeading = nil
        self.locationCompletion = completion
        self.locationManager?.startUpdatingLocation()
        print("[CameraPreview] Started updating location")
        if CLLocationManager.headingAvailable() {
            self.locationManager?.startUpdatingHeading()
            print("[CameraPreview] Started updating heading")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("[CameraPreview] locationManager didUpdateLocations called, locations count: \(locations.count)")
        self.currentLocation = locations.last
        if let completion = locationCompletion {
            print("[CameraPreview] Calling location completion with location: \(self.currentLocation?.description ?? "nil")")
            self.locationManager?.stopUpdatingLocation()
            completion(self.currentLocation)
            locationCompletion = nil
        } else {
            print("[CameraPreview] No location completion handler found")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        print("[CameraPreview] locationManager didUpdateHeading: trueHeading=\(newHeading.trueHeading), magneticHeading=\(newHeading.magneticHeading), accuracy=\(newHeading.headingAccuracy)")
        if newHeading.headingAccuracy >= 0 {
            self.currentHeading = newHeading
        }
    }

}
