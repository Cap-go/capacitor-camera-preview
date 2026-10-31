import XCTest
@testable import CapgoCameraPreview

final class CaptureSessionCoordinationTests: XCTestCase {
    func testRecoverySkippedWhenTeardownStarted() {
        XCTAssertTrue(
            CaptureSessionRecoveryGate.shouldSkipRecovery(sessionTeardownStarted: true, isObservedSession: true)
        )
    }

    func testRecoverySkippedWhenSessionDoesNotMatch() {
        XCTAssertTrue(
            CaptureSessionRecoveryGate.shouldSkipRecovery(sessionTeardownStarted: false, isObservedSession: false)
        )
    }

    func testRecoveryAllowedWhenSessionActiveAndNotTearingDown() {
        XCTAssertFalse(
            CaptureSessionRecoveryGate.shouldSkipRecovery(sessionTeardownStarted: false, isObservedSession: true)
        )
    }

    func testPrepareAbortsWhenTeardownInProgressOnLiveSession() {
        XCTAssertFalse(
            CaptureSessionPrepareGate.mayBeginPrepareOnQueue(sessionTeardownStarted: true, hasLiveCaptureSession: true)
        )
    }

    func testPrepareClearsTeardownFlagAfterCleanupWhenSessionNil() {
        XCTAssertTrue(
            CaptureSessionPrepareGate.shouldClearTeardownStartedBeforePrepare(
                sessionTeardownStarted: true,
                hasLiveCaptureSession: false
            )
        )
        XCTAssertTrue(
            CaptureSessionPrepareGate.mayBeginPrepareOnQueue(sessionTeardownStarted: true, hasLiveCaptureSession: false)
        )
    }

    func testMutationExecutorSyncDoesNotDeadlockWhenReentrant() {
        let queue = DispatchQueue(label: "com.capgo.camera.test.captureSession")
        CaptureSessionMutationExecutor.register(queue: queue)
        var outerRan = false
        var innerRan = false

        CaptureSessionMutationExecutor.performSync(on: queue) {
            outerRan = true
            CaptureSessionMutationExecutor.performSync(on: queue) {
                innerRan = true
            }
        }

        XCTAssertTrue(outerRan)
        XCTAssertTrue(innerRan)
    }

    func testMutationExecutorAsyncEventuallyRuns() {
        let queue = DispatchQueue(label: "com.capgo.camera.test.captureSession.async")
        CaptureSessionMutationExecutor.register(queue: queue)
        let expectation = expectation(description: "async mutation")
        var ran = false

        CaptureSessionMutationExecutor.performAsync(on: queue) {
            ran = true
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
        XCTAssertTrue(ran)
    }
}
