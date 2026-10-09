package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.util.Size;
import androidx.exifinterface.media.ExifInterface;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import org.json.JSONObject;
import org.junit.Test;

public class CaptureResolutionSupportTest {

    @Test
    public void parseCaptureResolution_nullObject() {
        CaptureResolutionSupport.CaptureResolutionParseResult result = CaptureResolutionSupport.parseStartCaptureResolution(null);
        assertFalse(result.isError());
        assertNull(result.width);
        assertNull(result.height);
    }

    @Test
    public void parseCaptureResolution_missingWidthOrHeight() throws Exception {
        CaptureResolutionSupport.CaptureResolutionParseResult missingWidth = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"height\":1080}")
        );
        assertTrue(missingWidth.isError());
        assertEquals("captureResolution requires both width and height", missingWidth.errorMessage);

        CaptureResolutionSupport.CaptureResolutionParseResult missingHeight = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"width\":1920}")
        );
        assertTrue(missingHeight.isError());
    }

    @Test
    public void parseCaptureResolution_invalidTypesAndValues() throws Exception {
        assertTrue(CaptureResolutionSupport.parseStartCaptureResolution("not-an-object").isError());

        CaptureResolutionSupport.CaptureResolutionParseResult zero = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"width\":0,\"height\":1080}")
        );
        assertTrue(zero.isError());

        CaptureResolutionSupport.CaptureResolutionParseResult negative = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"width\":-1,\"height\":1080}")
        );
        assertTrue(negative.isError());

        CaptureResolutionSupport.CaptureResolutionParseResult nanWidth = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"width\":NaN,\"height\":1080}")
        );
        assertTrue(nanWidth.isError());

        CaptureResolutionSupport.CaptureResolutionParseResult nullWidth = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"width\":null,\"height\":1080}")
        );
        assertTrue(nullWidth.isError());
    }

    @Test
    public void parseCaptureResolution_stringNumbers() throws Exception {
        CaptureResolutionSupport.CaptureResolutionParseResult result = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"width\":\"1920\",\"height\":\"1080\"}")
        );
        assertFalse(result.isError());
        assertEquals(1920, result.width);
        assertEquals(1080, result.height);
    }

    @Test
    public void parseCaptureResolution_validNumbers() throws Exception {
        CaptureResolutionSupport.CaptureResolutionParseResult result = CaptureResolutionSupport.parseStartCaptureResolution(
            new JSONObject("{\"width\":1600,\"height\":1200}")
        );
        assertFalse(result.isError());
        assertEquals(1600, result.width);
        assertEquals(1200, result.height);
    }

    @Test
    public void parsePositivePixelDimension_edgeCases() {
        assertNull(CaptureResolutionSupport.parsePositivePixelDimension(null));
        assertNull(CaptureResolutionSupport.parsePositivePixelDimension(Double.NaN));
        assertNull(CaptureResolutionSupport.parsePositivePixelDimension("not-a-number"));
        assertEquals(42, CaptureResolutionSupport.parsePositivePixelDimension("42"));
    }

    @Test
    public void normalizedCaptureTargetResolution_swapsToLandscapeMajor() {
        Size normalized = CaptureResolutionSupport.normalizedCaptureTargetResolution(1080, 1920);
        assertEquals(1920, normalized.getWidth());
        assertEquals(1080, normalized.getHeight());
    }

    @Test
    public void filterCaptureResolutionCandidates_capsByLongEdge() {
        List<Size> supported = Arrays.asList(new Size(4000, 3000), new Size(1920, 1080), new Size(1280, 720));
        List<Size> capped = CaptureResolutionSupport.filterCaptureResolutionCandidates(supported, 1920);
        assertEquals(2, capped.size());
        assertEquals(1920, capped.get(0).getWidth());
        assertEquals(1080, capped.get(1).getWidth());
    }

    @Test
    public void filterCaptureResolutionCandidates_fallsBackToSmallest() {
        List<Size> supported = Arrays.asList(new Size(4000, 3000), new Size(3200, 2400));
        List<Size> capped = CaptureResolutionSupport.filterCaptureResolutionCandidates(supported, 1000);
        assertEquals(1, capped.size());
        assertEquals(3200, capped.get(0).getWidth());
    }

    @Test
    public void filterCaptureResolutionCandidates_emptyInput() {
        assertNull(CaptureResolutionSupport.filterCaptureResolutionCandidates(null, 1920));
        assertTrue(CaptureResolutionSupport.filterCaptureResolutionCandidates(Collections.emptyList(), 1920).isEmpty());
    }

    @Test
    public void captureRequiresSoftwareTransform() {
        assertTrue(CaptureResolutionSupport.captureRequiresSoftwareTransform(800, null, false, false, false, false));
        assertTrue(CaptureResolutionSupport.captureRequiresSoftwareTransform(null, 600, false, false, false, false));
        assertTrue(CaptureResolutionSupport.captureRequiresSoftwareTransform(null, null, true, false, false, false));
        assertTrue(CaptureResolutionSupport.captureRequiresSoftwareTransform(null, null, false, true, false, false));
        assertTrue(CaptureResolutionSupport.captureRequiresSoftwareTransform(null, null, false, false, true, true));
        assertFalse(CaptureResolutionSupport.captureRequiresSoftwareTransform(null, null, false, false, true, false));
        assertFalse(CaptureResolutionSupport.captureRequiresSoftwareTransform(null, null, false, false, false, false));
    }

    @Test
    public void canUseViewportCaptureFastPath_qualityAndTransforms() {
        assertTrue(
            CaptureResolutionSupport.canUseViewportCaptureFastPath(
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                false,
                true,
                ExifInterface.ORIENTATION_NORMAL
            )
        );
        assertFalse(
            CaptureResolutionSupport.canUseViewportCaptureFastPath(
                50,
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                false,
                true,
                ExifInterface.ORIENTATION_NORMAL
            )
        );
        assertFalse(
            CaptureResolutionSupport.canUseViewportCaptureFastPath(
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                true,
                true,
                ExifInterface.ORIENTATION_NORMAL
            )
        );
        assertFalse(
            CaptureResolutionSupport.canUseViewportCaptureFastPath(
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                false,
                false,
                ExifInterface.ORIENTATION_NORMAL
            )
        );
        assertFalse(
            CaptureResolutionSupport.canUseViewportCaptureFastPath(
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                CaptureResolutionSupport.DEFAULT_IMAGE_CAPTURE_JPEG_QUALITY,
                false,
                true,
                ExifInterface.ORIENTATION_ROTATE_90
            )
        );
    }
}
