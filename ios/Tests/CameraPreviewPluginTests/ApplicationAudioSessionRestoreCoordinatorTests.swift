import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class ApplicationAudioSessionRestoreCoordinatorTests: XCTestCase {
    func testDoubleCleanupWhileRecordingActiveDefersSingleRestoreUntilRecordingFinishes() throws {
        let session = AVAudioSession.sharedInstance()
        let priorCategory = session.category
        let priorMode = session.mode
        let priorOptions = session.categoryOptions
        defer { try? session.setCategory(priorCategory, mode: priorMode, options: priorOptions) }

        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])

        let coordinator = ApplicationAudioSessionRestoreCoordinator()
        coordinator.beginPreviewSession()
        coordinator.captureSnapshotIfNeeded()

        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])

        let recordingId = coordinator.beginRecording()
        coordinator.handleCleanup(isRecording: true)
        XCTAssertTrue(coordinator.isDeferredRestorePending)

        coordinator.handleCleanup(isRecording: true)
        XCTAssertTrue(coordinator.isDeferredRestorePending)
        XCTAssertEqual(session.category, .playAndRecord)

        coordinator.finishRecording(recordingId: recordingId)
        XCTAssertFalse(coordinator.isDeferredRestorePending)
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .default)
    }

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

    func testCleanupDefersWhenPendingRecordingIdProvidedAfterOutputStops() throws {
        let session = AVAudioSession.sharedInstance()
        let priorCategory = session.category
        let priorMode = session.mode
        let priorOptions = session.categoryOptions
        defer { try? session.setCategory(priorCategory, mode: priorMode, options: priorOptions) }

        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])

        let coordinator = ApplicationAudioSessionRestoreCoordinator()
        coordinator.beginPreviewSession()
        coordinator.captureSnapshotIfNeeded()

        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])

        let recordingId = coordinator.beginRecording()
        coordinator.handleCleanup(isRecording: false, pendingRecordingIds: [recordingId])
        XCTAssertTrue(coordinator.isDeferredRestorePending)
        XCTAssertEqual(session.category, .playAndRecord)

        coordinator.finishRecording(recordingId: recordingId)
        XCTAssertEqual(session.category, .playback)
    }

    func testNewPreviewBeforeRecordingCompletionSkipsLateRestore() throws {
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

    func testNewPreviewBeforeAsyncRecordingCompletionSkipsLateRestore() throws {
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

        coordinator.finishRecordingAsync(recordingId: recordingId)
        coordinator.syncWithQueueForTesting()

        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertEqual(session.mode, .videoRecording)
    }

    func testCaptureSnapshotDoesNotReplaceExistingBaselineOnNewPreview() throws {
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
        coordinator.captureSnapshotIfNeeded()

        coordinator.finishRecording(recordingId: recordingId)
        coordinator.handleCleanup(isRecording: false)
        XCTAssertEqual(session.category, .playback)
    }

    func testBeginPreviewDuringDeferredRestoreKeepsSnapshotForLaterCleanup() throws {
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

        coordinator.handleCleanup(isRecording: false)
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .default)
    }
}
