package app.capgo.capacitor.camera.preview;

import android.graphics.Rect;
import android.graphics.RectF;
import org.json.JSONException;
import org.json.JSONObject;

public final class FaceDetectionJsonMapper {

    private FaceDetectionJsonMapper() {}

    public static RectF normalizeBoundingBox(Rect bounds, int imageWidth, int imageHeight, int rotationDegrees) {
        if (bounds == null || imageWidth <= 0 || imageHeight <= 0) {
            return new RectF(0f, 0f, 0f, 0f);
        }

        int normalizedRotation = ((rotationDegrees % 360) + 360) % 360;
        int frameWidth = imageWidth;
        int frameHeight = imageHeight;
        if (normalizedRotation == 90 || normalizedRotation == 270) {
            frameWidth = imageHeight;
            frameHeight = imageWidth;
        }

        int clippedLeft = Math.max(0, Math.min(bounds.left, frameWidth));
        int clippedTop = Math.max(0, Math.min(bounds.top, frameHeight));
        int clippedRight = Math.max(clippedLeft, Math.min(bounds.right, frameWidth));
        int clippedBottom = Math.max(clippedTop, Math.min(bounds.bottom, frameHeight));

        return new RectF(
            clippedLeft / (float) frameWidth,
            clippedTop / (float) frameHeight,
            clippedRight / (float) frameWidth,
            clippedBottom / (float) frameHeight
        );
    }

    public static JSONObject toFaceJson(RectF normalizedBounds, Integer trackingId) throws JSONException {
        JSONObject face = new JSONObject();
        JSONObject bounds = new JSONObject();
        bounds.put("x", normalizedBounds.left);
        bounds.put("y", normalizedBounds.top);
        bounds.put("width", normalizedBounds.width());
        bounds.put("height", normalizedBounds.height());
        face.put("bounds", bounds);
        if (trackingId != null) {
            face.put("trackingId", trackingId);
        }
        return face;
    }
}
