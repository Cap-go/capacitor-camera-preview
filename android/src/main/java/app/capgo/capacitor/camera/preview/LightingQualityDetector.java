package app.capgo.capacitor.camera.preview;

import androidx.camera.core.ImageProxy;
import java.nio.ByteBuffer;

/**
 * Utility class to assess lighting quality from camera frames.
 * Analyzes brightness levels and provides guidance for better lighting.
 */
public class LightingQualityDetector {

    // Default thresholds for lighting quality
    private static final double DEFAULT_MIN_BRIGHTNESS = 0.25; // Too dark below 25%
    private static final double DEFAULT_MAX_BRIGHTNESS = 0.85; // Too bright above 85%
    private static final double DEFAULT_OPTIMAL_MIN = 0.35;
    private static final double DEFAULT_OPTIMAL_MAX = 0.75;

    private final double minBrightness;
    private final double maxBrightness;
    private final double optimalMin;
    private final double optimalMax;

    /**
     * Create detector with default thresholds
     */
    public LightingQualityDetector() {
        this(DEFAULT_MIN_BRIGHTNESS, DEFAULT_MAX_BRIGHTNESS, DEFAULT_OPTIMAL_MIN, DEFAULT_OPTIMAL_MAX);
    }

    /**
     * Create detector with custom thresholds
     */
    public LightingQualityDetector(double minBrightness, double maxBrightness, double optimalMin, double optimalMax) {
        this.minBrightness = minBrightness;
        this.maxBrightness = maxBrightness;
        this.optimalMin = optimalMin;
        this.optimalMax = optimalMax;
    }

    /**
     * Analyze lighting quality from camera frame
     *
     * @param image Camera frame to analyze
     * @return Lighting quality result with feedback
     */
    public LightingResult analyzeLighting(ImageProxy image) {
        // Calculate average brightness from Y plane (luminance)
        double brightness = calculateBrightness(image);

        LightingResult result = new LightingResult();
        result.brightnessLevel = brightness;

        // Assess lighting quality
        if (brightness < minBrightness) {
            result.isGoodLighting = false;
            result.isTooDark = true;
            result.isTooBright = false;
            result.feedback = "Move to a brighter area";
        } else if (brightness > maxBrightness) {
            result.isGoodLighting = false;
            result.isTooDark = false;
            result.isTooBright = true;
            result.feedback = "Reduce lighting or move to shade";
        } else if (brightness < optimalMin || brightness > optimalMax) {
            result.isGoodLighting = true; // Acceptable but not optimal
            result.isTooDark = false;
            result.isTooBright = false;
            result.feedback = brightness < optimalMin
                ? "Lighting acceptable, but brighter is better"
                : "Lighting acceptable, but dimmer is better";
        } else {
            result.isGoodLighting = true;
            result.isTooDark = false;
            result.isTooBright = false;
            result.feedback = "Lighting is good";
        }

        return result;
    }

    /**
     * Calculate average brightness from Y plane (luminance)
     * Returns value from 0.0 (black) to 1.0 (white)
     */
    private double calculateBrightness(ImageProxy image) {
        @androidx.camera.core.ExperimentalGetImage
        android.media.Image mediaImage = image.getImage();
        if (mediaImage == null) {
            return 0.5; // Default to medium brightness if can't access
        }

        // Get Y plane (luminance) - this is the brightness component
        android.media.Image.Plane yPlane = mediaImage.getPlanes()[0];
        ByteBuffer yBuffer = yPlane.getBuffer();
        int yRowStride = yPlane.getRowStride();
        int yPixelStride = yPlane.getPixelStride();

        int width = image.getWidth();
        int height = image.getHeight();

        // Sample every 8th pixel for performance
        int sampleSize = 8;
        long sum = 0;
        int count = 0;

        for (int y = 0; y < height; y += sampleSize) {
            for (int x = 0; x < width; x += sampleSize) {
                int index = y * yRowStride + x * yPixelStride;
                if (index < yBuffer.capacity()) {
                    int luminance = yBuffer.get(index) & 0xFF; // Convert to 0-255
                    sum += luminance;
                    count++;
                }
            }
        }

        if (count == 0) {
            return 0.5; // Default
        }

        // Return normalized brightness (0.0 - 1.0)
        double avgBrightness = (double) sum / count / 255.0;
        return avgBrightness;
    }

    /**
     * Result of lighting quality analysis
     */
    public static class LightingResult {

        public boolean isGoodLighting = false;
        public double brightnessLevel = 0.0;
        public boolean isTooDark = false;
        public boolean isTooBright = false;
        public String feedback = "";

        /**
         * Get recommended exposure compensation adjustment
         * @return Suggested EV adjustment (-2.0 to +2.0)
         */
        public float getRecommendedExposureCompensation() {
            if (isTooDark) {
                // Increase exposure for dark scenes
                return (float) Math.min(2.0, (0.4 - brightnessLevel) * 3.0);
            } else if (isTooBright) {
                // Decrease exposure for bright scenes
                return (float) Math.max(-2.0, (0.7 - brightnessLevel) * 3.0);
            }
            return 0.0f; // No adjustment needed
        }
    }
}
