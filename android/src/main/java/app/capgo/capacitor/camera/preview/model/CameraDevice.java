package app.capgo.capacitor.camera.preview.model;

import java.util.List;

/**
 * Represents a camera device available on the Android device.
 */
public class CameraDevice {

    private final String deviceId;
    private final String label;
    private final String position;
    private final List<LensInfo> lenses;
    private final float minZoom;
    private final float maxZoom;
    private final boolean isLogical;

    public CameraDevice(
        String deviceId,
        String label,
        String position,
        List<LensInfo> lenses,
        float minZoom,
        float maxZoom,
        boolean isLogical
    ) {
        this.deviceId = deviceId;
        this.label = label;
        this.position = position;
        this.lenses = lenses;
        this.minZoom = minZoom;
        this.maxZoom = maxZoom;
        this.isLogical = isLogical;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public String getLabel() {
        return label;
    }

    public String getPosition() {
        return position;
    }

    public List<LensInfo> getLenses() {
        return lenses;
    }

    public float getMinZoom() {
        return minZoom;
    }

    public float getMaxZoom() {
        return maxZoom;
    }

    public boolean isLogical() {
        return isLogical;
    }
}
