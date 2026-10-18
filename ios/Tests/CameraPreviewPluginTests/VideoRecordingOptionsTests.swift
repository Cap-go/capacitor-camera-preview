import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class VideoRecordingOptionsTests: XCTestCase {
    func testParseVideoBitrateAcceptsPositiveIntegers() {
        XCTAssertEqual(VideoRecordingOptions.parseVideoBitrate(from: 2_500_000), 2_500_000)
        XCTAssertEqual(VideoRecordingOptions.parseVideoBitrate(from: 900_000.0), 900_000)
        XCTAssertEqual(VideoRecordingOptions.parseVideoBitrate(from: "1500000"), 1_500_000)
    }

    func testParseVideoBitrateIgnoresInvalidValues() {
        XCTAssertNil(VideoRecordingOptions.parseVideoBitrate(from: nil))
        XCTAssertNil(VideoRecordingOptions.parseVideoBitrate(from: 0))
        XCTAssertNil(VideoRecordingOptions.parseVideoBitrate(from: -1))
        XCTAssertNil(VideoRecordingOptions.parseVideoBitrate(from: "not-a-number"))
    }

    func testMovieFileOutputSettingsIncludesBitrateWhenSet() {
        let settings = VideoRecordingOptions.movieFileOutputSettings(codecType: .h264, videoBitrate: 1_000_000)
        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .h264)
        let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoAverageBitRateKey] as? Int, 1_000_000)
    }

    func testMovieFileOutputSettingsOmitsBitrateWhenUnset() {
        let settings = VideoRecordingOptions.movieFileOutputSettings(codecType: .h264, videoBitrate: nil)
        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .h264)
        XCTAssertNil(settings[AVVideoCompressionPropertiesKey])
    }
}
