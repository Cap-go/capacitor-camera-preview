import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class ApplicationAudioSessionSnapshotTests: XCTestCase {
    func testSnapshotAndRestoreCategoryModeAndOptions() throws {
        let session = AVAudioSession.sharedInstance()
        let priorCategory = session.category
        let priorMode = session.mode
        let priorOptions = session.categoryOptions
        defer { try? session.setCategory(priorCategory, mode: priorMode, options: priorOptions) }

        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        let snapshot = ApplicationAudioSessionSnapshot.capture(from: session)

        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertEqual(session.mode, .videoRecording)

        XCTAssertTrue(snapshot.apply(to: session))
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .default)
        XCTAssertEqual(session.categoryOptions, [.mixWithOthers])
    }
}
