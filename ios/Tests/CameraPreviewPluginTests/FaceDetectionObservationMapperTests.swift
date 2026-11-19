import CoreGraphics
import XCTest

@testable import CapgoCameraPreviewPlugin

final class FaceDetectionObservationMapperTests: XCTestCase {
    func testNormalizedBoundsConvertsVisionBottomLeftOriginToTopLeft() {
        let visionBounds = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5)
        let bounds = FaceDetectionObservationMapper.normalizedBounds(from: visionBounds)

        XCTAssertEqual(bounds["x"], 0.1, accuracy: 0.0001)
        XCTAssertEqual(bounds["y"], 0.3, accuracy: 0.0001)
        XCTAssertEqual(bounds["width"], 0.4, accuracy: 0.0001)
        XCTAssertEqual(bounds["height"], 0.5, accuracy: 0.0001)
    }
}