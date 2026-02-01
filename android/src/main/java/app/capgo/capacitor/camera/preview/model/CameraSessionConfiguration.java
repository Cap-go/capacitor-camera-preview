package app.capgo.capacitor.camera.preview.model;

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
    private final boolean disableExifHeaderStripping;
    private final boolean disableAudio;
    private final float zoomFactor;
    private final String aspectRatio;
    private final String aspectMode;
    private final String gridMode;
    private final boolean disableFocusIndicator;
    private final boolean enableVideoMode;
    private float targetZoom = 1.0f;
    private boolean isCentered = false;

    public CameraSessionConfiguration(
        String deviceId,
        String position,
        int x,
        int y,
        int width,
        int height,
        int paddingBottom,
        boolean toBack,
        boolean storeToFile,
        boolean enableOpacity,
        boolean disableExifHeaderStripping,
        boolean disableAudio,
        float zoomFactor,
        String aspectRatio,
        String aspectMode,
        String gridMode,
        boolean disableFocusIndicator,
        boolean enableVideoMode
    ) {
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
        this.disableExifHeaderStripping = disableExifHeaderStripping;
        this.disableAudio = disableAudio;
        this.zoomFactor = zoomFactor;
        this.aspectRatio = aspectRatio;
        this.aspectMode = aspectMode != null ? aspectMode : "contain";
        this.gridMode = gridMode != null ? gridMode : "none";
        this.disableFocusIndicator = disableFocusIndicator;
        this.enableVideoMode = enableVideoMode;
    }

    public void setTargetZoom(float zoom) {
        this.targetZoom = zoom;
    }

    public float getTargetZoom() {
        return this.targetZoom;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public String getPosition() {
        return position;
    }

    public int getX() {
        return x;
    }

    public int getY() {
        return y;
    }

    public int getWidth() {
        return width;
    }

    public int getHeight() {
        return height;
    }

    public int getPaddingBottom() {
        return paddingBottom;
    }

    public boolean isToBack() {
        return toBack;
    }

    public boolean isStoreToFile() {
        return storeToFile;
    }

    public boolean isEnableOpacity() {
        return enableOpacity;
    }

    public boolean isDisableExifHeaderStripping() {
        return disableExifHeaderStripping;
    }

    public boolean isDisableAudio() {
        return disableAudio;
    }

    public float getZoomFactor() {
        return zoomFactor;
    }

    public String getAspectRatio() {
        return aspectRatio;
    }

    public String getAspectMode() {
        return aspectMode;
    }

    public String getGridMode() {
        return gridMode;
    }

    // Additional getters with "get" prefix for compatibility
    public boolean getToBack() {
        return toBack;
    }

    public boolean getStoreToFile() {
        return storeToFile;
    }

    public boolean getEnableOpacity() {
        return enableOpacity;
    }

    public boolean getDisableExifHeaderStripping() {
        return disableExifHeaderStripping;
    }

    public boolean getDisableAudio() {
        return disableAudio;
    }

    public boolean isCentered() {
        return isCentered;
    }

    public void setCentered(boolean centered) {
        isCentered = centered;
    }

    public boolean getDisableFocusIndicator() {
        return disableFocusIndicator;
    }

    public boolean isVideoModeEnabled() {
        return enableVideoMode;
    }

    public boolean getEnableVideoMode() {
        return enableVideoMode;
    }
}
