import Foundation

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
