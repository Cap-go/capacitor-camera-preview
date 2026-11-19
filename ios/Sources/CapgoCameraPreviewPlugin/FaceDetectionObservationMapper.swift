import CoreGraphics
import Foundation

enum FaceDetectionObservationMapper {
    static func normalizedBounds(from visionBounds: CGRect) -> [String: Double] {
        let x = Double(visionBounds.origin.x)
        let y = 1.0 - Double(visionBounds.origin.y) - Double(visionBounds.height)
        let width = Double(visionBounds.width)
        let height = Double(visionBounds.height)
        return [
            "x": x,
            "y": y,
            "width": width,
            "height": height
        ]
    }

    static func facePayload(from visionBounds: CGRect, trackingIdentifier: Int?) -> [String: Any] {
        var payload: [String: Any] = [
            "bounds": normalizedBounds(from: visionBounds)
        ]
        if let trackingIdentifier {
            payload["trackingId"] = trackingIdentifier
        }
        return payload
    }
}