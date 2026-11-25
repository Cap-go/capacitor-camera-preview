import WebKit
import XCTest
@testable import CapgoCameraPreview

final class NativeUIProjectionBridgeTests: XCTestCase {
    func testInactiveByDefault() {
        let bridge = NativeUIProjectionBridge()
        XCTAssertFalse(bridge.isActive)
    }

    func testReceiveWhenInactiveIsNoOp() {
        let bridge = NativeUIProjectionBridge()
        bridge.receive(eventName: "previewAppearanceChanged", data: nil)
        XCTAssertFalse(bridge.isActive)
    }

    func testMissingSelectorValidationMessageMatchesPlugin() {
        XCTAssertTrue(NativeUIProjectionStartValidation.isMissingSelector(enabled: true, selector: nil))
        XCTAssertTrue(NativeUIProjectionStartValidation.isMissingSelector(enabled: true, selector: ""))
        XCTAssertTrue(NativeUIProjectionStartValidation.isMissingSelector(enabled: true, selector: "   "))
        XCTAssertFalse(NativeUIProjectionStartValidation.isMissingSelector(enabled: true, selector: "#slot"))
        XCTAssertEqual(
            "nativeUIProjectionSelector is required when nativeUIProjection is true",
            NativeUIProjectionStartValidation.missingSelectorMessage
        )
    }

    func testActivateDeactivateRoundTripWhenEngineAvailable() {
        let bridge = NativeUIProjectionBridge()
        let webView = WKWebView(frame: .zero)
        bridge.activate(webView: webView, projectionSelector: "#test", viewProvider: { UIView() })
        if bridge.isActive {
            bridge.receive(eventName: "previewAppearanceChanged", data: [:])
            bridge.deactivate()
            XCTAssertFalse(bridge.isActive)
        }
        bridge.deactivate()
        XCTAssertFalse(bridge.isActive)
    }
}