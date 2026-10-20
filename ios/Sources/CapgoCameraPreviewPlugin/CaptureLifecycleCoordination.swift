import Foundation

/// Flags coordinating `stop()` with an in-flight still capture. Mutate only on the main thread.
struct CaptureLifecycleState {
    var isCapturingPhoto: Bool = false
    var stopRequestedAfterCapture: Bool = false
    var isAwaitingSampleCapture: Bool = false
}

enum CaptureReadiness {
    /// Matches `isRunning()` and capture guards: preview started and capture session active.
    static func canPerformCapture(isInitialized: Bool, isCaptureSessionRunning: Bool) -> Bool {
        isInitialized && isCaptureSessionRunning
    }
}

enum CaptureSubmissionGate {
    /// Blocks still capture submission once teardown started or the session stopped.
    static func blocksPhotoCaptureSubmission(sessionTeardownStarted: Bool, isCaptureSessionRunning: Bool) -> Bool {
        sessionTeardownStarted || !isCaptureSessionRunning
    }

    /// Main-thread only: gate check and `isCapturingPhoto = true` in one step.
    static func tryClaimPhotoCapture(
        sessionTeardownStarted: Bool,
        isCaptureSessionRunning: Bool,
        isCapturingPhoto: inout Bool
    ) -> Bool {
        if blocksPhotoCaptureSubmission(
            sessionTeardownStarted: sessionTeardownStarted,
            isCaptureSessionRunning: isCaptureSessionRunning
        ) {
            return false
        }
        isCapturingPhoto = true
        return true
    }
}

enum CaptureLifecycleCoordination {
    /// Rejects a pending sample-buffer capture when teardown begins (call on the main thread).
    static func cancelAwaitingSampleCaptureIfNeeded(isAwaiting: Bool, cancel: () -> Void) {
        guard isAwaiting else { return }
        cancel()
    }
    /// Handles `stop()` when a capture may be in flight. Call on the main thread only.
    static func handleStop(
        state: inout CaptureLifecycleState,
        force: Bool,
        cleanup: () -> Void
    ) {
        if state.isCapturingPhoto && !force {
            state.stopRequestedAfterCapture = true
            return
        }
        if force {
            state.stopRequestedAfterCapture = false
        }
        cleanup()
    }

    /// Ends the capture lifecycle after processing completes. Call on the main thread only.
    static func finishCapture(
        state: inout CaptureLifecycleState,
        cleanup: () -> Void
    ) {
        state.isCapturingPhoto = false
        if state.stopRequestedAfterCapture {
            cleanup()
            state.stopRequestedAfterCapture = false
        }
    }
}
