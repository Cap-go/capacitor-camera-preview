import XCTest
@testable import CapgoCameraPreview

final class CaptureLifecycleCoordinationTests: XCTestCase {
    func testCaptureReadinessRequiresInitializedSessionAndRunningCaptureSession() {
        XCTAssertFalse(CaptureReadiness.canPerformCapture(isInitialized: false, isCaptureSessionRunning: false))
        XCTAssertFalse(CaptureReadiness.canPerformCapture(isInitialized: false, isCaptureSessionRunning: true))
        XCTAssertFalse(CaptureReadiness.canPerformCapture(isInitialized: true, isCaptureSessionRunning: false))
        XCTAssertTrue(CaptureReadiness.canPerformCapture(isInitialized: true, isCaptureSessionRunning: true))
    }

    func testPhotoCaptureSubmissionBlockedWhenTeardownStartedOrSessionStopped() {
        XCTAssertTrue(CaptureSubmissionGate.blocksPhotoCaptureSubmission(sessionTeardownStarted: true, isCaptureSessionRunning: true))
        XCTAssertTrue(CaptureSubmissionGate.blocksPhotoCaptureSubmission(sessionTeardownStarted: false, isCaptureSessionRunning: false))
        XCTAssertTrue(CaptureSubmissionGate.blocksPhotoCaptureSubmission(sessionTeardownStarted: true, isCaptureSessionRunning: false))
        XCTAssertFalse(CaptureSubmissionGate.blocksPhotoCaptureSubmission(sessionTeardownStarted: false, isCaptureSessionRunning: true))
    }

    func testTryClaimPhotoCaptureSetsFlagOnlyWhenSubmissionAllowed() {
        var isCapturing = false
        XCTAssertFalse(
            CaptureSubmissionGate.tryClaimPhotoCapture(
                sessionTeardownStarted: true,
                isCaptureSessionRunning: true,
                isCapturingPhoto: &isCapturing
            )
        )
        XCTAssertFalse(isCapturing)

        XCTAssertTrue(
            CaptureSubmissionGate.tryClaimPhotoCapture(
                sessionTeardownStarted: false,
                isCaptureSessionRunning: true,
                isCapturingPhoto: &isCapturing
            )
        )
        XCTAssertTrue(isCapturing)

        XCTAssertFalse(
            CaptureSubmissionGate.tryClaimPhotoCapture(
                sessionTeardownStarted: false,
                isCaptureSessionRunning: false,
                isCapturingPhoto: &isCapturing
            )
        )
        XCTAssertTrue(isCapturing)
    }

    func testClaimAwaitingSampleCaptureIsOneShot() {
        var state = CaptureLifecycleState()
        XCTAssertFalse(CaptureLifecycleCoordination.claimAwaitingSampleCapture(state: &state))
        state.isAwaitingSampleCapture = true
        XCTAssertTrue(CaptureLifecycleCoordination.claimAwaitingSampleCapture(state: &state))
        XCTAssertFalse(state.isAwaitingSampleCapture)
        XCTAssertFalse(CaptureLifecycleCoordination.claimAwaitingSampleCapture(state: &state))
    }

    func testCancelAwaitingSampleCaptureOnlyWhenAwaiting() {
        var cancelCount = 0
        CaptureLifecycleCoordination.cancelAwaitingSampleCaptureIfNeeded(isAwaiting: false) { cancelCount += 1 }
        XCTAssertEqual(cancelCount, 0)

        CaptureLifecycleCoordination.cancelAwaitingSampleCaptureIfNeeded(isAwaiting: true) { cancelCount += 1 }
        XCTAssertEqual(cancelCount, 1)
    }

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

    func testCoordinatorDeferredStopThenFinishCleansUpOnce() {
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
