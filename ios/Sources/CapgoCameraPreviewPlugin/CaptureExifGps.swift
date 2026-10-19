import CoreLocation
import Foundation

/// GPS EXIF helpers for still capture (heading / image direction).
enum CaptureExifGps {
    struct ImageDirection: Equatable {
        let degrees: Double
        /// `T` (true north) or `M` (magnetic north).
        let reference: String
    }

    static func imageDirection(
        trueHeading: Double,
        magneticHeading: Double,
        headingAccuracy: Double
    ) -> ImageDirection? {
        guard headingAccuracy >= 0 else { return nil }
        if trueHeading >= 0 {
            return ImageDirection(degrees: trueHeading, reference: "T")
        }
        return ImageDirection(degrees: magneticHeading, reference: "M")
    }

    static func imageDirection(from heading: CLHeading) -> ImageDirection? {
        imageDirection(
            trueHeading: heading.trueHeading,
            magneticHeading: heading.magneticHeading,
            headingAccuracy: heading.headingAccuracy
        )
    }
}

/// Reads the latest compass heading from the main queue (where `CLLocationManager` delivers updates).
enum CaptureExifHeadingReader {
    static func readCurrentHeading(_ provider: @escaping () -> CLHeading?) -> CLHeading? {
        if Thread.isMainThread {
            return provider()
        }
        return DispatchQueue.main.sync { provider() }
    }
}
