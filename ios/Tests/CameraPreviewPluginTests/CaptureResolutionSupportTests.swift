import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class CaptureResolutionSupportTests: XCTestCase {
    func testParseCaptureResolutionNullObject() {
        let result = CaptureResolutionSupport.parseStartCaptureResolution(nil)
        XCTAssertFalse(result.isError)
        XCTAssertNil(result.width)
        XCTAssertNil(result.height)
    }

    func testParseCaptureResolutionMissingWidthOrHeight() {
        let missingWidth = CaptureResolutionSupport.parseStartCaptureResolution(["height": 1080])
        XCTAssertTrue(missingWidth.isError)
        XCTAssertEqual(missingWidth.errorMessage, "captureResolution requires both width and height")

        let missingHeight = CaptureResolutionSupport.parseStartCaptureResolution(["width": 1920])
        XCTAssertTrue(missingHeight.isError)
    }

    func testParseCaptureResolutionInvalidTypesAndValues() {
        XCTAssertTrue(CaptureResolutionSupport.parseStartCaptureResolution("not-an-object").isError)

        let zero = CaptureResolutionSupport.parseStartCaptureResolution(["width": 0, "height": 1080])
        XCTAssertTrue(zero.isError)

        let negative = CaptureResolutionSupport.parseStartCaptureResolution(["width": -1, "height": 1080])
        XCTAssertTrue(negative.isError)

        let nanWidth = CaptureResolutionSupport.parseStartCaptureResolution(["width": "NaN", "height": 1080])
        XCTAssertTrue(nanWidth.isError)
    }

    func testParseCaptureResolutionStringNumbers() {
        let result = CaptureResolutionSupport.parseStartCaptureResolution(["width": "1920", "height": "1080"])
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.width, 1920)
        XCTAssertEqual(result.height, 1080)
    }

    func testNormalizedCaptureTargetResolutionSwapsToLandscapeMajor() {
        let normalized = CaptureResolutionSupport.normalizedCaptureTargetResolution(configuredWidth: 1080, configuredHeight: 1920)
        XCTAssertEqual(normalized.width, 1920)
        XCTAssertEqual(normalized.height, 1080)
    }

    func testPhotoMaxDimensionsClampsToDeviceMax() {
        let deviceMax = CMVideoDimensions(width: 4032, height: 3024)
        let dimensions = CaptureResolutionSupport.photoMaxDimensions(
            configuredWidth: 1080,
            configuredHeight: 1920,
            deviceMax: deviceMax
        )
        XCTAssertEqual(dimensions.width, 1920)
        XCTAssertEqual(dimensions.height, 1080)

        let clamped = CaptureResolutionSupport.photoMaxDimensions(
            configuredWidth: 8000,
            configuredHeight: 6000,
            deviceMax: deviceMax
        )
        XCTAssertLessThanOrEqual(clamped.width, deviceMax.width)
        XCTAssertLessThanOrEqual(clamped.height, deviceMax.height)
    }

    func testShouldEnableHighResolutionPhotoWhenCaptureResolutionSet() {
        XCTAssertFalse(
            CaptureResolutionSupport.shouldEnableHighResolutionPhoto(
                captureResolutionWidth: 1920,
                captureResolutionHeight: 1080,
                captureMaxWidth: nil,
                captureMaxHeight: nil
            )
        )
    }

    func testShouldEnableHighResolutionPhotoWhenCaptureMaxDimensionsLarge() {
        XCTAssertTrue(
            CaptureResolutionSupport.shouldEnableHighResolutionPhoto(
                captureResolutionWidth: nil,
                captureResolutionHeight: nil,
                captureMaxWidth: 2048,
                captureMaxHeight: nil
            )
        )
    }
}

final class CapturePhotoProcessingQueueTests: XCTestCase {
    func testProcessingQueueIsNotMainThread() {
        let expectation = expectation(description: "background processing")
        var ranOnMain = true
        CapturePhotoProcessingQueue.async {
            ranOnMain = Thread.isMainThread
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertFalse(ranOnMain)
    }

    func testIsCurrentQueueOnlyOnProcessingQueue() {
        XCTAssertFalse(CapturePhotoProcessingQueue.isCurrentQueue)
        let expectation = expectation(description: "queue marker")
        CapturePhotoProcessingQueue.async {
            XCTAssertTrue(CapturePhotoProcessingQueue.isCurrentQueue)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)
    }
}
