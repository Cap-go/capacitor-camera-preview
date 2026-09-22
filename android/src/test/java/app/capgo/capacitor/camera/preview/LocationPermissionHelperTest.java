package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import com.getcapacitor.PermissionState;
import org.junit.Test;

public class LocationPermissionHelperTest {

    @Test
    public void canCaptureWithExifLocationRequiresCapacitorGrantAndRuntimePermissions() {
        assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.GRANTED, true));
        assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.DENIED, true));
        assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.PROMPT, true));
        assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.GRANTED, false));
    }

    @Test
    public void capacitorGrantWithoutRuntimePermissionsFallsBackToGpsLessCapture() {
        assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.GRANTED, false));
    }
}
