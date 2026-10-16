package app.capgo.capacitor.camera.preview;

import android.view.Surface;

/**
 * Resolves device physical rotation from gravity (accelerometer) for photo and video capture.
 * When the device is near flat, x/y gravity is noisy; keep the last reliable rotation or UI fallback.
 */
final class PhysicalOrientationResolver {

    /** |z| above this means gravity mostly points through the screen (camera toward table or ceiling). */
    static final float FLAT_GRAVITY_Z_THRESHOLD = 0.75f;
    /** Below this, horizontal gravity is too weak to infer portrait vs landscape reliably. */
    static final float MIN_HORIZONTAL_GRAVITY = 0.35f;
    /** When |x| and |y| are within this margin, do not flip between landscape and portrait. */
    static final float AXIS_DECISION_MARGIN = 0.12f;

    static final class Result {

        final int rotation;
        /** True when rotation came from a strong gravity signal (safe to remember for hysteresis). */
        final boolean reliable;

        Result(int rotation, boolean reliable) {
            this.rotation = rotation;
            this.reliable = reliable;
        }
    }

    private PhysicalOrientationResolver() {}

    /**
     * @param x gravity component on x in g (divide raw m/s^2 by {@link android.hardware.SensorManager#GRAVITY_EARTH})
     * @param y gravity component on y in g
     * @param z gravity component on z in g
     * @param lastReliableRotation {@link Surface#ROTATION_0} etc., or -1 if unknown
     * @param fallbackRotation display rotation when gravity is ambiguous
     */
    static Result resolve(float x, float y, float z, int lastReliableRotation, int fallbackRotation) {
        float absX = Math.abs(x);
        float absY = Math.abs(y);
        float absZ = Math.abs(z);
        float horizontalMax = Math.max(absX, absY);

        boolean isNearFlat = absZ >= FLAT_GRAVITY_Z_THRESHOLD || horizontalMax < MIN_HORIZONTAL_GRAVITY;
        if (isNearFlat) {
            int rotation = lastReliableRotation != -1 ? lastReliableRotation : fallbackRotation;
            return new Result(rotation, false);
        }

        if (Math.abs(absX - absY) < AXIS_DECISION_MARGIN) {
            int rotation = lastReliableRotation != -1 ? lastReliableRotation : fallbackRotation;
            return new Result(rotation, false);
        }

        int rotation;
        if (absX > absY) {
            if (x > 0) {
                rotation = Surface.ROTATION_90;
            } else {
                rotation = Surface.ROTATION_270;
            }
        } else {
            if (y > 0) {
                rotation = Surface.ROTATION_0;
            } else {
                rotation = Surface.ROTATION_180;
            }
        }
        return new Result(rotation, true);
    }
}
