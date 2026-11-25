package app.capgo.capacitor.camera.preview;

import android.util.Log;
import android.view.View;
import android.view.Window;
import android.webkit.WebView;
import com.getcapacitor.JSObject;
import io.github.webview_native_ui.engine.NativeUIProjection;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/** Optional WebView Native UI Engine registration for the camera preview surface. */
public final class NativeUIProjectionBridge {
    private static final String TAG = "CameraPreviewNUI";
    private NativeUIProjection projection;

    public boolean isActive() {
        return projection != null;
    }

    public void activate(Window window, WebView webView, String projectionSelector, Supplier<View> viewProvider) {
        if (projection != null) {
            return;
        }
        try {
            NativeUIProjection.install(webView);
            NativeUIProjection.ReceiveListeners.Projection projectionListeners =
                new NativeUIProjection.ReceiveListeners.Projection(
                    List.of("previewShown"),
                    List.of(),
                    List.of("previewHidden")
                );
            NativeUIProjection.ReceiveListeners receiveListeners =
                new NativeUIProjection.ReceiveListeners(
                    List.of("previewAppearanceChanged"),
                    projectionListeners,
                    Map.of()
                );
            projection =
                new NativeUIProjection(
                    window,
                    webView,
                    "CameraPreview",
                    projectionSelector,
                    receiveListeners,
                    viewProvider
                );
        } catch (Exception error) {
            Log.e(TAG, "Native UI projection unavailable", error);
            projection = null;
        }
    }

    public void deactivate() {
        if (projection != null) {
            projection.close();
            projection = null;
        }
    }

    public void receive(String eventName, JSObject data) {
        if (projection != null) {
            projection.receive(eventName, data == null ? new JSObject() : data);
        }
    }
}