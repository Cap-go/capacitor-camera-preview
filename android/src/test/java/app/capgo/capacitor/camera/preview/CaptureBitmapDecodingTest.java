package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(manifest = Config.NONE, sdk = 28)
public class CaptureBitmapDecodingTest {

    @Test
    public void computeInSampleSize_noBounds() {
        assertEquals(1, CaptureBitmapDecoding.computeInSampleSize(4000, 3000, null, null));
    }

    @Test
    public void computeInSampleSize_scalesDownForMaxDimensions() {
        int sampleSize = CaptureBitmapDecoding.computeInSampleSize(4000, 3000, 1920, 1080);
        assertEquals(2, sampleSize);
        int decodedWidth = 4000 / sampleSize;
        int decodedHeight = 3000 / sampleSize;
        assertEquals(2000, decodedWidth);
        assertEquals(1500, decodedHeight);
        assertTrue(decodedWidth >= 1920 && decodedHeight >= 1080);
    }

    @Test
    public void decodeJpegSubsamplingToMaxDimensions_returnsNullForInvalidInput() {
        assertNull(CaptureBitmapDecoding.decodeJpegSubsamplingToMaxDimensions(new byte[0], 1920, 1080));
        assertNull(CaptureBitmapDecoding.decodeJpegSubsamplingToMaxDimensions(new byte[] { 1, 2, 3 }, 1920, 1080));
    }

    @Test
    public void computeInSampleSize_singleDimensionBound() {
        int sampleSize = CaptureBitmapDecoding.computeInSampleSize(4000, 3000, 800, null);
        assertTrue(sampleSize >= 4);
    }
}
