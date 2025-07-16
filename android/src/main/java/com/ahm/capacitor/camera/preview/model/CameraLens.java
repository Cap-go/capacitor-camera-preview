package com.ahm.capacitor.camera.preview.model;

/**
 * Represents a camera lens available on the Android device.
 */
public class CameraLens {
    private final String id;
    private final String label;
    private final String position;
    private final String deviceType;
    private final float focalLength;
    private final float minZoom;
    private final float maxZoom;
    private final float baseZoomRatio;
    public boolean isActive;

    public CameraLens(String id, String label, String position, String deviceType,
                     float focalLength, float minZoom, float maxZoom,
                     float baseZoomRatio, boolean isActive) {
        this.id = id;
        this.label = label;
        this.position = position;
        this.deviceType = deviceType;
        this.focalLength = Math.round(focalLength * 100.0f) / 100.0f;
        this.minZoom = minZoom;
        this.maxZoom = maxZoom;
        this.baseZoomRatio = Math.round(baseZoomRatio);
        this.isActive = isActive;
    }

    public String getId() {
        return id;
    }

    public String getLabel() {
        return label;
    }

    public String getPosition() {
        return position;
    }

    public String getDeviceType() {
        return deviceType;
    }

    public float getFocalLength() {
        return focalLength;
    }

    public float getMinZoom() {
        return minZoom;
    }

    public float getMaxZoom() {
        return maxZoom;
    }

    public float getBaseZoomRatio() {
        return baseZoomRatio;
    }

    public boolean isActive() {
        return isActive;
    }

    public void setIsActive(boolean isActive) {
        this.isActive = isActive;
    }
}
