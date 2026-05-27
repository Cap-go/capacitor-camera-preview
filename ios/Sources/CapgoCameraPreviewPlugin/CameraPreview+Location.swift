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

        DispatchQueue.main.async {
            self.handleLocationAuthorizationChange(status)
        }
    }

    func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard let callID = self.permissionCallID, self.waitingForLocation else {
            print("[CameraPreview] No pending capture call")
            return
        }

        print("[CameraPreview] Found pending capture call ID: \(callID)")
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
        @unknown default:
            print("[CameraPreview] Unknown status, rejecting capture")
            call.reject("Unknown location permission status")
            self.bridge?.releaseCall(call)
            self.permissionCallID = nil
            self.waitingForLocation = false
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[CameraPreview] locationManager didFailWithError: \(error.localizedDescription)")
        DispatchQueue.main.async {
            let completion = self.locationCompletion
            self.locationCompletion = nil
            self.locationManager?.stopUpdatingLocation()
            self.locationManager?.stopUpdatingHeading()
            completion?(nil)
        }
    }
    func getCurrentLocation(completion: @escaping (CLLocation?) -> Void) {
        let startLocationUpdates = {
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

        if Thread.isMainThread {
            startLocationUpdates()
        } else {
            DispatchQueue.main.async(execute: startLocationUpdates)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("[CameraPreview] locationManager didUpdateLocations called, locations count: \(locations.count)")
        let latestLocation = locations.last
        DispatchQueue.main.async {
            self.currentLocation = latestLocation
            if let completion = self.locationCompletion {
                print("[CameraPreview] Calling location completion with location: \(self.currentLocation?.description ?? "nil")")
                self.locationManager?.stopUpdatingLocation()
                completion(self.currentLocation)
                self.locationCompletion = nil
            } else {
                print("[CameraPreview] No location completion handler found")
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        print("[CameraPreview] locationManager didUpdateHeading: trueHeading=\(newHeading.trueHeading), magneticHeading=\(newHeading.magneticHeading), accuracy=\(newHeading.headingAccuracy)")
        DispatchQueue.main.async {
            if newHeading.headingAccuracy >= 0 {
                self.currentHeading = newHeading
            }
        }
    }

}
