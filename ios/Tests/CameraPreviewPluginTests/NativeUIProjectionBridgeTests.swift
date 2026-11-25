import WebKit
import WebViewNativeUIEngine
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
        XCTAssertTrue(NativeUIProjectionStartValidation.isMissingSelector(enabled: true, selector: "\t\n\u{000C}\r"))
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
        if !bridge.isActive {
            do {
                let projection = try NativeUIProjection(
                    webView: webView,
                    plugin: "CameraPreview",
                    projectionSelector: "#test",
                    receiveListeners: NativeUIProjection.ReceiveListeners(
                        update: ["previewAppearanceChanged"],
                        projection: NativeUIProjection.ReceiveListeners.Projection(
                            native: ["previewShown"],
                            web: [],
                            none: ["previewHidden"]
                        )
                    ),
                    view: { UIView() }
                )
                bridge.assignProjectionForTesting(projection)
            } catch {
                XCTFail("Native UI projection engine unavailable: \(error)")
            }
        }
        XCTAssertTrue(bridge.isActive, "projection bridge must be active for round-trip test")
        bridge.receive(eventName: "previewAppearanceChanged", data: [:])
        bridge.deactivate()
        XCTAssertFalse(bridge.isActive)
    }
}