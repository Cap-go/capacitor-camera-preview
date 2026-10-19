import CoreLocation
import ImageIO

enum ExifGpsMetadata {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!

    static func gpsDateStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = utcTimeZone
        formatter.dateFormat = "yyyy:MM:dd"
        return formatter.string(from: date)
    }

    static func gpsTimeStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = utcTimeZone
        formatter.dateFormat = "HH:mm:ss.SS"
        return formatter.string(from: date)
    }

    static func gpsDictionary(for location: CLLocation, heading: CLHeading? = nil) -> [String: Any] {
        let timestamp = location.timestamp
        var gpsDict: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSDateStamp as String: gpsDateStamp(from: timestamp),
            kCGImagePropertyGPSTimeStamp as String: gpsTimeStamp(from: timestamp),
            kCGImagePropertyGPSAltitude as String: location.altitude,
            kCGImagePropertyGPSAltitudeRef as String: location.altitude >= 0 ? 0 : 1
        ]

        if let heading = heading {
            let directionDegrees: Double
            let directionRef: String
            if heading.trueHeading >= 0 {
                directionDegrees = heading.trueHeading
                directionRef = "T"
            } else {
                directionDegrees = heading.magneticHeading
                directionRef = "M"
            }
            gpsDict[kCGImagePropertyGPSImgDirection as String] = directionDegrees
            gpsDict[kCGImagePropertyGPSImgDirectionRef as String] = directionRef
        }

        return gpsDict
    }
}
