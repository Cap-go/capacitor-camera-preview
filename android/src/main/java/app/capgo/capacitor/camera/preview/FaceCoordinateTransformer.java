package app.capgo.capacitor.camera.preview;

import android.graphics.PointF;
import android.graphics.Rect;
import android.util.Log;
import androidx.annotation.NonNull;

/**
 * Utility class to transform face detection coordinates from camera frame space
 * to preview view space, accounting for aspect ratio differences, letterboxing,
 * pillarboxing, and device orientation.
 */
public class FaceCoordinateTransformer {

    private static final String TAG = "FaceCoordTransformer";

    private final int frameWidth;
    private final int frameHeight;
    private final int previewWidth;
    private final int previewHeight;
    private final int rotation; // 0, 90, 180, 270

    /**
     * Creates a coordinate transformer
     *
     * @param frameWidth Width of camera frame in pixels
     * @param frameHeight Height of camera frame in pixels
     * @param previewWidth Width of preview view in pixels
     * @param previewHeight Height of preview view in pixels
     * @param rotation Rotation in degrees (0, 90, 180, 270)
     */
    public FaceCoordinateTransformer(int frameWidth, int frameHeight, int previewWidth, int previewHeight, int rotation) {
        this.frameWidth = frameWidth;
        this.frameHeight = frameHeight;
        this.previewWidth = previewWidth;
        this.previewHeight = previewHeight;
        this.rotation = rotation;

        Log.d(
            TAG,
            String.format(
                "Transformer created: frame=%dx%d, preview=%dx%d, rotation=%d",
                frameWidth,
                frameHeight,
                previewWidth,
                previewHeight,
                rotation
            )
        );
    }

    /**
     * Transform a bounding box from frame coordinates to normalized preview coordinates (0-1)
     *
     * @param frameBounds Bounding box in frame pixel coordinates
     * @return Normalized bounds (x, y, width, height) in range 0-1 relative to preview
     */
    @NonNull
    public NormalizedRect transformBounds(@NonNull Rect frameBounds) {
        // Step 1: Normalize to frame (0-1)
        double frameX = (double) frameBounds.left / frameWidth;
        double frameY = (double) frameBounds.top / frameHeight;
        double frameW = (double) frameBounds.width() / frameWidth;
        double frameH = (double) frameBounds.height() / frameHeight;

        // Step 2: Apply rotation transformation
        double rotatedX, rotatedY, rotatedW, rotatedH;
        switch (rotation) {
            case 90:
                // 90° clockwise: (x, y) -> (1-y-h, x)
                rotatedX = 1.0 - frameY - frameH;
                rotatedY = frameX;
                rotatedW = frameH;
                rotatedH = frameW;
                break;
            case 180:
                // 180°: (x, y) -> (1-x-w, 1-y-h)
                rotatedX = 1.0 - frameX - frameW;
                rotatedY = 1.0 - frameY - frameH;
                rotatedW = frameW;
                rotatedH = frameH;
                break;
            case 270:
                // 270° clockwise: (x, y) -> (y, 1-x-w)
                rotatedX = frameY;
                rotatedY = 1.0 - frameX - frameW;
                rotatedW = frameH;
                rotatedH = frameW;
                break;
            default: // 0 degrees
                rotatedX = frameX;
                rotatedY = frameY;
                rotatedW = frameW;
                rotatedH = frameH;
                break;
        }

        // Step 3: Calculate aspect ratio differences and scaling
        double frameAspect = (double) frameWidth / frameHeight;
        double previewAspect = (double) previewWidth / previewHeight;

        // Account for rotation swapping dimensions
        if (rotation == 90 || rotation == 270) {
            frameAspect = (double) frameHeight / frameWidth;
        }

        double scaleX, scaleY, offsetX, offsetY;

        if (frameAspect > previewAspect) {
            // Frame is wider - pillarboxing (black bars on left/right)
            scaleY = 1.0;
            scaleX = previewAspect / frameAspect;
            offsetX = (1.0 - scaleX) / 2.0;
            offsetY = 0.0;
        } else {
            // Frame is taller - letterboxing (black bars on top/bottom)
            scaleX = 1.0;
            scaleY = frameAspect / previewAspect;
            offsetX = 0.0;
            offsetY = (1.0 - scaleY) / 2.0;
        }

        // Step 4: Apply scaling and offset
        double finalX = rotatedX * scaleX + offsetX;
        double finalY = rotatedY * scaleY + offsetY;
        double finalW = rotatedW * scaleX;
        double finalH = rotatedH * scaleY;

        return new NormalizedRect(finalX, finalY, finalW, finalH);
    }

    /**
     * Transform a point from frame coordinates to normalized preview coordinates (0-1)
     *
     * @param framePoint Point in frame pixel coordinates
     * @return Normalized point (x, y) in range 0-1 relative to preview
     */
    @NonNull
    public NormalizedPoint transformPoint(@NonNull PointF framePoint) {
        // Use the same transformation as bounds but for a single point
        Rect pointAsRect = new Rect((int) framePoint.x, (int) framePoint.y, (int) framePoint.x, (int) framePoint.y);
        NormalizedRect transformed = transformBounds(pointAsRect);
        return new NormalizedPoint(transformed.x, transformed.y);
    }

    /**
     * Represents a normalized rectangle with values in range 0-1
     */
    public static class NormalizedRect {

        public final double x;
        public final double y;
        public final double width;
        public final double height;

        public NormalizedRect(double x, double y, double width, double height) {
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
        }
    }

    /**
     * Represents a normalized point with values in range 0-1
     */
    public static class NormalizedPoint {

        public final double x;
        public final double y;

        public NormalizedPoint(double x, double y) {
            this.x = x;
            this.y = y;
        }
    }
}
