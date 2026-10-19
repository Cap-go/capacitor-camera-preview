import XCTest
@testable import CapgoCameraPreview

final class CaptureLifecycleCoordinationTests: XCTestCase {
    func testDeferredStopRunsCleanupWhenCaptureFinishes() {
        var state = CaptureLifecycleState()
        state.isCapturingPhoto = true
        var cleanupCount = 0

        CaptureLifecycleCoordination.handleStop(state: &state, force: false, cleanup: { cleanupCount += 1 })

        XCTAssertTrue(state.stopRequestedAfterCapture)
        XCTAssertTrue(state.isCapturingPhoto)
        XCTAssertEqual(cleanupCount, 0)

        CaptureLifecycleCoordination.finishCapture(state: &state, cleanup: { cleanupCount += 1 })

        XCTAssertFalse(state.isCapturingPhoto)
        XCTAssertFalse(state.stopRequestedAfterCapture)
        XCTAssertEqual(cleanupCount, 1)
    }

    func testForceStopDuringCaptureCleansUpImmediately() {
        var state = CaptureLifecycleState()
        state.isCapturingPhoto = true
        var cleanupCount = 0

        CaptureLifecycleCoordination.handleStop(state: &state, force: true, cleanup: { cleanupCount += 1 })

        XCTAssertFalse(state.stopRequestedAfterCapture)
        XCTAssertEqual(cleanupCount, 1)
    }

    func testFinishCaptureWithoutDeferredStopDoesNotCleanup() {
        var state = CaptureLifecycleState()
        state.isCapturingPhoto = true
        var cleanupCount = 0

        CaptureLifecycleCoordination.finishCapture(state: &state, cleanup: { cleanupCount += 1 })

        XCTAssertFalse(state.isCapturingPhoto)
        XCTAssertFalse(state.stopRequestedAfterCapture)
        XCTAssertEqual(cleanupCount, 0)
    }

    func testStopAfterCaptureAlreadyFinishedCleansUpImmediately() {
        var state = CaptureLifecycleState()
        state.isCapturingPhoto = false
        var cleanupCount = 0

        CaptureLifecycleCoordination.handleStop(state: &state, force: false, cleanup: { cleanupCount += 1 })

        XCTAssertFalse(state.stopRequestedAfterCapture)
        XCTAssertEqual(cleanupCount, 1)
    }

    func testMainThreadFinishAfterDeferredStopMatchesReportedRace() {
        var state = CaptureLifecycleState()
        state.isCapturingPhoto = true
        var cleanupCount = 0
        let finishExpectation = expectation(description: "finish on main")

        DispatchQueue.main.async {
            CaptureLifecycleCoordination.handleStop(state: &state, force: false, cleanup: { cleanupCount += 1 })
            CaptureLifecycleCoordination.finishCapture(state: &state, cleanup: { cleanupCount += 1 })
            finishExpectation.fulfill()
        }

        waitForExpectations(timeout: 5)
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertFalse(state.stopRequestedAfterCapture)
    }
}
