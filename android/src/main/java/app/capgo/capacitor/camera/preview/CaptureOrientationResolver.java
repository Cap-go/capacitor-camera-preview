package app.capgo.capacitor.camera.preview;

/**
 * Chooses whether still capture uses on-screen preview rotation or physical device rotation.
 */
public final class CaptureOrientationResolver {

    public static final String ORIENTATION_PREVIEW = "preview";
    public static final String ORIENTATION_DEVICE = "device";

    private CaptureOrientationResolver() {}

    /**
     * @param orientationMode {@link #ORIENTATION_PREVIEW}, {@link #ORIENTATION_DEVICE}, or null/empty for preview.
     * @param displayRotation rotation matching the preview (typically {@link android.view.Display#getRotation()}).
     * @param deviceRotation rotation from the accelerometer / physical resolver.
     */
    public static int resolveRotation(String orientationMode, int displayRotation, int deviceRotation) {
        if (ORIENTATION_DEVICE.equals(orientationMode)) {
            return deviceRotation;
        }
        return displayRotation;
    }

    public static boolean usesDeviceOrientation(String orientationMode) {
        return ORIENTATION_DEVICE.equals(orientationMode);
    }
}
