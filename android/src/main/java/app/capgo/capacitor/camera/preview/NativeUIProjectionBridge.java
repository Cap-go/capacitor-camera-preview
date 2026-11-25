package app.capgo.capacitor.camera.preview;

import android.util.Log;
import android.view.View;
import android.view.Window;
import android.webkit.WebView;
import com.getcapacitor.JSObject;
import io.github.webview_native_ui.engine.NativeUIProjection;
import java.util.Collections;
import java.util.function.Supplier;

/** Optional WebView Native UI Engine registration for the camera preview surface. */
public final class NativeUIProjectionBridge {

    private static final String TAG = "CameraPreviewNUI";

    interface NativeUIProjectionSession {
        void receive(String eventName, JSObject data);

        void close();
    }

    private NativeUIProjectionSession session;

    public boolean isActive() {
        return session != null;
    }

    public void activate(Window window, WebView webView, String projectionSelector, Supplier<View> viewProvider) {
        if (session != null) {
            deactivate();
        }
        try {
            NativeUIProjection.ReceiveListeners.Projection projectionListeners = new NativeUIProjection.ReceiveListeners.Projection(
                Collections.singletonList("previewShown"),
                Collections.emptyList(),
                Collections.singletonList("previewHidden")
            );
            NativeUIProjection.ReceiveListeners receiveListeners = new NativeUIProjection.ReceiveListeners(
                Collections.singletonList("previewAppearanceChanged"),
                projectionListeners,
                Collections.emptyMap()
            );
            NativeUIProjection projection = new NativeUIProjection(
                window,
                webView,
                "CameraPreview",
                projectionSelector,
                receiveListeners,
                () -> viewProvider.get()
            );
            session = new EngineNativeUIProjectionSession(projection);
        } catch (Exception error) {
            Log.e(TAG, "Native UI projection unavailable", error);
            session = null;
        }
    }

    public void deactivate() {
        if (session != null) {
            session.close();
            session = null;
        }
    }

    public void receive(String eventName, JSObject data) {
        if (session != null) {
            session.receive(eventName, data == null ? new JSObject() : data);
        }
    }

    void assignSessionForTesting(NativeUIProjectionSession testSession) {
        if (session != null) {
            deactivate();
        }
        session = testSession;
    }

    static final class TestNativeUIProjectionSession implements NativeUIProjectionSession {

        boolean closed;

        @Override
        public void receive(String eventName, JSObject data) {}

        @Override
        public void close() {
            closed = true;
        }
    }

    private static final class EngineNativeUIProjectionSession implements NativeUIProjectionSession {

        private final NativeUIProjection projection;

        private EngineNativeUIProjectionSession(NativeUIProjection projection) {
            this.projection = projection;
        }

        @Override
        public void receive(String eventName, JSObject data) {
            projection.receive(eventName, data);
        }

        @Override
        public void close() {
            projection.close();
        }
    }
}
