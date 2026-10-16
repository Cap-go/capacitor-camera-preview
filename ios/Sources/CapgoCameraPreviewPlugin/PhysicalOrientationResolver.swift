import AVFoundation
import Foundation

/// Resolves device physical orientation from gravity (accelerometer) for photo and video capture.
/// When the device is near flat, x/y gravity is noisy; keep the last reliable orientation or UI fallback.
enum PhysicalOrientationResolver {
    /// |z| above this means gravity mostly points through the screen (camera toward table or ceiling).
    static let flatGravityZThreshold: Double = 0.75
    /// Below this, horizontal gravity is too weak to infer portrait vs landscape reliably.
    static let minHorizontalGravity: Double = 0.35
    /// When |x| and |y| are within this margin, do not flip between landscape and portrait.
    static let axisDecisionMargin: Double = 0.12

    struct Acceleration {
        let x: Double
        let y: Double
        let z: Double
    }

    struct Result {
        let orientation: AVCaptureVideoOrientation
        /// True when orientation came from a strong gravity signal (safe to remember for hysteresis).
        let isReliable: Bool
    }

    static func resolve(
        acceleration: Acceleration,
        lastReliableOrientation: AVCaptureVideoOrientation?,
        fallbackOrientation: AVCaptureVideoOrientation
    ) -> Result {
        let x = acceleration.x
        let y = acceleration.y
        let z = acceleration.z
        let absX = abs(x)
        let absY = abs(y)
        let absZ = abs(z)
        let horizontalMax = max(absX, absY)

        let isNearFlat = absZ >= flatGravityZThreshold || horizontalMax < minHorizontalGravity
        if isNearFlat {
            let orientation = lastReliableOrientation ?? fallbackOrientation
            return Result(orientation: orientation, isReliable: false)
        }

        let axisMargin = axisDecisionMargin
        if abs(absX - absY) < axisMargin {
            let orientation = lastReliableOrientation ?? fallbackOrientation
            return Result(orientation: orientation, isReliable: false)
        }

        let orientation: AVCaptureVideoOrientation
        if absX > absY {
            orientation = x > 0 ? .landscapeLeft : .landscapeRight
        } else {
            orientation = y > 0 ? .portraitUpsideDown : .portrait
        }
        return Result(orientation: orientation, isReliable: true)
    }
}
