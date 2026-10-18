import AVFoundation
import XCTest
@testable import CapgoCameraPreview

final class CaptureOrientationResolverTests: XCTestCase {
    func testDefaultsToPreviewOrientation() {
        XCTAssertEqual(
            CaptureOrientationResolver.resolveOrientation(
                mode: nil,
                previewOrientation: .portrait,
                deviceOrientation: .landscapeRight
            ),
            .portrait
        )
        XCTAssertEqual(
            CaptureOrientationResolver.resolveOrientation(
                mode: "preview",
                previewOrientation: .landscapeLeft,
                deviceOrientation: .portrait
            ),
            .landscapeLeft
        )
    }

    func testDeviceModeUsesPhysicalOrientation() {
        XCTAssertTrue(CaptureOrientationResolver.usesDeviceOrientation(mode: "device"))
        XCTAssertEqual(
            CaptureOrientationResolver.resolveOrientation(
                mode: "device",
                previewOrientation: .portrait,
                deviceOrientation: .landscapeRight
            ),
            .landscapeRight
        )
    }
}
