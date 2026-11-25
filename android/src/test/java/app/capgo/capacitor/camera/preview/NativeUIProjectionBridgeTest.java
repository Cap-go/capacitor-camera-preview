package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.view.View;
import android.webkit.WebView;
import androidx.test.core.app.ApplicationProvider;
import com.getcapacitor.JSObject;
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
        if (bridge.isActive()) {
            bridge.receive("previewAppearanceChanged", new JSObject());
            bridge.deactivate();
            assertFalse(bridge.isActive());
        }
        bridge.deactivate();
        assertFalse(bridge.isActive());
    }
}
