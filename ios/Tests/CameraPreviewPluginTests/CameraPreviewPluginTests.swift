import XCTest
@testable import CapgoCameraPreview

class CameraPreviewTests: XCTestCase {
    func testPluginVersion() {
        // Basic test to verify the plugin module loads correctly
        let plugin = CameraPreview()
        XCTAssertNotNil(plugin)
    }
}
