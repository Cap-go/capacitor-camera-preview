package com.ahm.capacitor.camera.preview.model;

/**
 * Configuration for a camera session.
 */
public class CameraSessionConfiguration {
    private final String deviceId;
    private final String position;
    private final int x;
    private final int y;
    private final int width;
    private final int height;
    private final int paddingBottom;
    private final boolean toBack;
    private final boolean storeToFile;
    private final boolean enableOpacity;
    private final boolean enableZoom;
    private final boolean disableExifHeaderStripping;
    private final boolean disableAudio;
    private final float zoomFactor;
    private float targetZoom = 1.0f;

    public CameraSessionConfiguration(String deviceId, String position, int x, int y, int width, int height, 
                                    int paddingBottom, boolean toBack, boolean storeToFile, boolean enableOpacity, 
                                    boolean enableZoom, boolean disableExifHeaderStripping, boolean disableAudio, 
                                    float zoomFactor) {
        this.deviceId = deviceId;
        this.position = position;
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        this.paddingBottom = paddingBottom;
        this.toBack = toBack;
        this.storeToFile = storeToFile;
        this.enableOpacity = enableOpacity;
        this.enableZoom = enableZoom;
        this.disableExifHeaderStripping = disableExifHeaderStripping;
        this.disableAudio = disableAudio;
        this.zoomFactor = zoomFactor;
    }

    public void setTargetZoom(float zoom) {
        this.targetZoom = zoom;
    }

    public float getTargetZoom() {
        return this.targetZoom;
    }

    public String getDeviceId() { return deviceId; }
    public String getPosition() { return position; }
    public int getX() { return x; }
    public int getY() { return y; }
    public int getWidth() { return width; }
    public int getHeight() { return height; }
    public int getPaddingBottom() { return paddingBottom; }
    public boolean isToBack() { return toBack; }
    public boolean isStoreToFile() { return storeToFile; }
    public boolean isEnableOpacity() { return enableOpacity; }
    public boolean isEnableZoom() { return enableZoom; }
    public boolean isDisableExifHeaderStripping() { return disableExifHeaderStripping; }
    public boolean isDisableAudio() { return disableAudio; }
    public float getZoomFactor() { return zoomFactor; }
} 
