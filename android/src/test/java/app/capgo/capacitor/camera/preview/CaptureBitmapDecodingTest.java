package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class CaptureBitmapDecodingTest {

    @Test
    public void computeInSampleSize_noBounds() {
        assertEquals(1, CaptureBitmapDecoding.computeInSampleSize(4000, 3000, null, null));
    }

    @Test
    public void computeInSampleSize_scalesDownForMaxDimensions() {
        int sampleSize = CaptureBitmapDecoding.computeInSampleSize(4000, 3000, 1920, 1080);
        assertTrue(sampleSize >= 2);
        int decodedWidth = 4000 / sampleSize;
        int decodedHeight = 3000 / sampleSize;
        assertTrue(decodedWidth >= 1920 || decodedHeight >= 1080);
    }

    @Test
    public void computeInSampleSize_singleDimensionBound() {
        int sampleSize = CaptureBitmapDecoding.computeInSampleSize(4000, 3000, 800, null);
        assertTrue(sampleSize >= 4);
    }
}
