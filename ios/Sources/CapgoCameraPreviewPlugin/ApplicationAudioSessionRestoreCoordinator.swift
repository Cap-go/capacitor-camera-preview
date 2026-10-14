import AVFoundation
import Foundation

/// Serializes capture, deferred restore, and completion for the app `AVAudioSession` around preview and recording.
final class ApplicationAudioSessionRestoreCoordinator {
    private let queue = DispatchQueue(label: "com.capgo.camera.applicationAudioSessionRestore")

    private var snapshot: ApplicationAudioSessionSnapshot?
    private var previewGeneration: UInt64 = 0
    private var activeRecordingId: UInt64?
    private var nextRecordingId: UInt64 = 1
    private var deferredRecordingId: UInt64?
    private var deferredPreviewGeneration: UInt64?

    var isDeferredRestorePending: Bool {
        self.queue.sync { self.deferredRecordingId != nil }
    }

    func beginPreviewSession() {
        self.queue.sync {
            self.previewGeneration += 1
            if self.deferredRecordingId != nil {
                self.discardPendingRestoreWithoutApplying()
            }
        }
    }

    func captureSnapshotIfNeeded() {
        self.queue.sync {
            guard self.snapshot == nil else { return }
            self.snapshot = ApplicationAudioSessionSnapshot.capture()
        }
    }

    func handleCleanup(isRecording: Bool) {
        self.queue.sync {
            if self.deferredRecordingId != nil {
                return
            }
            if isRecording {
                let recordingId = self.activeRecordingId ?? 0
                self.deferredRecordingId = recordingId
                self.deferredPreviewGeneration = self.previewGeneration
                return
            }
            self.restoreNow()
        }
    }

    func beginRecording() -> UInt64 {
        self.queue.sync {
            let id = self.nextRecordingId
            self.nextRecordingId += 1
            self.activeRecordingId = id
            return id
        }
    }

    func finishRecording(recordingId: UInt64) {
        self.queue.sync {
            if self.activeRecordingId == recordingId {
                self.activeRecordingId = nil
            }
            self.completeDeferredRestoreIfNeeded(forRecordingId: recordingId)
        }
    }

    func finishRecordingAsync(recordingId: UInt64) {
        self.queue.async {
            if self.activeRecordingId == recordingId {
                self.activeRecordingId = nil
            }
            self.completeDeferredRestoreIfNeeded(forRecordingId: recordingId)
        }
    }

    private func completeDeferredRestoreIfNeeded(forRecordingId recordingId: UInt64) {
        guard let deferredId = self.deferredRecordingId, deferredId == recordingId else {
            return
        }
        if self.deferredPreviewGeneration != self.previewGeneration {
            self.discardPendingRestoreWithoutApplying()
            return
        }
        self.deferredRecordingId = nil
        self.deferredPreviewGeneration = nil
        self.restoreNow()
    }

    private func discardPendingRestoreWithoutApplying() {
        self.deferredRecordingId = nil
        self.deferredPreviewGeneration = nil
        self.snapshot = nil
    }

    private func restoreNow() {
        guard let snap = self.snapshot else { return }
        self.snapshot = nil
        snap.apply()
    }
}
