package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.view.Surface;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(manifest = Config.NONE, sdk = 28)
public class CaptureOrientationResolverTest {

    @Test
    public void defaultsToDeviceRotation() {
        assertEquals(Surface.ROTATION_90, CaptureOrientationResolver.resolveRotation(null, Surface.ROTATION_0, Surface.ROTATION_90));
        assertEquals(Surface.ROTATION_90, CaptureOrientationResolver.resolveRotation("", Surface.ROTATION_0, Surface.ROTATION_90));
        assertEquals(Surface.ROTATION_90, CaptureOrientationResolver.resolveRotation("device", Surface.ROTATION_0, Surface.ROTATION_90));
        assertTrue(CaptureOrientationResolver.usesDeviceOrientation(null));
        assertTrue(CaptureOrientationResolver.usesDeviceOrientation("device"));
    }

    @Test
    public void previewModeUsesDisplayRotation() {
        assertEquals(Surface.ROTATION_270, CaptureOrientationResolver.resolveRotation("preview", Surface.ROTATION_270, Surface.ROTATION_0));
        assertFalse(CaptureOrientationResolver.usesDeviceOrientation("preview"));
    }
}
