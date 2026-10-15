import AVFoundation
import Foundation

/// Serializes capture, deferred restore, and completion for the app `AVAudioSession` around preview and recording.
final class ApplicationAudioSessionRestoreCoordinator {
    private let queue = DispatchQueue(label: "com.capgo.camera.applicationAudioSessionRestore")

    private var snapshot: ApplicationAudioSessionSnapshot?
    private var snapshotPreviewGeneration: UInt64?
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
                self.clearDeferredRestoreWithoutApplying()
            }
        }
    }

    func captureSnapshotIfNeeded() {
        self.queue.sync {
            guard self.snapshot == nil || self.snapshotPreviewGeneration != self.previewGeneration else { return }
            self.snapshot = ApplicationAudioSessionSnapshot.capture()
            self.snapshotPreviewGeneration = self.previewGeneration
        }
    }

    func handleCleanup(isRecording: Bool, pendingRecordingId: UInt64? = nil) {
        self.queue.sync {
            if self.deferredRecordingId != nil {
                return
            }
            let shouldDeferRestore = isRecording || pendingRecordingId != nil
            if shouldDeferRestore {
                let recordingId = pendingRecordingId ?? self.activeRecordingId ?? 0
                guard recordingId != 0 else { return }
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

    func syncWithQueueForTesting() {
        self.queue.sync {}
    }

    private func completeDeferredRestoreIfNeeded(forRecordingId recordingId: UInt64) {
        guard let deferredId = self.deferredRecordingId, deferredId == recordingId else {
            return
        }
        if self.deferredPreviewGeneration != self.previewGeneration {
            self.clearDeferredRestoreWithoutApplying()
            return
        }
        self.deferredRecordingId = nil
        self.deferredPreviewGeneration = nil
        self.restoreNow()
    }

    private func clearDeferredRestoreWithoutApplying() {
        self.deferredRecordingId = nil
        self.deferredPreviewGeneration = nil
    }

    private func restoreNow() {
        guard let snap = self.snapshot else { return }
        self.snapshot = nil
        self.snapshotPreviewGeneration = nil
        snap.apply()
    }
}
