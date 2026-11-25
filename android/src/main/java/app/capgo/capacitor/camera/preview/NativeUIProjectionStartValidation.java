package app.capgo.capacitor.camera.preview;

/** Shared start-option validation for native UI projection. */
public final class NativeUIProjectionStartValidation {

    public static final String MISSING_SELECTOR_MESSAGE = "nativeUIProjectionSelector is required when nativeUIProjection is true";

    private NativeUIProjectionStartValidation() {}

    public static boolean isMissingSelector(boolean nativeUIProjection, String nativeUIProjectionSelector) {
        return nativeUIProjection && (nativeUIProjectionSelector == null || nativeUIProjectionSelector.trim().isEmpty());
    }
}
