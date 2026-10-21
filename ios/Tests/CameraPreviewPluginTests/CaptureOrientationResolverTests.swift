import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class CaptureOrientationResolverTests: XCTestCase {
    func testDefaultsToDeviceOrientation() {
        XCTAssertEqual(
            CaptureOrientationResolver.resolveOrientation(
                mode: nil,
                previewOrientation: .portrait,
                deviceOrientation: .landscapeRight
            ),
            .landscapeRight
        )
        XCTAssertTrue(CaptureOrientationResolver.usesDeviceOrientation(mode: nil))
        XCTAssertTrue(CaptureOrientationResolver.usesDeviceOrientation(mode: "device"))
    }

    func testPreviewModeUsesPreviewOrientation() {
        XCTAssertEqual(
            CaptureOrientationResolver.resolveOrientation(
                mode: "preview",
                previewOrientation: .landscapeLeft,
                deviceOrientation: .portrait
            ),
            .landscapeLeft
        )
        XCTAssertFalse(CaptureOrientationResolver.usesDeviceOrientation(mode: "preview"))
    }
}
