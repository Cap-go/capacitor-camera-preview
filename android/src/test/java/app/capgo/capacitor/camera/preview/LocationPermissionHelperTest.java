package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class LocationPermissionHelperTest {

    @Test
    public void canCaptureWithExifLocationUsesRuntimePermissionOnly() {
        assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(true));
        assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(false));
    }

    @Test
    public void runtimeAccessAllowsExifCaptureRegardlessOfCapacitorCache() {
        assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(true));
    }

    @Test
    public void missingRuntimePermissionsFallsBackToGpsLessCapture() {
        assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(false));
    }
}
