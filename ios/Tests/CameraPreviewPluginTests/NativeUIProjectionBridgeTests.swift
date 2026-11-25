import XCTest
@testable import CapgoCameraPreview

final class NativeUIProjectionBridgeTests: XCTestCase {
    func testInactiveByDefault() {
        let bridge = NativeUIProjectionBridge()
        XCTAssertFalse(bridge.isActive)
    }

    func testReceiveWithoutActivateDoesNotCrash() {
        let bridge = NativeUIProjectionBridge()
        bridge.receive(eventName: "previewAppearanceChanged", data: nil)
        XCTAssertFalse(bridge.isActive)
    }
}