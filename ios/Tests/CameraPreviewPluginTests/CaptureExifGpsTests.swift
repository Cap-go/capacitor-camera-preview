import CoreLocation
import XCTest
@testable import CapgoCameraPreview

private final class TestCLHeading: CLHeading {
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
        let expected = TestCLHeading(trueHeading: 10, magneticHeading: 11, headingAccuracy: 3)
        let read = CaptureExifHeadingReader.readCurrentHeading { expected }
        XCTAssertTrue(read === expected)
    }

    func testHeadingReaderFetchesFromMainWhenOffMainThread() {
        let expected = TestCLHeading(trueHeading: 42, magneticHeading: 44, headingAccuracy: 2)
        let expectation = expectation(description: "read on main")
        DispatchQueue.global(qos: .userInitiated).async {
            let read = CaptureExifHeadingReader.readCurrentHeading {
                XCTAssertTrue(Thread.isMainThread)
                return expected
            }
            XCTAssertTrue(read === expected)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testHeadingFallbackAfterLocationRefresh() {
        let prior = TestCLHeading(trueHeading: 88.0, magneticHeading: 90.0, headingAccuracy: 4)
        let afterRefresh = CaptureExifHeadingLifecycle.heading(after: .locationRefreshStarted, current: prior)
        XCTAssertTrue(afterRefresh === prior)
        let direction = afterRefresh.flatMap(CaptureExifGps.imageDirection)
        XCTAssertEqual(direction?.degrees, 88.0)
        XCTAssertEqual(direction?.reference, "T")
    }

    func testCaptureExifFinishedClearsHeading() {
        let prior = TestCLHeading(trueHeading: 88.0, magneticHeading: 90.0, headingAccuracy: 4)
        XCTAssertNil(CaptureExifHeadingLifecycle.heading(after: .captureExifFinished, current: prior))
    }
}
