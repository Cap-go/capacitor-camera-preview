import CoreLocation
import ImageIO
import XCTest
@testable import CapgoCameraPreview

final class ExifGpsMetadataTests: XCTestCase {
    func testGpsDateStampUsesExifFormatInUtc() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 10
        components.day = 19
        components.hour = 14
        components.minute = 30
        components.second = 45
        let date = components.date!
        XCTAssertEqual(ExifGpsMetadata.gpsDateStamp(from: date), "2026:10:19")
    }

    func testGpsTimeStampUsesExifFormatInUtc() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 10
        components.day = 19
        components.hour = 10
        components.minute = 31
        components.second = 34
        components.nanosecond = 60_000_000
        let date = components.date!
        XCTAssertEqual(ExifGpsMetadata.gpsTimeStamp(from: date), "10:31:34.06")
    }

    func testGpsDictionaryRoundTripThroughImageIOAvoidsZeroRationals() throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 38.72, longitude: -9.14),
            altitude: 120.5,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: 1_760_867_494)
        )
        let gpsDict = ExifGpsMetadata.gpsDictionary(for: location)
        XCTAssertNotNil(gpsDict[kCGImagePropertyGPSDateStamp as String])
        XCTAssertNotNil(gpsDict[kCGImagePropertyGPSTimeStamp as String])

        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create test CGImage")
            return
        }

        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: gpsDict
        ]
        guard let jpegData = ImageIOJpegEncoding.encode(cgImage: cgImage, properties: properties, qualityPercent: 90) else {
            XCTFail("JPEG encode failed")
            return
        }

        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let readGps = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] else {
            XCTFail("Failed to read GPS metadata from JPEG")
            return
        }

        let dateStamp = readGps[kCGImagePropertyGPSDateStamp as String] as? String
        XCTAssertEqual(dateStamp, ExifGpsMetadata.gpsDateStamp(from: location.timestamp))

        let timeStamp = readGps[kCGImagePropertyGPSTimeStamp as String]
        XCTAssertNotNil(timeStamp)
        if let timeStampString = timeStamp as? String {
            XCTAssertFalse(timeStampString.contains("0/0"))
        } else if let timeStampArray = timeStamp as? [Any] {
            for component in timeStampArray {
                if let rational = component as? [String: Any],
                   let numerator = rational["numerator"] as? Int,
                   let denominator = rational["denominator"] as? Int {
                    XCTAssertFalse(numerator == 0 && denominator == 0)
                }
            }
        }
    }
}
