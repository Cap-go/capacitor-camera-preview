package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.Manifest;
import android.app.Application;
import androidx.test.core.app.ApplicationProvider;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 31)
public class LocationPermissionHelperContextTest {

    @Test
    public void canCaptureWithExifLocationContextOverloadAllowsFineOnly() {
        Application application = (Application) ApplicationProvider.getApplicationContext();
        shadowOf(application).grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION);
        assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(application));
    }

    @Test
    public void canCaptureWithExifLocationContextOverloadAllowsCoarseOnly() {
        Application application = (Application) ApplicationProvider.getApplicationContext();
        shadowOf(application).grantPermissions(Manifest.permission.ACCESS_COARSE_LOCATION);
        assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(application));
    }

    @Test
    public void canCaptureWithExifLocationContextOverloadDeniesWhenNeitherGranted() {
        Application application = (Application) ApplicationProvider.getApplicationContext();
        assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(application));
    }
}
