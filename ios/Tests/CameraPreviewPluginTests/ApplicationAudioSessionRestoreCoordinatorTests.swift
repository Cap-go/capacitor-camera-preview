import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class ApplicationAudioSessionRestoreCoordinatorTests: XCTestCase {
    func testRepeatedCleanupDuringRecordingKeepsDeferralUntilRecordingFinishes() {
        let coordinator = ApplicationAudioSessionRestoreCoordinator()
        coordinator.beginPreviewSession()
        coordinator.captureSnapshotIfNeeded()

        let recordingId = coordinator.beginRecording()
        coordinator.handleCleanup(isRecording: true)
        XCTAssertTrue(coordinator.isDeferredRestorePending)

        coordinator.handleCleanup(isRecording: false)
        XCTAssertTrue(coordinator.isDeferredRestorePending)

        coordinator.finishRecording(recordingId: recordingId)
        XCTAssertFalse(coordinator.isDeferredRestorePending)
    }

    func testLateRecordingCompletionDoesNotRestoreAfterNewPreview() throws {
        let session = AVAudioSession.sharedInstance()
        let priorCategory = session.category
        let priorMode = session.mode
        let priorOptions = session.categoryOptions
        defer { try? session.setCategory(priorCategory, mode: priorMode, options: priorOptions) }

        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])

        let coordinator = ApplicationAudioSessionRestoreCoordinator()
        coordinator.beginPreviewSession()
        coordinator.captureSnapshotIfNeeded()

        let recordingId = coordinator.beginRecording()
        coordinator.handleCleanup(isRecording: true)

        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        coordinator.beginPreviewSession()

        coordinator.finishRecording(recordingId: recordingId)
        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertEqual(session.mode, .videoRecording)
    }
}
