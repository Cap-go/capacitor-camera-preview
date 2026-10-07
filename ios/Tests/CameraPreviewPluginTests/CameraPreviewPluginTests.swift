import XCTest
@testable import CapgoCameraPreview

final class AspectRatioLayoutTests: XCTestCase {
    func testFillModeIsRecognizedCaseInsensitively() {
        XCTAssertTrue(AspectRatioLayout.isFillMode("fill"))
        XCTAssertTrue(AspectRatioLayout.isFillMode("FILL"))
        XCTAssertFalse(AspectRatioLayout.isFillMode("4:3"))
    }

    func testFillDoesNotParseAsNumericRatio() {
        XCTAssertNil(AspectRatioLayout.parseViewportAspectRatio("fill", isPortrait: true))
        XCTAssertNil(AspectRatioLayout.parseViewportAspectRatio("fill", isPortrait: false))
    }

    func testFillUsesFullAvailableSpace() {
        let dimensions = AspectRatioLayout.dimensionsForAspectRatio(
            "fill",
            availableWidth: 428,
            availableHeight: 926,
            isPortrait: true
        )

        XCTAssertEqual(dimensions.width, 428)
        XCTAssertEqual(dimensions.height, 926)
    }

    func testFourThreePortraitParsesAsThreeFour() {
        let ratio = AspectRatioLayout.parseViewportAspectRatio("4:3", isPortrait: true)
        XCTAssertEqual(ratio ?? 0, 0.75, accuracy: 0.0001)
    }

    func testFourThreePortraitLetterboxesInTallViewport() {
        let dimensions = AspectRatioLayout.dimensionsForAspectRatio(
            "4:3",
            availableWidth: 428,
            availableHeight: 926,
            isPortrait: true
        )

        XCTAssertEqual(dimensions.width, 428, accuracy: 0.5)
        XCTAssertLessThan(dimensions.height, 926)
        XCTAssertGreaterThan(dimensions.height, 500)
    }

    func testMalformedRatioFallsBackToFullViewport() {
        XCTAssertNil(AspectRatioLayout.parseViewportAspectRatio("4:bad:3", isPortrait: true))

        let dimensions = AspectRatioLayout.dimensionsForAspectRatio(
            "4:bad:3",
            availableWidth: 428,
            availableHeight: 926,
            isPortrait: true
        )

        XCTAssertEqual(dimensions.width, 428)
        XCTAssertEqual(dimensions.height, 926)
    }
}
