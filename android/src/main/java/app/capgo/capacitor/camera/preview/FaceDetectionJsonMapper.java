package app.capgo.capacitor.camera.preview;

import android.graphics.Rect;
import android.graphics.RectF;
import org.json.JSONException;
import org.json.JSONObject;

public final class FaceDetectionJsonMapper {

    private FaceDetectionJsonMapper() {}

    public static RectF normalizeBoundingBox(Rect bounds, int imageWidth, int imageHeight) {
        if (bounds == null || imageWidth <= 0 || imageHeight <= 0) {
            return new RectF(0f, 0f, 0f, 0f);
        }

        float width = imageWidth;
        float height = imageHeight;
        return new RectF(bounds.left / width, bounds.top / height, bounds.right / width, bounds.bottom / height);
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
