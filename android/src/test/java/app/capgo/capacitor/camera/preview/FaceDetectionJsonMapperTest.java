package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;

import android.graphics.Rect;
import android.graphics.RectF;
import org.json.JSONObject;
import org.junit.Test;

public class FaceDetectionJsonMapperTest {

    @Test
    public void normalizeBoundingBox_mapsPixelRectToFractions() {
        RectF normalized = FaceDetectionJsonMapper.normalizeBoundingBox(new Rect(100, 50, 300, 250), 1000, 500, 0);

        assertEquals(0.1f, normalized.left, 0.0001f);
        assertEquals(0.1f, normalized.top, 0.0001f);
        assertEquals(0.3f, normalized.right, 0.0001f);
        assertEquals(0.5f, normalized.bottom, 0.0001f);
    }

    @Test
    public void normalizeBoundingBox_swapsDimensionsForQuarterTurnRotation() {
        RectF normalized = FaceDetectionJsonMapper.normalizeBoundingBox(new Rect(100, 50, 300, 250), 1000, 500, 90);

        assertEquals(0.2f, normalized.left, 0.0001f);
        assertEquals(0.1f, normalized.top, 0.0001f);
        assertEquals(0.6f, normalized.right, 0.0001f);
        assertEquals(0.5f, normalized.bottom, 0.0001f);
    }

    @Test
    public void toFaceJson_emitsNormalizedBounds() throws Exception {
        RectF bounds = new RectF(0.1f, 0.2f, 0.5f, 0.7f);
        JSONObject face = FaceDetectionJsonMapper.toFaceJson(bounds, 42);

        JSONObject serializedBounds = face.getJSONObject("bounds");
        assertEquals(0.1, serializedBounds.getDouble("x"), 0.0001);
        assertEquals(0.2, serializedBounds.getDouble("y"), 0.0001);
        assertEquals(0.4, serializedBounds.getDouble("width"), 0.0001);
        assertEquals(0.5, serializedBounds.getDouble("height"), 0.0001);
        assertEquals(42, face.getInt("trackingId"));
    }
}
