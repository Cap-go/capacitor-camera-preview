package app.capgo.capacitor.camera.preview;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(manifest = Config.NONE, sdk = 28)
public class VideoRecordingOptionsTest {

    @Test
    public void parseVideoBitrate_omittedOrNull() throws Exception {
        assertNull(VideoRecordingOptions.parseVideoBitrate(null));
        assertNull(VideoRecordingOptions.parseVideoBitrate(new JSONObject()));
        assertNull(VideoRecordingOptions.parseVideoBitrate(new JSONObject("{\"videoBitrate\":null}")));
    }

    @Test
    public void parseVideoBitrate_positiveInteger() throws Exception {
        assertEquals(Integer.valueOf(2_500_000), VideoRecordingOptions.parseVideoBitrate(new JSONObject("{\"videoBitrate\":2500000}")));
        assertEquals(Integer.valueOf(900_000), VideoRecordingOptions.parseVideoBitrate(new JSONObject("{\"videoBitrate\":\"900000\"}")));
    }

    @Test
    public void parseVideoBitrate_invalidValuesIgnored() throws Exception {
        assertNull(VideoRecordingOptions.parseVideoBitrate(new JSONObject("{\"videoBitrate\":0}")));
        assertNull(VideoRecordingOptions.parseVideoBitrate(new JSONObject("{\"videoBitrate\":-1}")));
        assertNull(VideoRecordingOptions.parseVideoBitrate(new JSONObject("{\"videoBitrate\":\"bad\"}")));
        assertNull(VideoRecordingOptions.parseVideoBitrate(new JSONObject("{\"videoBitrate\":9223372036854775808}")));
    }
}
