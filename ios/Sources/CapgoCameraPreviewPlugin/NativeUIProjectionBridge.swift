import Capacitor
import UIKit
import WebKit
import WebViewNativeUIEngine

/// Optional WebView Native UI Engine registration for the camera preview surface.
final class NativeUIProjectionBridge {
    private var projection: NativeUIProjection?

    var isActive: Bool {
        projection != nil
    }

    func activate(
        webView: WKWebView?,
        projectionSelector: String,
        viewProvider: @escaping () -> UIView?
    ) {
        if projection != nil {
            deactivate()
        }
        do {
            projection = try NativeUIProjection(
                webView: webView,
                plugin: "CameraPreview",
                projectionSelector: projectionSelector,
                receiveListeners: NativeUIProjection.ReceiveListeners(
                    update: ["previewAppearanceChanged"],
                    projection: NativeUIProjection.ReceiveListeners.Projection(
                        native: ["previewShown"],
                        web: [],
                        none: ["previewHidden"]
                    )
                ),
                view: viewProvider
            )
        } catch {
            CAPLog.print("[CameraPreview] Native UI projection unavailable: \(error)")
        }
    }

    func deactivate() {
        projection?.destroy()
        projection = nil
    }

    func receive(eventName: String, data: [String: Any]?) {
        projection?.receive(eventName, data: data)
    }

    internal func assignProjectionForTesting(_ projection: NativeUIProjection?) {
        if self.projection != nil {
            deactivate()
        }
        self.projection = projection
    }
}