import XCTest
@testable import CapgoCameraPreview

final class CaptureExifGpsTests: XCTestCase {
    func testImageDirectionUsesTrueHeadingWhenAvailable() {
        let direction = CaptureExifGps.imageDirection(
            trueHeading: 175.4,
            magneticHeading: 180.0,
            headingAccuracy: 5
        )
        XCTAssertEqual(direction?.degrees, 175.4)
        XCTAssertEqual(direction?.reference, "T")
    }

    func testImageDirectionFallsBackToMagneticWhenTrueHeadingInvalid() {
        let direction = CaptureExifGps.imageDirection(
            trueHeading: -1,
            magneticHeading: 182.5,
            headingAccuracy: 5
        )
        XCTAssertEqual(direction?.degrees, 182.5)
        XCTAssertEqual(direction?.reference, "M")
    }

    func testImageDirectionNilWhenAccuracyInvalid() {
        XCTAssertNil(
            CaptureExifGps.imageDirection(
                trueHeading: 90,
                magneticHeading: 90,
                headingAccuracy: -1
            )
        )
    }

    func testHeadingReaderReturnsProviderValueOnMainThread() {
        let value = CaptureExifHeadingReader.readCurrentHeading { nil }
        XCTAssertNil(value)
    }

    func testHeadingReaderFetchesFromMainWhenOffMainThread() {
        let expectation = expectation(description: "read on main")
        DispatchQueue.global(qos: .userInitiated).async {
            let heading = CaptureExifHeadingReader.readCurrentHeading { nil }
            XCTAssertNil(heading)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
