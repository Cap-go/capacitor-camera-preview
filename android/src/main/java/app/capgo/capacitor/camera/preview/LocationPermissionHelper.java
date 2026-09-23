package app.capgo.capacitor.camera.preview;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import androidx.core.app.ActivityCompat;

/**
 * Runtime location permission checks for EXIF capture.
 * <p>
 * Capacitor's cached {@link PermissionState} can diverge from the OS grant state; always
 * verify both before requesting location and before settling a capture call.
 */
public final class LocationPermissionHelper {

    private LocationPermissionHelper() {}

    public static boolean hasRuntimeLocationPermissions(Context context) {
        return (
            ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        );
    }

    public static boolean canCaptureWithExifLocation(Context context) {
        return canCaptureWithExifLocation(hasRuntimeLocationPermissions(context));
    }

    static boolean canCaptureWithExifLocation(boolean hasRuntimeLocationPermissions) {
        return hasRuntimeLocationPermissions;
    }
}
