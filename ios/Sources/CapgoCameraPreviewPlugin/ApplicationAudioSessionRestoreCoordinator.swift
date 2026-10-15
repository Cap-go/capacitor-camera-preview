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
    private var deferredRecordingIds: Set<UInt64> = []
    private var deferredPreviewGeneration: UInt64?
    private var finishedBeforeDeferral: Set<UInt64> = []

    var isDeferredRestorePending: Bool {
        self.queue.sync { !self.deferredRecordingIds.isEmpty }
    }

    func beginPreviewSession() {
        self.queue.sync {
            self.previewGeneration += 1
            if !self.deferredRecordingIds.isEmpty {
                self.clearDeferredRestoreWithoutApplying()
            }
        }
    }

    func captureSnapshotIfNeeded() {
        self.queue.sync {
            guard self.snapshot == nil else { return }
            self.snapshot = ApplicationAudioSessionSnapshot.capture()
            self.snapshotPreviewGeneration = self.previewGeneration
        }
    }

    /// Registers deferred restore before capture session teardown. Returns `true` if the snapshot should be applied after teardown.
    func beginCaptureSessionTeardown(isRecording: Bool, pendingRecordingIds: Set<UInt64> = []) -> Bool {
        self.queue.sync {
            if !self.deferredRecordingIds.isEmpty {
                return false
            }
            var ids = pendingRecordingIds
            if isRecording, let active = self.activeRecordingId {
                ids.insert(active)
            }
            ids.subtract(self.finishedBeforeDeferral)
            self.finishedBeforeDeferral.removeAll()
            guard !ids.isEmpty else {
                return true
            }
            self.deferredRecordingIds = ids
            self.deferredPreviewGeneration = self.previewGeneration
            return false
        }
    }

    func restoreAfterCaptureSessionTeardown() {
        self.queue.sync {
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
            self.noteRecordingFinished(recordingId)
        }
    }

    func finishRecordingAsync(recordingId: UInt64) {
        self.queue.async {
            self.noteRecordingFinished(recordingId)
        }
    }

    func syncWithQueueForTesting() {
        self.queue.sync {}
    }

    private func noteRecordingFinished(_ recordingId: UInt64) {
        if self.activeRecordingId == recordingId {
            self.activeRecordingId = nil
        }
        if self.deferredRecordingIds.isEmpty {
            self.finishedBeforeDeferral.insert(recordingId)
            return
        }
        self.deferredRecordingIds.remove(recordingId)
        self.tryCompleteDeferredRestore()
    }

    private func tryCompleteDeferredRestore() {
        guard self.deferredRecordingIds.isEmpty else { return }
        if self.deferredPreviewGeneration != self.previewGeneration {
            self.clearDeferredRestoreWithoutApplying()
            return
        }
        self.deferredPreviewGeneration = nil
        self.restoreNow()
    }

    private func clearDeferredRestoreWithoutApplying() {
        self.deferredRecordingIds.removeAll()
        self.deferredPreviewGeneration = nil
    }

    private func restoreNow() {
        guard let snap = self.snapshot else { return }
        self.snapshot = nil
        self.snapshotPreviewGeneration = nil
        snap.apply()
    }
}
