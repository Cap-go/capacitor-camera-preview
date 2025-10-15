package app.capgo.capacitor.camera.preview.model;

/**
 * Represents zoom factor information for a camera with current lens details.
 */
public class ZoomFactors {

    private final float min;
    private final float max;
    private final float current;
    private final LensInfo lens;

    public ZoomFactors(float min, float max, float current, LensInfo lens) {
        this.min = min;
        this.max = max;
        this.current = current;
        this.lens = lens;
    }

    public float getMin() {
        return min;
    }

    public float getMax() {
        return max;
    }

    public float getCurrent() {
        return current;
    }

    public LensInfo getLens() {
        return lens;
    }
}
