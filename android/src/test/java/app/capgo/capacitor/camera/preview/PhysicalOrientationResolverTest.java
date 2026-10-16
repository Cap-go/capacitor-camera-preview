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
public class PhysicalOrientationResolverTest {

    @Test
    public void nearFlatUsesFallbackWhenNoLastReliable() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(0.04f, -0.03f, -0.99f, -1, Surface.ROTATION_0);
        assertEquals(Surface.ROTATION_0, result.rotation);
        assertFalse(result.reliable);
    }

    @Test
    public void nearFlatKeepsLastReliableRotation() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(
            0.05f,
            0.02f,
            0.92f,
            Surface.ROTATION_90,
            Surface.ROTATION_0
        );
        assertEquals(Surface.ROTATION_90, result.rotation);
        assertFalse(result.reliable);
    }

    @Test
    public void clearPortrait() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(0.08f, 0.95f, 0.15f, -1, Surface.ROTATION_0);
        assertEquals(Surface.ROTATION_0, result.rotation);
        assertTrue(result.reliable);
    }

    @Test
    public void clearLandscapeLeft() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(0.92f, 0.08f, 0.05f, -1, Surface.ROTATION_0);
        assertEquals(Surface.ROTATION_90, result.rotation);
        assertTrue(result.reliable);
    }

    @Test
    public void clearLandscapeRight() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(-0.9f, 0.1f, 0.05f, -1, Surface.ROTATION_0);
        assertEquals(Surface.ROTATION_270, result.rotation);
        assertTrue(result.reliable);
    }

    @Test
    public void upsideDownPortrait() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(0.05f, -0.94f, 0.1f, -1, Surface.ROTATION_0);
        assertEquals(Surface.ROTATION_180, result.rotation);
        assertTrue(result.reliable);
    }

    @Test
    public void ambiguousAxisUsesLastReliable() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(
            0.52f,
            -0.48f,
            0.2f,
            Surface.ROTATION_0,
            Surface.ROTATION_90
        );
        assertEquals(Surface.ROTATION_0, result.rotation);
        assertFalse(result.reliable);
    }

    @Test
    public void weakHorizontalGravityTreatedAsFlat() {
        PhysicalOrientationResolver.Result result = PhysicalOrientationResolver.resolve(
            0.12f,
            -0.18f,
            0.55f,
            Surface.ROTATION_270,
            Surface.ROTATION_0
        );
        assertEquals(Surface.ROTATION_270, result.rotation);
        assertFalse(result.reliable);
    }
}
