package app.capgo.capacitor.camera.preview;

/** Shared start-option validation for native UI projection. */
public final class NativeUIProjectionStartValidation {

    public static final String MISSING_SELECTOR_MESSAGE = "nativeUIProjectionSelector is required when nativeUIProjection is true";

    private NativeUIProjectionStartValidation() {}

    public static boolean isMissingSelector(boolean nativeUIProjection, String nativeUIProjectionSelector) {
        return nativeUIProjection && isBlankCssWhitespace(nativeUIProjectionSelector);
    }

    private static boolean isBlankCssWhitespace(String value) {
        if (value == null || value.isEmpty()) {
            return true;
        }
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c != ' ' && c != '\t' && c != '\n' && c != '\f' && c != '\r') {
                return false;
            }
        }
        return true;
    }
}
