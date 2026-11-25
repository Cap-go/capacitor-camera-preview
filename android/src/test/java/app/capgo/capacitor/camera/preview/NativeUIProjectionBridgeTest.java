package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import android.app.Activity;
import android.view.View;
import android.webkit.WebView;
import androidx.test.core.app.ApplicationProvider;
import com.getcapacitor.JSObject;
import io.github.webview_native_ui.engine.NativeUIProjection;
import java.util.Collections;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class NativeUIProjectionBridgeTest {

    @Test
    public void inactiveByDefault() {
        NativeUIProjectionBridge bridge = new NativeUIProjectionBridge();
        assertFalse(bridge.isActive());
    }

    @Test
    public void receiveWhenInactiveIsNoOp() {
        NativeUIProjectionBridge bridge = new NativeUIProjectionBridge();
        bridge.receive("previewAppearanceChanged", new JSObject());
        assertFalse(bridge.isActive());
    }

    @Test
    public void missingSelectorValidationMessageMatchesPlugin() {
        assertTrue(NativeUIProjectionStartValidation.isMissingSelector(true, null));
        assertTrue(NativeUIProjectionStartValidation.isMissingSelector(true, ""));
        assertTrue(NativeUIProjectionStartValidation.isMissingSelector(true, "   "));
        assertTrue(NativeUIProjectionStartValidation.isMissingSelector(true, "\t\n\f\r"));
        assertFalse(NativeUIProjectionStartValidation.isMissingSelector(true, "#slot"));
        assertEquals(
            "nativeUIProjectionSelector is required when nativeUIProjection is true",
            NativeUIProjectionStartValidation.MISSING_SELECTOR_MESSAGE
        );
    }

    @Test
    public void activateDeactivateRoundTripWhenEngineAvailable() {
        Activity activity = Robolectric.buildActivity(Activity.class).setup().get();
        WebView webView = new WebView(ApplicationProvider.getApplicationContext());
        View preview = new View(ApplicationProvider.getApplicationContext());
        NativeUIProjectionBridge bridge = new NativeUIProjectionBridge();
        bridge.activate(activity.getWindow(), webView, "#slot", () -> preview);
        if (!bridge.isActive()) {
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
                    activity.getWindow(),
                    webView,
                    "CameraPreview",
                    "#slot",
                    receiveListeners,
                    () -> preview
                );
                bridge.assignProjectionForTesting(projection);
            } catch (Exception error) {
                fail("Native UI projection engine unavailable: " + error.getMessage());
            }
        }
        assertTrue("projection bridge must be active for round-trip test", bridge.isActive());
        bridge.receive("previewAppearanceChanged", new JSObject());
        bridge.deactivate();
        assertFalse(bridge.isActive());
    }
}
