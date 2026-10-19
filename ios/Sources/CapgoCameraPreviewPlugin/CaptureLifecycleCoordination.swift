import Foundation

/// Flags coordinating `stop()` with an in-flight still capture. Mutate only on the main thread.
struct CaptureLifecycleState {
    var isCapturingPhoto: Bool = false
    var stopRequestedAfterCapture: Bool = false
}

enum CaptureLifecycleCoordination {
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
