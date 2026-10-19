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
            if (!Double.isFinite(value) || value <= 0D || value > Integer.MAX_VALUE || value != Math.floor(value)) {
                return null;
            }
            return (int) value;
        }
        if (raw instanceof String) {
            try {
                double value = Double.parseDouble((String) raw);
                if (!Double.isFinite(value) || value <= 0D || value > Integer.MAX_VALUE || value != Math.floor(value)) {
                    return null;
                }
                return (int) value;
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }

    /**
     * Bitrate for a single {@code startRecordVideo} call: a valid per-call override, otherwise the preview
     * bitrate from {@code start()} (may be {@code null} for the platform default).
     */
    public static Integer resolveRecordingVideoBitrate(Integer previewBitrate, JSONObject data) {
        if (data == null || !data.has("videoBitrate") || data.isNull("videoBitrate")) {
            return previewBitrate;
        }
        Integer parsed = parseVideoBitrate(data);
        return parsed != null ? parsed : previewBitrate;
    }
}
