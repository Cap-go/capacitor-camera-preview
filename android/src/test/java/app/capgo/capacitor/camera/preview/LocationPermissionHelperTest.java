package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import androidx.core.app.ActivityCompat;
import com.getcapacitor.PermissionState;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.MockedStatic;
import org.mockito.Mockito;
import org.mockito.junit.MockitoJUnitRunner;

@RunWith(MockitoJUnitRunner.class)
public class LocationPermissionHelperTest {

    @Test
    public void canCaptureWithExifLocationRequiresCapacitorGrantAndRuntimePermissions() {
        Context context = mock(Context.class);

        try (MockedStatic<ActivityCompat> activityCompat = Mockito.mockStatic(ActivityCompat.class)) {
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION))
                .thenReturn(PackageManager.PERMISSION_GRANTED);
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION))
                .thenReturn(PackageManager.PERMISSION_GRANTED);

            assertTrue(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.GRANTED, context));
            assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.DENIED, context));
            assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.PROMPT, context));
        }
    }

    @Test
    public void hasRuntimeLocationPermissionsRequiresFineAndCoarse() {
        Context context = mock(Context.class);

        try (MockedStatic<ActivityCompat> activityCompat = Mockito.mockStatic(ActivityCompat.class)) {
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION))
                .thenReturn(PackageManager.PERMISSION_GRANTED);
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION))
                .thenReturn(PackageManager.PERMISSION_DENIED);

            assertFalse(LocationPermissionHelper.hasRuntimeLocationPermissions(context));
        }
    }

    @Test
    public void capacitorGrantWithoutRuntimePermissionsFallsBackToGpsLessCapture() {
        Context context = mock(Context.class);

        try (MockedStatic<ActivityCompat> activityCompat = Mockito.mockStatic(ActivityCompat.class)) {
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION))
                .thenReturn(PackageManager.PERMISSION_DENIED);
            activityCompat
                .when(() -> ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION))
                .thenReturn(PackageManager.PERMISSION_DENIED);

            assertFalse(LocationPermissionHelper.canCaptureWithExifLocation(PermissionState.GRANTED, context));
        }
    }
}
