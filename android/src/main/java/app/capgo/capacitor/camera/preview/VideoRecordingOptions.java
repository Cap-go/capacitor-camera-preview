package app.capgo.capacitor.camera.preview;

import org.json.JSONObject;

/**
 * Helpers for parsing video recording options from plugin call payloads.
 */
public final class VideoRecordingOptions {

    private VideoRecordingOptions() {}

    /**
     * Parses {@code videoBitrate} from a plugin options object.
     * Returns {@code null} when omitted, null, non-positive, or not a finite positive integer.
     */
    public static Integer parseVideoBitrate(JSONObject data) {
        if (data == null || !data.has("videoBitrate") || data.isNull("videoBitrate")) {
            return null;
        }
        Object raw = data.opt("videoBitrate");
        if (raw instanceof Number) {
            double value = ((Number) raw).doubleValue();
            if (!Double.isFinite(value) || value <= 0D || value > Integer.MAX_VALUE) {
                return null;
            }
            return (int) Math.round(value);
        }
        if (raw instanceof String) {
            try {
                double value = Double.parseDouble((String) raw);
                if (!Double.isFinite(value) || value <= 0D || value > Integer.MAX_VALUE) {
                    return null;
                }
                return (int) Math.round(value);
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }
}
