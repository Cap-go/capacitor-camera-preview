import AVFoundation
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

    func testRecoverySkippedWhenTeardownStartedForStaleSession() {
        XCTAssertTrue(
            CaptureSessionRecoveryGate.shouldSkipRecovery(sessionTeardownStarted: true, isObservedSession: false)
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

    func testControllerPrepareBeginGateClearsTeardownAfterCleanupWithNilSession() {
        let controller = CameraController()
        controller.cleanup()

        XCTAssertNil(controller.captureSession)
        XCTAssertTrue(controller.captureSessionTeardownStarted)

        XCTAssertTrue(controller.runPrepareBeginGateForTesting(startToken: 1))
        XCTAssertFalse(controller.captureSessionTeardownStarted)
    }

    func testControllerPrepareBeginGateBlocksWhileLiveSessionIsTearingDown() {
        let controller = CameraController()
        controller.captureSession = AVCaptureSession()
        controller.markCaptureSessionTeardownInProgressForTesting()

        XCTAssertFalse(controller.runPrepareBeginGateForTesting(startToken: 1))
        XCTAssertTrue(controller.captureSessionTeardownStarted)
        XCTAssertNotNil(controller.captureSession)
    }

    func testControllerCleanupThenPrepareBeginGateDoesNotReuseTornDownSession() {
        let controller = CameraController()
        controller.captureSession = AVCaptureSession()
        controller.markCaptureSessionTeardownInProgressForTesting()

        XCTAssertFalse(controller.runPrepareBeginGateForTesting(startToken: 1))

        controller.cleanup()

        XCTAssertNil(controller.captureSession)
        XCTAssertTrue(controller.captureSessionTeardownStarted)
        XCTAssertTrue(controller.runPrepareBeginGateForTesting(startToken: 2))
        XCTAssertFalse(controller.captureSessionTeardownStarted)
    }

    func testControllerCleanupWhilePrepareMutationHeldOnCaptureQueueClearsSession() {
        let controller = CameraController()
        let passedGate = DispatchSemaphore(value: 0)
        let releaseHold = DispatchSemaphore(value: 0)
        let cleanupFinished = expectation(description: "cleanup finished")

        controller.holdCaptureSessionQueueAfterPrepareBeginForTesting(
            startToken: 1,
            passedGate: passedGate,
            releaseHold: releaseHold
        )

        XCTAssertEqual(passedGate.wait(timeout: .now() + 5), .success)
        XCTAssertNotNil(controller.captureSession)

        DispatchQueue.global(qos: .userInitiated).async {
            controller.cleanup()
            cleanupFinished.fulfill()
        }

        releaseHold.signal()

        wait(for: [cleanupFinished], timeout: 5)
        XCTAssertNil(controller.captureSession)
        XCTAssertTrue(controller.runPrepareBeginGateForTesting(startToken: 2))
    }

    func testMutationExecutorSyncDoesNotDeadlockWhenReentrant() {
        let queue = DispatchQueue(label: "com.capgo.camera.test.captureSession")
        let queueKey = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: queueKey, value: true)
        CaptureSessionMutationExecutor.register(queue: queue)
        var outerRan = false
        var innerRan = false
        var outerOnQueue = false

        CaptureSessionMutationExecutor.performSync(on: queue) {
            outerOnQueue = DispatchQueue.getSpecific(key: queueKey) == true
            outerRan = true
            CaptureSessionMutationExecutor.performSync(on: queue) {
                innerRan = true
            }
        }

        XCTAssertTrue(outerOnQueue)
        XCTAssertTrue(outerRan)
        XCTAssertTrue(innerRan)
    }

    func testMutationExecutorAsyncEventuallyRuns() {
        let queue = DispatchQueue(label: "com.capgo.camera.test.captureSession.async")
        let queueKey = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: queueKey, value: true)
        CaptureSessionMutationExecutor.register(queue: queue)
        let expectation = expectation(description: "async mutation")
        var ran = false
        var ranOnQueue = false

        CaptureSessionMutationExecutor.performAsync(on: queue) {
            ranOnQueue = DispatchQueue.getSpecific(key: queueKey) == true
            ran = true
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
        XCTAssertTrue(ran)
        XCTAssertTrue(ranOnQueue)
    }
}
