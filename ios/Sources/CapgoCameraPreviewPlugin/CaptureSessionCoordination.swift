import Foundation

/// Guards prepare against reusing a session that cleanup is still tearing down on the capture queue.
enum CaptureSessionPrepareGate {
    static func mayBeginPrepareOnQueue(sessionTeardownStarted: Bool, hasLiveCaptureSession: Bool) -> Bool {
        !(sessionTeardownStarted && hasLiveCaptureSession)
    }

    static func shouldClearTeardownStartedBeforePrepare(sessionTeardownStarted: Bool, hasLiveCaptureSession: Bool) -> Bool {
        sessionTeardownStarted && !hasLiveCaptureSession
    }

    /// Applies prepare begin gating on the capture queue (see `CameraController.prepare`).
    static func applyBeginIfAllowed(sessionTeardownStarted: inout Bool, hasLiveCaptureSession: Bool) -> Bool {
        guard mayBeginPrepareOnQueue(
            sessionTeardownStarted: sessionTeardownStarted,
            hasLiveCaptureSession: hasLiveCaptureSession
        ) else {
            return false
        }
        if shouldClearTeardownStartedBeforePrepare(
            sessionTeardownStarted: sessionTeardownStarted,
            hasLiveCaptureSession: hasLiveCaptureSession
        ) {
            sessionTeardownStarted = false
        }
        return true
    }
}

/// Guards interruption / runtime-error recovery against overlapping teardown.
enum CaptureSessionRecoveryGate {
    static func shouldSkipRecovery(sessionTeardownStarted: Bool, isObservedSession: Bool) -> Bool {
        sessionTeardownStarted || !isObservedSession
    }
}

/// Serializes mutation work onto the capture session queue without deadlocking when already on that queue.
enum CaptureSessionMutationExecutor {
    private static let queueKey = DispatchSpecificKey<UInt8>()

    static func register(queue: DispatchQueue) {
        queue.setSpecific(key: queueKey, value: 1)
    }

    static func performSync(on queue: DispatchQueue, _ block: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            block()
        } else {
            queue.sync(execute: block)
        }
    }

    static func performAsync(on queue: DispatchQueue, _ block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}
