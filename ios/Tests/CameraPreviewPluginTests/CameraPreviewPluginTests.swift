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

    func testExtremeRatioQuotientFallsBackToFullViewport() {
        XCTAssertNil(AspectRatioLayout.parseViewportAspectRatio("1e-300:1e300", isPortrait: true))

        let dimensions = AspectRatioLayout.dimensionsForAspectRatio(
            "1e-300:1e300",
            availableWidth: 428,
            availableHeight: 926,
            isPortrait: true
        )

        XCTAssertEqual(dimensions.width, 428)
        XCTAssertEqual(dimensions.height, 926)
    }

    func testPositionedFillUsesRemainingWebViewSpace() {
        let size = AspectRatioLayout.positionedFillSize(x: 20, y: 100, viewportWidth: 390, viewportHeight: 800)

        XCTAssertEqual(size.width, 370)
        XCTAssertEqual(size.height, 700)
    }

    func testPositionedFillNeverReturnsNegativeSize() {
        let size = AspectRatioLayout.positionedFillSize(x: 500, y: 900, viewportWidth: 390, viewportHeight: 800)

        XCTAssertEqual(size.width, 0)
        XCTAssertEqual(size.height, 0)
    }

    func testVisibleFillRatioMatchesPreviewWhenOrientationsAgree() {
        let ratio = AspectRatioLayout.visibleFillCaptureAspectRatio(
            previewSize: CGSize(width: 390, height: 844),
            interfaceIsPortrait: true,
            captureIsPortrait: true
        )

        XCTAssertEqual(ratio ?? 0, 390.0 / 844.0, accuracy: 0.0001)
    }

    func testVisibleFillRatioFlipsWhenCaptureOrientationDiffers() {
        let ratio = AspectRatioLayout.visibleFillCaptureAspectRatio(
            previewSize: CGSize(width: 390, height: 844),
            interfaceIsPortrait: true,
            captureIsPortrait: false
        )

        XCTAssertEqual(ratio ?? 0, 844.0 / 390.0, accuracy: 0.0001)
    }

    func testVisibleFillRatioRejectsEmptyPreview() {
        XCTAssertNil(
            AspectRatioLayout.visibleFillCaptureAspectRatio(
                previewSize: .zero,
                interfaceIsPortrait: true,
                captureIsPortrait: true
            )
        )
    }

    func testCenterCropOfPortraitPhotoToTallPreviewTrimsSides() {
        // 3:4 portrait photo shown in a 390x844 cover preview: the sides are cropped.
        let rect = AspectRatioLayout.centerCropRect(
            imageSize: CGSize(width: 3024, height: 4032),
            targetAspectRatio: 390.0 / 844.0
        )

        XCTAssertEqual(rect.height, 4032)
        XCTAssertEqual(rect.width, (4032 * 390.0 / 844.0).rounded(), accuracy: 2)
        XCTAssertEqual(rect.midX, 1512, accuracy: 1)
        XCTAssertEqual(rect.minY, 0)
    }

    func testCenterCropToWiderRatioTrimsTopAndBottom() {
        let rect = AspectRatioLayout.centerCropRect(
            imageSize: CGSize(width: 3024, height: 4032),
            targetAspectRatio: 1
        )

        XCTAssertEqual(rect.width, 3024)
        XCTAssertEqual(rect.height, 3024)
        XCTAssertEqual(rect.minY, 504)
    }

    func testCenterCropWithInvalidRatioKeepsFullImage() {
        let size = CGSize(width: 3024, height: 4032)
        XCTAssertEqual(AspectRatioLayout.centerCropRect(imageSize: size, targetAspectRatio: 0), CGRect(origin: .zero, size: size))
        XCTAssertEqual(
            AspectRatioLayout.centerCropRect(imageSize: size, targetAspectRatio: .infinity),
            CGRect(origin: .zero, size: size)
        )
    }
}
