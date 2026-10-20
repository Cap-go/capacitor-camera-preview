import CoreLocation
import ImageIO
import UIKit
import XCTest
@testable import CapgoCameraPreview

private final class CaptureExifGpsEncoderTestHeading: CLHeading {
    private let storedTrue: CLLocationDirection
    private let storedMagnetic: CLLocationDirection
    private let storedAccuracy: CLLocationAccuracy

    init(
        trueHeading: CLLocationDirection,
        magneticHeading: CLLocationDirection,
        headingAccuracy: CLLocationAccuracy
    ) {
        self.storedTrue = trueHeading
        self.storedMagnetic = magneticHeading
        self.storedAccuracy = headingAccuracy
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var trueHeading: CLLocationDirection { storedTrue }
    override var magneticHeading: CLLocationDirection { storedMagnetic }
    override var headingAccuracy: CLLocationAccuracy { storedAccuracy }
}

final class CaptureImageExifEncoderTests: XCTestCase {
    func testSkipsJpegEncodeWhenOriginalPhotoDataProvided() {
        let image = makeTestImage()
        guard let originalPhotoData = image.jpegData(compressionQuality: 0.9) else {
            XCTFail("Failed to build fixture JPEG")
            return
        }

        var encodeCallCount = 0
        let result = CaptureImageExifEncoder.createImageData(
            from: image,
            quality: 85,
            location: nil,
            heading: nil,
            originalPhotoData: originalPhotoData,
            jpegEncoder: { _, _ in
                encodeCallCount += 1
                return nil
            }
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(encodeCallCount, 0)
    }

    func testProducesJpegWithTiffMetadata() {
        let image = makeTestImage()
        guard let originalPhotoData = image.jpegData(compressionQuality: 0.9) else {
            XCTFail("Failed to build fixture JPEG")
            return
        }

        let result = CaptureImageExifEncoder.createImageData(
            from: image,
            quality: 85,
            location: nil,
            heading: nil,
            originalPhotoData: originalPhotoData
        )

        guard let result,
              let source = CGImageSourceCreateWithData(result as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] else {
            XCTFail("Expected JPEG output with TIFF metadata")
            return
        }

        XCTAssertEqual(tiff[kCGImagePropertyTIFFMake as String] as? String, "Apple")
    }

    func testHonorsRequestedQualityWhenOriginalPhotoDataProvided() {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 50, y: 50, width: 300, height: 200))
        }
        guard let originalPhotoData = image.jpegData(compressionQuality: 1.0) else {
            XCTFail("Failed to build fixture JPEG")
            return
        }

        guard let lowQuality = CaptureImageExifEncoder.createImageData(
            from: image,
            quality: 20,
            location: nil,
            heading: nil,
            originalPhotoData: originalPhotoData
        ),
        let highQuality = CaptureImageExifEncoder.createImageData(
            from: image,
            quality: 95,
            location: nil,
            heading: nil,
            originalPhotoData: originalPhotoData
        ) else {
            XCTFail("Expected JPEG output at both quality levels")
            return
        }

        XCTAssertLessThan(lowQuality.count, highQuality.count)
    }

    func testFallsBackToJpegEncoderWhenMetadataReadFails() {
        let image = makeTestImage()
        let invalidOriginalData = Data([0x00, 0x01, 0x02, 0x03])

        var encodeCallCount = 0
        let result = CaptureImageExifEncoder.createImageData(
            from: image,
            quality: 85,
            location: nil,
            heading: nil,
            originalPhotoData: invalidOriginalData,
            jpegEncoder: { _, _ in
                encodeCallCount += 1
                return image.jpegData(compressionQuality: 0.85)
            }
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(encodeCallCount, 1)
    }

    func testEmbedsGpsDateTimeAndImageDirectionWhenLocationAndHeadingProvided() {
        let image = makeTestImage()
        guard let originalPhotoData = image.jpegData(compressionQuality: 0.9) else {
            XCTFail("Failed to build fixture JPEG")
            return
        }

        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 38.72, longitude: -9.14),
            altitude: 120.5,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: 1_760_867_494.06)
        )
        let heading = CaptureExifGpsEncoderTestHeading(trueHeading: 88.0, magneticHeading: 90.0, headingAccuracy: 4)

        guard let result = CaptureImageExifEncoder.createImageData(
            from: image,
            quality: 85,
            location: location,
            heading: heading,
            originalPhotoData: originalPhotoData
        ),
        let source = CGImageSourceCreateWithData(result as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] else {
            XCTFail("Expected JPEG output with GPS metadata")
            return
        }

        XCTAssertEqual(gps[kCGImagePropertyGPSDateStamp as String] as? String, ExifGpsMetadata.gpsDateStamp(from: location.timestamp))
        let wholeSeconds = floor(location.timestamp.timeIntervalSince1970)
        let expectedTimeStamp = ExifGpsMetadata.gpsTimeStamp(from: Date(timeIntervalSince1970: wholeSeconds))
        if let readTime = gps[kCGImagePropertyGPSTimeStamp as String] as? String {
            XCTAssertEqual(readTime, expectedTimeStamp)
        } else {
            XCTAssertNotNil(gps[kCGImagePropertyGPSTimeStamp as String])
        }
        XCTAssertEqual(gps[kCGImagePropertyGPSImgDirection as String] as? Double, 88.0)
        XCTAssertEqual(gps[kCGImagePropertyGPSImgDirectionRef as String] as? String, "T")
    }

    func testEncodesWhenOriginalPhotoDataMissing() {
        let image = makeTestImage()

        var encodeCallCount = 0
        let result = CaptureImageExifEncoder.createImageData(
            from: image,
            quality: 85,
            location: nil,
            heading: nil,
            originalPhotoData: nil,
            jpegEncoder: { _, _ in
                encodeCallCount += 1
                return image.jpegData(compressionQuality: 0.85)
            }
        )

        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(encodeCallCount, 1)
    }

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }
}
