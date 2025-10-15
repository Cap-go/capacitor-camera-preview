package app.capgo.capacitor.camera.preview.model;

/**
 * Represents lens information for a camera device.
 */
public class LensInfo {

    private final float focalLength;
    private final String deviceType;
    private final float baseZoomRatio;
    private final float digitalZoom;

    public LensInfo(float focalLength, String deviceType, float baseZoomRatio, float digitalZoom) {
        this.focalLength = Math.round(focalLength * 100.0f) / 100.0f;
        this.deviceType = deviceType;
        this.baseZoomRatio = baseZoomRatio;
        this.digitalZoom = digitalZoom;
    }

    public float getFocalLength() {
        return focalLength;
    }

    public String getDeviceType() {
        return deviceType;
    }

    public float getBaseZoomRatio() {
        return baseZoomRatio;
    }

    public float getDigitalZoom() {
        return digitalZoom;
    }
}
