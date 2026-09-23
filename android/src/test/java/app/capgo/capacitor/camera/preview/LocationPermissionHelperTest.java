package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import androidx.core.app.ActivityCompat;
import org.junit.Test;
import org.mockito.MockedStatic;

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

    @Test
    public void canCaptureWithExifLocationContextOverloadAllowsFineOnly() {
        Context context = mock(Context.class);
        withMockedPermissions(context, PackageManager.PERMISSION_GRANTED, PackageManager.PERMISSION_DENIED, () ->
            assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(context))
        );
    }

    @Test
    public void canCaptureWithExifLocationContextOverloadAllowsCoarseOnly() {
        Context context = mock(Context.class);
        withMockedPermissions(context, PackageManager.PERMISSION_DENIED, PackageManager.PERMISSION_GRANTED, () ->
            assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(context))
        );
    }

    @Test
    public void canCaptureWithExifLocationContextOverloadDeniesWhenNeitherGranted() {
        Context context = mock(Context.class);
        withMockedPermissions(context, PackageManager.PERMISSION_DENIED, PackageManager.PERMISSION_DENIED, () ->
            assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(context))
        );
    }

    private static void withMockedPermissions(Context context, int finePermission, int coarsePermission, Runnable assertion) {
        try (MockedStatic<ActivityCompat> activityCompat = mockStatic(ActivityCompat.class)) {
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION))
                .thenReturn(finePermission);
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION))
                .thenReturn(coarsePermission);
            assertion.run();
        }
    }
}
