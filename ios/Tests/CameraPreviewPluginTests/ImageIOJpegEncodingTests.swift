import XCTest
@testable import CapgoCameraPreview

final class ImageIOJpegEncodingTests: XCTestCase {
    func testApplyingCompressionQualitySetsImageIODestinationKey() {
        let properties = ImageIOJpegEncoding.applyingCompressionQuality(42, to: [:])
        let quality = properties[kCGImageDestinationLossyCompressionQuality as String] as? CGFloat
        XCTAssertEqual(quality ?? -1, 0.42, accuracy: 0.0001)
    }

    func testEncodeProducesSmallerOutputAtLowerQuality() throws {
        let size = CGSize(width: 800, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 600, height: 400))
        }
        guard let cgImage = image.cgImage else {
            XCTFail("Failed to create test CGImage")
            return
        }

        let sourceJPEG = image.jpegData(compressionQuality: 1.0)
        XCTAssertNotNil(sourceJPEG)
        guard let sourceJPEG,
              let imageSource = CGImageSourceCreateWithData(sourceJPEG as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            XCTFail("Failed to read JPEG metadata for test fixture")
            return
        }

        guard let lowQualityData = ImageIOJpegEncoding.encode(cgImage: cgImage, properties: metadata, qualityPercent: 20),
              let highQualityData = ImageIOJpegEncoding.encode(cgImage: cgImage, properties: metadata, qualityPercent: 95) else {
            XCTFail("ImageIO JPEG encode failed")
            return
        }

        XCTAssertLessThan(lowQualityData.count, highQualityData.count)
    }
}
