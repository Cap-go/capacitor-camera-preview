package app.capgo.capacitor.camera.preview;

import android.util.Size;
import androidx.annotation.Nullable;
import androidx.exifinterface.media.ExifInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.json.JSONObject;

/**
 * Package-private helpers for Android still capture resolution and fast-path decisions.
 */
final class CaptureResolutionSupport {

    /** Matches {@link CameraPreview} default capture quality and ImageCapture JPEG quality. */
    static final int DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY = 85;

    private CaptureResolutionSupport() {}

    static final class CaptureResolutionParseResult {

        @Nullable
        final Integer width;

        @Nullable
        final Integer height;

        @Nullable
        final String errorMessage;

        private CaptureResolutionParseResult(@Nullable Integer width, @Nullable Integer height, @Nullable String errorMessage) {
            this.width = width;
            this.height = height;
            this.errorMessage = errorMessage;
        }

        static CaptureResolutionParseResult success(@Nullable Integer width, @Nullable Integer height) {
            return new CaptureResolutionParseResult(width, height, null);
        }

        static CaptureResolutionParseResult error(String message) {
            return new CaptureResolutionParseResult(null, null, message);
        }

        boolean isError() {
            return errorMessage != null;
        }
    }

    @Nullable
    static CaptureResolutionParseResult parseStartCaptureResolution(@Nullable Object captureResolutionObject) {
        if (captureResolutionObject == null) {
            return CaptureResolutionParseResult.success(null, null);
        }
        if (!(captureResolutionObject instanceof JSONObject)) {
            return CaptureResolutionParseResult.error("captureResolution must be an object with width and height");
        }
        JSONObject captureResolution = (JSONObject) captureResolutionObject;
        if (!captureResolution.has("width") || !captureResolution.has("height")) {
            return CaptureResolutionParseResult.error("captureResolution requires both width and height");
        }
        Integer captureWidth = parsePositivePixelDimension(captureResolution.opt("width"));
        Integer captureHeight = parsePositivePixelDimension(captureResolution.opt("height"));
        if (captureWidth == null || captureHeight == null) {
            return CaptureResolutionParseResult.error("captureResolution width and height must be positive");
        }
        return CaptureResolutionParseResult.success(captureWidth, captureHeight);
    }

    @Nullable
    static Integer parsePositivePixelDimension(@Nullable Object value) {
        if (value == null || value == JSONObject.NULL) {
            return null;
        }
        if (value instanceof Number) {
            double numeric = ((Number) value).doubleValue();
            if (Double.isNaN(numeric) || Double.isInfinite(numeric) || numeric <= 0) {
                return null;
            }
            long rounded = (long) numeric;
            if (rounded != (long) numeric) {
                return null;
            }
            if (rounded > Integer.MAX_VALUE) {
                return null;
            }
            return (int) rounded;
        }
        if (value instanceof String) {
            String trimmed = ((String) value).trim();
            if (trimmed.isEmpty()) {
                return null;
            }
            try {
                double numeric = Double.parseDouble(trimmed);
                if (Double.isNaN(numeric) || Double.isInfinite(numeric) || numeric <= 0) {
                    return null;
                }
                long rounded = (long) numeric;
                if (rounded != (long) numeric) {
                    return null;
                }
                if (rounded > Integer.MAX_VALUE) {
                    return null;
                }
                return (int) rounded;
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }

    static Size normalizedCaptureTargetResolution(int configuredWidth, int configuredHeight) {
        return new Size(Math.max(configuredWidth, configuredHeight), Math.min(configuredWidth, configuredHeight));
    }

    static List<Size> filterCaptureResolutionCandidates(@Nullable List<Size> supportedSizes, int maxCaptureLongEdge) {
        if (supportedSizes == null || supportedSizes.isEmpty()) {
            return supportedSizes;
        }

        List<Size> cappedSizes = new ArrayList<>();
        for (Size size : supportedSizes) {
            int longEdge = Math.max(size.getWidth(), size.getHeight());
            if (longEdge <= maxCaptureLongEdge) {
                cappedSizes.add(size);
            }
        }

        if (!cappedSizes.isEmpty()) {
            return cappedSizes;
        }

        Size smallest = supportedSizes.get(0);
        int smallestLongEdge = Math.max(smallest.getWidth(), smallest.getHeight());
        for (Size size : supportedSizes) {
            int longEdge = Math.max(size.getWidth(), size.getHeight());
            if (longEdge < smallestLongEdge) {
                smallest = size;
                smallestLongEdge = longEdge;
            }
        }
        return Collections.singletonList(smallest);
    }

    static boolean captureRequiresSoftwareTransform(
        @Nullable Integer width,
        @Nullable Integer height,
        boolean embedTimestamp,
        boolean embedLocation,
        boolean mirrorFrontCamera,
        boolean shouldMirrorFrontCamera
    ) {
        return width != null || height != null || embedTimestamp || embedLocation || (mirrorFrontCamera && shouldMirrorFrontCamera);
    }

    static boolean canUseViewportCaptureFastPath(
        int requestedQuality,
        int imageCaptureJpegQuality,
        boolean requiresSoftwareTransform,
        boolean viewportCropCurrent,
        int exifOrientation
    ) {
        return (
            requestedQuality == imageCaptureJpegQuality &&
            !requiresSoftwareTransform &&
            viewportCropCurrent &&
            exifOrientation == ExifInterface.ORIENTATION_NORMAL
        );
    }
}
