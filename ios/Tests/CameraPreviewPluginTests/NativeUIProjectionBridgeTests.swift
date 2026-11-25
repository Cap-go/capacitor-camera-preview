import XCTest
@testable import CapgoCameraPreview

final class NativeUIProjectionBridgeTests: XCTestCase {
    func testInactiveByDefault() {
        let bridge = NativeUIProjectionBridge()
        XCTAssertFalse(bridge.isActive)
    }
}