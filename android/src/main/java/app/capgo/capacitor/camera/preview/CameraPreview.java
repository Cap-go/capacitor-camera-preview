package app.capgo.capacitor.camera.preview;

import static android.Manifest.permission.CAMERA;
import static android.Manifest.permission.RECORD_AUDIO;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.location.Location;
import android.net.Uri;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.Size;
import android.view.OrientationEventListener;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import androidx.annotation.RequiresPermission;
import androidx.appcompat.app.AlertDialog;
import androidx.core.app.ActivityCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import app.capgo.capacitor.camera.preview.model.CameraDevice;
import app.capgo.capacitor.camera.preview.model.CameraSessionConfiguration;
import app.capgo.capacitor.camera.preview.model.LensInfo;
import app.capgo.capacitor.camera.preview.model.ZoomFactors;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Logger;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;
import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationServices;
import java.util.List;
import java.util.Objects;
import org.json.JSONObject;

@CapacitorPlugin(
    name = "CameraPreview",
    permissions = {
        @Permission(strings = { CAMERA, RECORD_AUDIO }, alias = CameraPreview.CAMERA_WITH_AUDIO_PERMISSION_ALIAS),
        @Permission(strings = { CAMERA }, alias = CameraPreview.CAMERA_ONLY_PERMISSION_ALIAS),
        @Permission(
            strings = { Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION },
            alias = CameraPreview.CAMERA_WITH_LOCATION_PERMISSION_ALIAS
        ),
        @Permission(strings = { RECORD_AUDIO }, alias = CameraPreview.MICROPHONE_ONLY_PERMISSION_ALIAS)
    }
)
public class CameraPreview extends Plugin implements CameraXView.CameraXViewListener {

    private final String pluginVersion = "";

    @Override
    protected void handleOnPause() {
        super.handleOnPause();
        if (cameraXView != null && cameraXView.isRunning()) {
            // Store the current configuration before stopping
            lastSessionConfig = cameraXView.getSessionConfig();
            cameraXView.stopSession();
        }
    }

    @Override
    protected void handleOnResume() {
        super.handleOnResume();
        if (lastSessionConfig != null) {
            // Recreate camera with last known configuration
            if (cameraXView == null) {
                cameraXView = new CameraXView(getContext(), getBridge().getWebView());
                cameraXView.setListener(this);
            }
            cameraXView.startSession(lastSessionConfig);
        }
    }

    @Override
    protected void handleOnDestroy() {
        super.handleOnDestroy();
        if (cameraXView != null) {
            cameraXView.stopSession();
            cameraXView = null;
        }
        lastSessionConfig = null;
    }

    private CameraSessionConfiguration lastSessionConfig;

    private static final String TAG = "CameraPreview CameraXView";

    static final String CAMERA_WITH_AUDIO_PERMISSION_ALIAS = "cameraWithAudio";
    static final String CAMERA_ONLY_PERMISSION_ALIAS = "cameraOnly";
    static final String CAMERA_WITH_LOCATION_PERMISSION_ALIAS = "cameraWithLocation";
    static final String MICROPHONE_ONLY_PERMISSION_ALIAS = "microphoneOnly";

    private String captureCallbackId = "";
    private String sampleCallbackId = "";
    private String cameraStartCallbackId = "";
    private final Object pendingStartLock = new Object();
    private PluginCall pendingStartCall;
    private int previousOrientationRequest = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
    private CameraXView cameraXView;
    private View rotationOverlay;
    private FusedLocationProviderClient fusedLocationClient;
    private Location lastLocation;
    private OrientationEventListener orientationListener;
    private int lastOrientation = Configuration.ORIENTATION_UNDEFINED;
    private String lastOrientationStr = "unknown";
    private boolean lastDisableAudio = true;
    private Drawable originalWindowBackground;
    private boolean isCameraPermissionDialogShowing = false;

    @PluginMethod
    public void getExposureModes(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        JSArray arr = new JSArray();
        for (String m : cameraXView.getExposureModes()) arr.put(m);
        JSObject ret = new JSObject();
        ret.put("modes", arr);
        call.resolve(ret);
    }

    @PluginMethod
    public void getExposureMode(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        JSObject ret = new JSObject();
        ret.put("mode", cameraXView.getExposureMode());
        call.resolve(ret);
    }

    @PluginMethod
    public void setExposureMode(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        String mode = call.getString("mode");
        if (mode == null || mode.isEmpty()) {
            call.reject("mode parameter is required");
            return;
        }
        try {
            cameraXView.setExposureMode(mode);
            call.resolve();
        } catch (Exception e) {
            call.reject("Failed to set exposure mode: " + e.getMessage());
        }
    }

    @PluginMethod
    public void getExposureCompensationRange(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        try {
            float[] range = cameraXView.getExposureCompensationRange();
            JSObject ret = new JSObject();
            ret.put("min", range[0]);
            ret.put("max", range[1]);
            ret.put("step", range.length > 2 ? range[2] : 0.1);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to get exposure compensation range: " + e.getMessage());
        }
    }

    @PluginMethod
    public void getExposureCompensation(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        try {
            float value = cameraXView.getExposureCompensation();
            JSObject ret = new JSObject();
            ret.put("value", value);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to get exposure compensation: " + e.getMessage());
        }
    }

    @PluginMethod
    public void setExposureCompensation(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        Float value = call.getFloat("value");
        if (value == null) {
            call.reject("value parameter is required");
            return;
        }
        try {
            cameraXView.setExposureCompensation(value);
            call.resolve();
        } catch (Exception e) {
            call.reject("Failed to set exposure compensation: " + e.getMessage());
        }
    }

    @PluginMethod
    public void getOrientation(PluginCall call) {
        String o = getDeviceOrientationString();
        JSObject ret = new JSObject();
        ret.put("orientation", o);
        call.resolve(ret);
    }

    @PluginMethod
    public void start(PluginCall call) {
        boolean force = Boolean.TRUE.equals(call.getBoolean("force", false));

        // If force is true, kill everything and restart no matter what
        if (force && cameraXView != null) {
            try {
                Log.d(TAG, "start: force=true, force stopping camera regardless of state");
                // Force stop the camera session no matter what state it's in
                cameraXView.stopSession();
                cameraXView = null;
            } catch (Exception e) {
                Log.w(TAG, "start: Exception while force stopping camera", e);
                // Continue anyway - we're forcing a restart
                cameraXView = null;
            }
        } else if (cameraXView != null) {
            // Normal checks only when force is false
            try {
                if (cameraXView.isRunning() && !cameraXView.isStopping()) {
                    call.reject("Camera is already running");
                    return;
                }
                if (cameraXView.isStopping() || cameraXView.isBusy()) {
                    if (enqueuePendingStart(call)) {
                        Log.d(TAG, "start: Camera busy; queued start request until stop completes");
                        return;
                    }
                    call.reject("Camera is busy or stopping. Please retry shortly.");
                    return;
                }
            } catch (Exception ignored) {}
        }

        boolean disableAudio = Boolean.TRUE.equals(call.getBoolean("disableAudio", true));
        String permissionAlias = disableAudio ? CAMERA_ONLY_PERMISSION_ALIAS : CAMERA_WITH_AUDIO_PERMISSION_ALIAS;

        if (PermissionState.GRANTED.equals(getPermissionState(permissionAlias))) {
            startCamera(call);
        } else {
            requestPermissionForAlias(permissionAlias, call, "handleCameraPermissionResult");
        }
    }

    private boolean enqueuePendingStart(PluginCall call) {
        synchronized (pendingStartLock) {
            if (pendingStartCall == null) {
                pendingStartCall = call;
                return true;
            }
        }
        return false;
    }

    @PluginMethod
    public void flip(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        cameraXView.flipCamera();
        call.resolve();
    }

    @SuppressLint("MissingPermission")
    @PluginMethod
    public void capture(final PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }

        final boolean withExifLocation = Boolean.TRUE.equals(call.getBoolean("withExifLocation", false));

        if (withExifLocation) {
            if (getPermissionState(CAMERA_WITH_LOCATION_PERMISSION_ALIAS) != PermissionState.GRANTED) {
                requestPermissionForAlias(CAMERA_WITH_LOCATION_PERMISSION_ALIAS, call, "captureWithLocationPermission");
            } else {
                getLocationAndCapture(call);
            }
        } else {
            captureWithoutLocation(call);
        }
    }

    @SuppressLint("MissingPermission")
    @PermissionCallback
    private void captureWithLocationPermission(PluginCall call) {
        if (getPermissionState(CAMERA_WITH_LOCATION_PERMISSION_ALIAS) == PermissionState.GRANTED) {
            if (
                ActivityCompat.checkSelfPermission(getContext(), Manifest.permission.ACCESS_FINE_LOCATION) !=
                    PackageManager.PERMISSION_GRANTED ||
                ActivityCompat.checkSelfPermission(getContext(), Manifest.permission.ACCESS_COARSE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return;
            }
            getLocationAndCapture(call);
        } else {
            Logger.warn("Location permission denied. Capturing photo without location data.");
            captureWithoutLocation(call);
        }
    }

    @RequiresPermission(allOf = { Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION })
    private void getLocationAndCapture(PluginCall call) {
        if (fusedLocationClient == null) {
            fusedLocationClient = LocationServices.getFusedLocationProviderClient(getContext());
        }
        fusedLocationClient
            .getLastLocation()
            .addOnSuccessListener(getActivity(), (location) -> {
                lastLocation = location;
                proceedWithCapture(call, lastLocation);
            })
            .addOnFailureListener((e) -> {
                Logger.error("Failed to get location: " + e.getMessage());
                proceedWithCapture(call, null);
            });
    }

    private void captureWithoutLocation(PluginCall call) {
        proceedWithCapture(call, null);
    }

    private void proceedWithCapture(PluginCall call, Location location) {
        bridge.saveCall(call);
        captureCallbackId = call.getCallbackId();

        Integer quality = Objects.requireNonNull(call.getInt("quality", 85));
        final boolean saveToGallery = Boolean.TRUE.equals(call.getBoolean("saveToGallery"));
        Integer width = call.getInt("width");
        Integer height = call.getInt("height");
        final boolean embedTimestamp = Boolean.TRUE.equals(call.getBoolean("embedTimestamp"));
        final boolean embedLocation = Boolean.TRUE.equals(call.getBoolean("embedLocation"));

        cameraXView.capturePhoto(quality, saveToGallery, width, height, location, embedTimestamp, embedLocation);
    }

    @PluginMethod
    public void captureSample(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        bridge.saveCall(call);
        sampleCallbackId = call.getCallbackId();
        Integer quality = Objects.requireNonNull(call.getInt("quality", 85));
        cameraXView.captureSample(quality);
    }

    @PluginMethod
    public void stop(final PluginCall call) {
        boolean force = Boolean.TRUE.equals(call.getBoolean("force", false));

        bridge
            .getActivity()
            .runOnUiThread(() -> {
                getBridge().getActivity().setRequestedOrientation(previousOrientationRequest);

                // Disable and clear orientation listener
                if (orientationListener != null) {
                    orientationListener.disable();
                    orientationListener = null;
                    lastOrientation = Configuration.ORIENTATION_UNDEFINED;
                }

                // Remove any rotation overlay if present
                if (rotationOverlay != null && rotationOverlay.getParent() != null) {
                    ((ViewGroup) rotationOverlay.getParent()).removeView(rotationOverlay);
                    rotationOverlay = null;
                }

                if (cameraXView != null) {
                    cameraXView.stopSession();
                    // If force is true, always drop the reference
                    // Otherwise only drop the reference if no deferred stop is pending
                    if (force || !cameraXView.isStopDeferred()) {
                        cameraXView = null;
                    }
                }
                // Manual stops should not trigger automatic resume with stale config
                lastSessionConfig = null;
                // Restore original window background if modified earlier
                if (originalWindowBackground != null) {
                    try {
                        getBridge().getActivity().getWindow().setBackgroundDrawable(originalWindowBackground);
                    } catch (Exception ignored) {}
                    originalWindowBackground = null;
                }
                call.resolve();
            });
    }

    @PluginMethod
    public void getSupportedFlashModes(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        List<String> supportedFlashModes = cameraXView.getSupportedFlashModes();
        JSArray jsonFlashModes = new JSArray();
        for (String mode : supportedFlashModes) {
            jsonFlashModes.put(mode);
        }
        JSObject jsObject = new JSObject();
        jsObject.put("result", jsonFlashModes);
        call.resolve(jsObject);
    }

    @PluginMethod
    public void setFlashMode(PluginCall call) {
        String flashMode = call.getString("flashMode");
        if (flashMode == null || flashMode.isEmpty()) {
            call.reject("flashMode required parameter is missing");
            return;
        }

        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        cameraXView.setFlashMode(flashMode);
        call.resolve();
    }

    @PluginMethod
    public void getAvailableDevices(PluginCall call) {
        List<CameraDevice> devices = CameraXView.getAvailableDevicesStatic(getContext());
        JSArray devicesArray = new JSArray();
        for (CameraDevice device : devices) {
            JSObject deviceJson = new JSObject();
            deviceJson.put("deviceId", device.getDeviceId());
            deviceJson.put("label", device.getLabel());
            deviceJson.put("position", device.getPosition());
            JSArray lensesArray = new JSArray();
            for (app.capgo.capacitor.camera.preview.model.LensInfo lens : device.getLenses()) {
                JSObject lensJson = new JSObject();
                lensJson.put("focalLength", lens.getFocalLength());
                lensJson.put("deviceType", lens.getDeviceType());
                lensJson.put("baseZoomRatio", lens.getBaseZoomRatio());
                lensJson.put("digitalZoom", lens.getDigitalZoom());
                lensesArray.put(lensJson);
            }
            deviceJson.put("lenses", lensesArray);
            deviceJson.put("minZoom", device.getMinZoom());
            deviceJson.put("maxZoom", device.getMaxZoom());
            devicesArray.put(deviceJson);
        }
        JSObject result = new JSObject();
        result.put("devices", devicesArray);
        call.resolve(result);
    }

    @PluginMethod
    public void getZoom(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        ZoomFactors zoomFactors = cameraXView.getZoomFactors();
        JSObject result = new JSObject();
        result.put("min", zoomFactors.getMin());
        result.put("max", zoomFactors.getMax());
        result.put("current", zoomFactors.getCurrent());
        call.resolve(result);
    }

    @PluginMethod
    public void getZoomButtonValues(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        // Build a sorted set to dedupe and order ascending
        java.util.Set<Double> sorted = new java.util.TreeSet<>();
        sorted.add(1.0);
        sorted.add(2.0);

        // Try to detect ultra-wide to include its min zoom (often 0.5)
        try {
            List<CameraDevice> devices = CameraXView.getAvailableDevicesStatic(getContext());
            ZoomFactors zoomFactors = cameraXView.getZoomFactors();
            boolean hasUltraWide = false;
            boolean hasTelephoto = false;
            float minUltra = 0.5f;

            for (CameraDevice device : devices) {
                for (app.capgo.capacitor.camera.preview.model.LensInfo lens : device.getLenses()) {
                    if ("ultraWide".equals(lens.getDeviceType())) {
                        hasUltraWide = true;
                        // Use overall minZoom for that device as the button value to represent UW
                        minUltra = Math.max(minUltra, zoomFactors.getMin());
                    } else if ("telephoto".equals(lens.getDeviceType())) {
                        hasTelephoto = true;
                    }
                }
            }
            if (hasUltraWide) {
                sorted.add((double) minUltra);
            }
            if (hasTelephoto) {
                sorted.add(3.0);
            }
        } catch (Exception ignored) {
            // Ignore and keep defaults
        }

        JSObject result = new JSObject();
        JSArray values = new JSArray();
        for (Double v : sorted) {
            values.put(v);
        }
        result.put("values", values);
        call.resolve(result);
    }

    @PluginMethod
    public void setZoom(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        Float level = call.getFloat("level");
        if (level == null) {
            call.reject("level parameter is required");
            return;
        }
        try {
            cameraXView.setZoom(level);
            call.resolve();
        } catch (Exception e) {
            call.reject("Failed to set zoom: " + e.getMessage());
        }
    }

    @PluginMethod
    public void setFocus(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        Float x = call.getFloat("x");
        Float y = call.getFloat("y");
        if (x == null || y == null) {
            call.reject("x and y parameters are required");
            return;
        }
        // Reject if values are outside 0-1 range
        if (x < 0f || x > 1f || y < 0f || y > 1f) {
            call.reject("Focus coordinates must be between 0 and 1");
            return;
        }

        getActivity().runOnUiThread(() -> {
            try {
                cameraXView.setFocus(x, y);
                call.resolve();
            } catch (Exception e) {
                call.reject("Failed to set focus: " + e.getMessage());
            }
        });
    }

    @PluginMethod
    public void setDeviceId(PluginCall call) {
        String deviceId = call.getString("deviceId");
        if (deviceId == null || deviceId.isEmpty()) {
            call.reject("deviceId parameter is required");
            return;
        }
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        cameraXView.switchToDevice(deviceId);
        call.resolve();
    }

    @PluginMethod
    public void getSupportedPictureSizes(final PluginCall call) {
        JSArray supportedPictureSizesResult = new JSArray();
        List<Size> rearSizes = CameraXView.getSupportedPictureSizes("rear");
        JSObject rear = new JSObject();
        rear.put("facing", "rear");
        JSArray rearSizesJs = new JSArray();
        for (Size size : rearSizes) {
            JSObject sizeJs = new JSObject();
            sizeJs.put("width", size.getWidth());
            sizeJs.put("height", size.getHeight());
            rearSizesJs.put(sizeJs);
        }
        rear.put("supportedPictureSizes", rearSizesJs);
        supportedPictureSizesResult.put(rear);

        List<Size> frontSizes = CameraXView.getSupportedPictureSizes("front");
        JSObject front = new JSObject();
        front.put("facing", "front");
        JSArray frontSizesJs = new JSArray();
        for (Size size : frontSizes) {
            JSObject sizeJs = new JSObject();
            sizeJs.put("width", size.getWidth());
            sizeJs.put("height", size.getHeight());
            frontSizesJs.put(sizeJs);
        }
        front.put("supportedPictureSizes", frontSizesJs);
        supportedPictureSizesResult.put(front);

        JSObject ret = new JSObject();
        ret.put("supportedPictureSizes", supportedPictureSizesResult);
        call.resolve(ret);
    }

    @PluginMethod
    public void setOpacity(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        Float opacity = call.getFloat("opacity", 1.0f);
        //noinspection DataFlowIssue
        cameraXView.setOpacity(opacity);
        call.resolve();
    }

    @PluginMethod
    public void getHorizontalFov(PluginCall call) {
        // CameraX does not provide a simple way to get FoV.
        // This would require Camera2 interop to access camera characteristics.
        // Returning a default/estimated value.
        JSObject ret = new JSObject();
        ret.put("result", 60.0); // A common default FoV
        call.resolve(ret);
    }

    @PluginMethod
    public void getDeviceId(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        JSObject ret = new JSObject();
        ret.put("deviceId", cameraXView.getCurrentDeviceId());
        call.resolve(ret);
    }

    @PluginMethod
    public void getFlashMode(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        JSObject ret = new JSObject();
        ret.put("flashMode", cameraXView.getFlashMode());
        call.resolve(ret);
    }

    @PluginMethod
    public void isRunning(PluginCall call) {
        boolean running = cameraXView != null && cameraXView.isRunning();
        JSObject jsObject = new JSObject();
        jsObject.put("isRunning", running);
        call.resolve(jsObject);
    }

    private void showCameraPermissionDialog(String title, String message, String openSettingsText, String cancelText, Runnable completion) {
        Activity activity = getActivity();
        if (activity == null) {
            if (completion != null) {
                completion.run();
            }
            return;
        }

        activity.runOnUiThread(() -> {
            if (activity.isFinishing()) {
                if (completion != null) {
                    completion.run();
                }
                return;
            }

            if (isCameraPermissionDialogShowing) {
                if (completion != null) {
                    completion.run();
                }
                return;
            }

            AlertDialog dialog = new AlertDialog.Builder(activity)
                .setTitle(title)
                .setMessage(message)
                .setNegativeButton(cancelText, (d, which) -> {
                    d.dismiss();
                    isCameraPermissionDialogShowing = false;
                })
                .setPositiveButton(openSettingsText, (d, which) -> {
                    Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                    Uri uri = Uri.fromParts("package", activity.getPackageName(), null);
                    intent.setData(uri);
                    activity.startActivity(intent);
                    isCameraPermissionDialogShowing = false;
                })
                .setOnDismissListener((d) -> isCameraPermissionDialogShowing = false)
                .create();

            isCameraPermissionDialogShowing = true;
            dialog.show();
            if (completion != null) {
                completion.run();
            }
        });
    }

    private String mapPermissionState(PermissionState state) {
        if (state == null) {
            return PermissionState.PROMPT.toString();
        }

        return state.toString();
    }

    @PluginMethod
    public void checkPermissions(PluginCall call) {
        boolean disableAudio = call.getBoolean("disableAudio") != null ? Boolean.TRUE.equals(call.getBoolean("disableAudio")) : true;

        PermissionState cameraState = getPermissionState(CAMERA_ONLY_PERMISSION_ALIAS);

        JSObject result = new JSObject();
        result.put("camera", mapPermissionState(cameraState));

        if (!disableAudio) {
            PermissionState audioState = getPermissionState(MICROPHONE_ONLY_PERMISSION_ALIAS);
            result.put("microphone", mapPermissionState(audioState));
        }

        call.resolve(result);
    }

    @Override
    @PluginMethod
    public void requestPermissions(PluginCall call) {
        Boolean disableAudioOption = call.getBoolean("disableAudio");
        boolean disableAudio = disableAudioOption == null ? true : Boolean.TRUE.equals(disableAudioOption);
        this.lastDisableAudio = disableAudio;

        String permissionAlias = disableAudio ? CAMERA_ONLY_PERMISSION_ALIAS : CAMERA_WITH_AUDIO_PERMISSION_ALIAS;

        boolean cameraGranted = PermissionState.GRANTED.equals(getPermissionState(CAMERA_ONLY_PERMISSION_ALIAS));
        boolean audioGranted = disableAudio || PermissionState.GRANTED.equals(getPermissionState(MICROPHONE_ONLY_PERMISSION_ALIAS));

        if (cameraGranted && audioGranted) {
            JSObject result = new JSObject();
            result.put("camera", mapPermissionState(PermissionState.GRANTED));
            if (!disableAudio) {
                result.put("microphone", mapPermissionState(PermissionState.GRANTED));
            }
            call.resolve(result);
            return;
        }

        requestPermissionForAlias(permissionAlias, call, "handleRequestPermissionsResult");
    }

    @PermissionCallback
    private void handleRequestPermissionsResult(PluginCall call) {
        Boolean disableAudioOption = call.getBoolean("disableAudio");
        boolean disableAudio = disableAudioOption == null ? true : Boolean.TRUE.equals(disableAudioOption);
        this.lastDisableAudio = disableAudio;

        PermissionState cameraState = getPermissionState(CAMERA_ONLY_PERMISSION_ALIAS);
        JSObject result = new JSObject();
        result.put("camera", mapPermissionState(cameraState));

        if (!disableAudio) {
            PermissionState audioState = getPermissionState(CAMERA_WITH_AUDIO_PERMISSION_ALIAS);
            result.put("microphone", mapPermissionState(audioState));
        }

        boolean showSettingsAlert = call.getBoolean("showSettingsAlert") != null
            ? Boolean.TRUE.equals(call.getBoolean("showSettingsAlert"))
            : false;

        String cameraStateString = result.getString("camera");
        boolean cameraNeedsSettings = "denied".equals(cameraStateString) || "prompt-with-rationale".equals(cameraStateString);

        boolean microphoneNeedsSettings = false;
        if (result.has("microphone")) {
            String micStateString = result.getString("microphone");
            microphoneNeedsSettings = "denied".equals(micStateString) || "prompt-with-rationale".equals(micStateString);
        }

        boolean shouldShowAlert = showSettingsAlert && (cameraNeedsSettings || microphoneNeedsSettings);

        if (shouldShowAlert) {
            Activity activity = getActivity();
            if (activity == null) {
                call.resolve(result);
                return;
            }

            String title = call.getString("title", "Camera Permission Needed");
            String message = call.getString("message", "Enable camera access in Settings to use the preview.");
            String openSettingsText = call.getString("openSettingsButtonTitle", "Open Settings");
            String cancelText = call.getString("cancelButtonTitle", activity.getString(android.R.string.cancel));

            showCameraPermissionDialog(title, message, openSettingsText, cancelText, () -> call.resolve(result));
        } else {
            call.resolve(result);
        }
    }

    @PermissionCallback
    private void handleCameraPermissionResult(PluginCall call) {
        if (
            PermissionState.GRANTED.equals(getPermissionState(CAMERA_ONLY_PERMISSION_ALIAS)) ||
            PermissionState.GRANTED.equals(getPermissionState(CAMERA_WITH_AUDIO_PERMISSION_ALIAS))
        ) {
            startCamera(call);
        } else {
            call.reject("camera permission denied. enable camera access in Settings.", "cameraPermissionDenied");
        }
    }

    private void startCamera(final PluginCall call) {
        String positionParam = call.getString("position");
        String originalDeviceId = call.getString("deviceId");
        String deviceId = originalDeviceId; // Use a mutable variable

        final String position = (positionParam == null ||
                positionParam.isEmpty() ||
                "rear".equals(positionParam) ||
                "back".equals(positionParam))
            ? "back"
            : "front";
        // Use -1 as default to indicate centering is needed when x/y not provided
        final Integer xParam = call.getInt("x");
        final Integer yParam = call.getInt("y");
        final int x = xParam != null ? xParam : -1;
        final int y = yParam != null ? yParam : -1;

        Log.d("CameraPreview", "========================");
        Log.d("CameraPreview", "CAMERA POSITION TRACKING START:");
        Log.d("CameraPreview", "1. RAW PARAMS - xParam: " + xParam + ", yParam: " + yParam);
        Log.d("CameraPreview", "2. AFTER DEFAULT - x: " + x + " (center=" + (x == -1) + "), y: " + y + " (center=" + (y == -1) + ")");
        //noinspection DataFlowIssue
        final int width = call.getInt("width", 0);
        //noinspection DataFlowIssue
        final int height = call.getInt("height", 0);
        //noinspection DataFlowIssue
        final int paddingBottom = call.getInt("paddingBottom", 0);
        final boolean toBack = Boolean.TRUE.equals(call.getBoolean("toBack", true));
        final boolean storeToFile = Boolean.TRUE.equals(call.getBoolean("storeToFile", false));
        final boolean enableOpacity = Boolean.TRUE.equals(call.getBoolean("enableOpacity", false));
        final boolean disableExifHeaderStripping = Boolean.TRUE.equals(call.getBoolean("disableExifHeaderStripping", false));
        final boolean lockOrientation = Boolean.TRUE.equals(call.getBoolean("lockAndroidOrientation", false));
        final boolean disableAudio = Boolean.TRUE.equals(call.getBoolean("disableAudio", true));
        this.lastDisableAudio = disableAudio;
        final String aspectRatio = call.getString("aspectRatio", "4:3");
        final String gridMode = call.getString("gridMode", "none");
        final String positioning = call.getString("positioning", "top");
        //noinspection DataFlowIssue
        final float initialZoomLevel = call.getFloat("initialZoomLevel", 1.0f);
        //noinspection DataFlowIssue
        final boolean disableFocusIndicator = call.getBoolean("disableFocusIndicator", false);
        final boolean enableVideoMode = Boolean.TRUE.equals(call.getBoolean("enableVideoMode", false));

        // Check for conflict between aspectRatio and size
        if (call.getData().has("aspectRatio") && (call.getData().has("width") || call.getData().has("height"))) {
            call.reject("Cannot set both aspectRatio and size (width/height). Use setPreviewSize after start.");
            return;
        }

        float targetZoom = initialZoomLevel;
        // Check if the selected device is a physical ultra-wide
        if (originalDeviceId != null) {
            List<CameraDevice> devices = CameraXView.getAvailableDevicesStatic(getContext());
            for (CameraDevice device : devices) {
                if (originalDeviceId.equals(device.getDeviceId()) && !device.isLogical()) {
                    for (LensInfo lens : device.getLenses()) {
                        if ("ultraWide".equals(lens.getDeviceType())) {
                            Log.d("CameraPreview", "Ultra-wide lens selected. Targeting 0.5x zoom on logical camera.");
                            targetZoom = 0.5f;
                            // Force the use of the logical camera by clearing the specific deviceId
                            deviceId = null;
                            break;
                        }
                    }
                }
                if (deviceId == null) break; // Exit outer loop once we've made our decision
            }
        }

        previousOrientationRequest = getBridge().getActivity().getRequestedOrientation();
        cameraXView = new CameraXView(getContext(), getBridge().getWebView());
        cameraXView.setListener(this);

        String finalDeviceId = deviceId;
        float finalTargetZoom = targetZoom;
        getBridge()
            .getActivity()
            .runOnUiThread(() -> {
                // Ensure transparent background when preview is behind the WebView (Android 10 fix)
                if (toBack) {
                    try {
                        if (originalWindowBackground == null) {
                            originalWindowBackground = getBridge().getActivity().getWindow().getDecorView().getBackground();
                        }
                        // Set to solid black first to prevent flickering during transition
                        // This provides a stable base before camera preview is ready
                        getBridge().getActivity().getWindow().setBackgroundDrawable(new ColorDrawable(Color.BLACK));
                    } catch (Exception ignored) {}
                }
                DisplayMetrics metrics = getBridge().getActivity().getResources().getDisplayMetrics();
                if (lockOrientation) {
                    getBridge().getActivity().setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LOCKED);
                }

                // Debug: Let's check all the positioning information
                ViewGroup webViewParent = (ViewGroup) getBridge().getWebView().getParent();

                // Get webview position in different coordinate systems
                int[] webViewLocationInWindow = new int[2];
                int[] webViewLocationOnScreen = new int[2];
                getBridge().getWebView().getLocationInWindow(webViewLocationInWindow);
                getBridge().getWebView().getLocationOnScreen(webViewLocationOnScreen);

                int webViewLeft = getBridge().getWebView().getLeft();
                int webViewTop = getBridge().getWebView().getTop();

                // Check parent position too
                int[] parentLocationInWindow = new int[2];
                int[] parentLocationOnScreen = new int[2];
                webViewParent.getLocationInWindow(parentLocationInWindow);
                webViewParent.getLocationOnScreen(parentLocationOnScreen);

                // Calculate pixel ratio
                float pixelRatio = metrics.density;

                // The key insight: JavaScript coordinates are relative to the WebView's viewport
                // If the WebView is positioned below the status bar (webViewLocationOnScreen[1] > 0),
                // we need to add that offset when placing native views
                int webViewTopInset = webViewLocationOnScreen[1];
                boolean isEdgeToEdgeActive = webViewLocationOnScreen[1] > 0;

                // Log all the positioning information for debugging
                Log.d("CameraPreview", "WebView Position Debug:");
                Log.d("CameraPreview", "  - webView.getTop(): " + webViewTop);
                Log.d("CameraPreview", "  - webView.getLeft(): " + webViewLeft);
                Log.d(
                    "CameraPreview",
                    "  - webView locationInWindow: (" + webViewLocationInWindow[0] + ", " + webViewLocationInWindow[1] + ")"
                );
                Log.d(
                    "CameraPreview",
                    "  - webView locationOnScreen: (" + webViewLocationOnScreen[0] + ", " + webViewLocationOnScreen[1] + ")"
                );
                Log.d(
                    "CameraPreview",
                    "  - parent locationInWindow: (" + parentLocationInWindow[0] + ", " + parentLocationInWindow[1] + ")"
                );
                Log.d(
                    "CameraPreview",
                    "  - parent locationOnScreen: (" + parentLocationOnScreen[0] + ", " + parentLocationOnScreen[1] + ")"
                );

                // Check if WebView has margins
                View webView = getBridge().getWebView();
                ViewGroup.LayoutParams webViewLayoutParams = webView.getLayoutParams();
                if (webViewLayoutParams instanceof ViewGroup.MarginLayoutParams) {
                    ViewGroup.MarginLayoutParams marginParams = (ViewGroup.MarginLayoutParams) webViewLayoutParams;
                    Log.d(
                        "CameraPreview",
                        "  - webView margins: left=" +
                            marginParams.leftMargin +
                            ", top=" +
                            marginParams.topMargin +
                            ", right=" +
                            marginParams.rightMargin +
                            ", bottom=" +
                            marginParams.bottomMargin
                    );
                }

                // Check WebView padding
                Log.d(
                    "CameraPreview",
                    "  - webView padding: left=" +
                        webView.getPaddingLeft() +
                        ", top=" +
                        webView.getPaddingTop() +
                        ", right=" +
                        webView.getPaddingRight() +
                        ", bottom=" +
                        webView.getPaddingBottom()
                );

                Log.d("CameraPreview", "  - Using webViewTopInset: " + webViewTopInset);
                Log.d("CameraPreview", "  - isEdgeToEdgeActive: " + isEdgeToEdgeActive);

                // Calculate position - center if x or y is -1
                int computedX;
                int computedY;

                // Calculate dimensions first
                int computedWidth = width != 0 ? (int) (width * pixelRatio) : getBridge().getWebView().getWidth();
                int computedHeight = height != 0 ? (int) (height * pixelRatio) : getBridge().getWebView().getHeight();
                computedHeight -= (int) (paddingBottom * pixelRatio);

                Log.d("CameraPreview", "========================");
                Log.d("CameraPreview", "POSITIONING CALCULATIONS:");
                Log.d("CameraPreview", "1. INPUT - x: " + x + ", y: " + y + ", width: " + width + ", height: " + height);
                Log.d("CameraPreview", "2. PIXEL RATIO: " + pixelRatio);
                Log.d("CameraPreview", "3. SCREEN - width: " + metrics.widthPixels + ", height: " + metrics.heightPixels);
                Log.d(
                    "CameraPreview",
                    "4. WEBVIEW - width: " + getBridge().getWebView().getWidth() + ", height: " + getBridge().getWebView().getHeight()
                );
                Log.d("CameraPreview", "5. COMPUTED DIMENSIONS - width: " + computedWidth + ", height: " + computedHeight);

                if (x == -1) {
                    // Center horizontally
                    int screenWidth = metrics.widthPixels;
                    computedX = (screenWidth - computedWidth) / 2;
                    Log.d(
                        "CameraPreview",
                        "Centering horizontally: screenWidth=" +
                            screenWidth +
                            ", computedWidth=" +
                            computedWidth +
                            ", computedX=" +
                            computedX
                    );
                } else {
                    computedX = (int) (x * pixelRatio);
                    Log.d("CameraPreview", "Using provided X position: " + x + " * " + pixelRatio + " = " + computedX);
                }

                if (y == -1) {
                    // Position vertically based on positioning parameter
                    int screenHeight = metrics.heightPixels;

                    switch (Objects.requireNonNull(positioning)) {
                        case "top":
                            computedY = 0;
                            Log.d("CameraPreview", "Positioning at top: computedY=0");
                            break;
                        case "bottom":
                            computedY = screenHeight - computedHeight;
                            Log.d(
                                "CameraPreview",
                                "Positioning at bottom: screenHeight=" +
                                    screenHeight +
                                    ", computedHeight=" +
                                    computedHeight +
                                    ", computedY=" +
                                    computedY
                            );
                            break;
                        case "center":
                        default:
                            // Center vertically
                            if (isEdgeToEdgeActive) {
                                // When WebView is offset from top, center within the available space
                                // The camera should be centered in the full screen, not just the WebView area
                                computedY = (screenHeight - computedHeight) / 2;
                                Log.d(
                                    "CameraPreview",
                                    "Centering vertically with WebView offset: screenHeight=" +
                                        screenHeight +
                                        ", webViewTop=" +
                                        webViewTopInset +
                                        ", computedHeight=" +
                                        computedHeight +
                                        ", computedY=" +
                                        computedY
                                );
                            } else {
                                // Normal mode - use full screen height
                                computedY = (screenHeight - computedHeight) / 2;
                                Log.d(
                                    "CameraPreview",
                                    "Centering vertically (normal): screenHeight=" +
                                        screenHeight +
                                        ", computedHeight=" +
                                        computedHeight +
                                        ", computedY=" +
                                        computedY
                                );
                            }
                            break;
                    }
                } else {
                    computedY = (int) (y * pixelRatio);
                    // If edge-to-edge is active, JavaScript Y is relative to WebView content area
                    // We need to add the inset to get absolute screen position
                    if (isEdgeToEdgeActive) {
                        computedY += webViewTopInset;
                        Log.d(
                            "CameraPreview",
                            "Edge-to-edge adjustment: Y position " +
                                (int) (y * pixelRatio) +
                                " + inset " +
                                webViewTopInset +
                                " = " +
                                computedY
                        );
                    }
                    Log.d(
                        "CameraPreview",
                        "Using provided Y position: " +
                            y +
                            " * " +
                            pixelRatio +
                            " = " +
                            computedY +
                            (isEdgeToEdgeActive ? " (adjusted for edge-to-edge)" : "")
                    );
                }

                Log.d(
                    "CameraPreview",
                    "2b. EDGE-TO-EDGE - " + (isEdgeToEdgeActive ? "ACTIVE (inset=" + webViewTopInset + ")" : "INACTIVE")
                );
                Log.d("CameraPreview", "3. COMPUTED POSITION - x=" + computedX + ", y=" + computedY);
                Log.d("CameraPreview", "4. COMPUTED SIZE - width=" + computedWidth + ", height=" + computedHeight);
                Log.d("CameraPreview", "=== COORDINATE DEBUG ===");
                Log.d("CameraPreview", "WebView getLeft/getTop: (" + webViewLeft + ", " + webViewTop + ")");
                Log.d(
                    "CameraPreview",
                    "WebView locationInWindow: (" + webViewLocationInWindow[0] + ", " + webViewLocationInWindow[1] + ")"
                );
                Log.d(
                    "CameraPreview",
                    "WebView locationOnScreen: (" + webViewLocationOnScreen[0] + ", " + webViewLocationOnScreen[1] + ")"
                );
                Log.d("CameraPreview", "Parent locationInWindow: (" + parentLocationInWindow[0] + ", " + parentLocationInWindow[1] + ")");
                Log.d("CameraPreview", "Parent locationOnScreen: (" + parentLocationOnScreen[0] + ", " + parentLocationOnScreen[1] + ")");
                Log.d("CameraPreview", "Parent class: " + webViewParent.getClass().getSimpleName());
                Log.d("CameraPreview", "Requested position (logical): (" + x + ", " + y + ")");
                Log.d("CameraPreview", "Pixel ratio: " + pixelRatio);
                Log.d("CameraPreview", "Final computed position (no offset): (" + computedX + ", " + computedY + ")");
                Log.d("CameraPreview", "5. IS_CENTERED - " + (x == -1 || y == -1));
                Log.d("CameraPreview", "========================");

                // Pass along whether we're centering so CameraXView knows not to add insets
                boolean isCentered = (x == -1 || y == -1);

                CameraSessionConfiguration config = new CameraSessionConfiguration(
                    finalDeviceId,
                    position,
                    computedX,
                    computedY,
                    computedWidth,
                    computedHeight,
                    paddingBottom,
                    toBack,
                    storeToFile,
                    enableOpacity,
                    disableExifHeaderStripping,
                    disableAudio,
                    1.0f,
                    aspectRatio,
                    gridMode,
                    disableFocusIndicator,
                    enableVideoMode
                );
                config.setTargetZoom(finalTargetZoom);
                config.setCentered(isCentered);

                bridge.saveCall(call);
                cameraStartCallbackId = call.getCallbackId();
                cameraXView.startSession(config);

                // Setup orientation listener to mirror iOS screenResize emission
                if (orientationListener == null) {
                    lastOrientation = getContext().getResources().getConfiguration().orientation;
                    lastOrientationStr = getDeviceOrientationString();
                    orientationListener = new OrientationEventListener(getContext()) {
                        @Override
                        public void onOrientationChanged(int orientation) {
                            if (orientation == ORIENTATION_UNKNOWN) return;
                            int current = getContext().getResources().getConfiguration().orientation;
                            String currentStr = getDeviceOrientationString();
                            if (current != lastOrientation || !Objects.equals(currentStr, lastOrientationStr)) {
                                lastOrientation = current;
                                lastOrientationStr = currentStr;
                                // Post to next frame so WebView has updated bounds before we recompute layout
                                getBridge()
                                    .getActivity()
                                    .getWindow()
                                    .getDecorView()
                                    .post(() -> handleOrientationChange());
                            }
                        }
                    };
                    if (orientationListener.canDetectOrientation()) {
                        orientationListener.enable();
                    }
                }
            });
    }

    private void handleOrientationChange() {
        if (cameraXView == null || !cameraXView.isRunning()) return;

        Log.d(TAG, "======================== ORIENTATION CHANGE DETECTED ========================");

        // Get comprehensive display and orientation information
        android.util.DisplayMetrics metrics = getContext().getResources().getDisplayMetrics();
        int screenWidthPx = metrics.widthPixels;
        int screenHeightPx = metrics.heightPixels;
        float density = metrics.density;
        int screenWidthDp = (int) (screenWidthPx / density);
        int screenHeightDp = (int) (screenHeightPx / density);

        int current = getContext().getResources().getConfiguration().orientation;
        Log.d(TAG, "New orientation: " + current + " (1=PORTRAIT, 2=LANDSCAPE)");
        Log.d(
            TAG,
            "Screen dimensions - Pixels: " +
                screenWidthPx +
                "x" +
                screenHeightPx +
                ", DP: " +
                screenWidthDp +
                "x" +
                screenHeightDp +
                ", Density: " +
                density
        );

        // Get WebView dimensions before rotation
        WebView webView = getBridge().getWebView();
        int webViewWidth = webView.getWidth();
        int webViewHeight = webView.getHeight();
        Log.d(TAG, "WebView dimensions: " + webViewWidth + "x" + webViewHeight);

        // Get current preview bounds before rotation
        int[] oldBounds = cameraXView.getCurrentPreviewBounds();
        Log.d(
            TAG,
            "Current preview bounds before rotation: x=" +
                oldBounds[0] +
                ", y=" +
                oldBounds[1] +
                ", width=" +
                oldBounds[2] +
                ", height=" +
                oldBounds[3]
        );

        getBridge()
            .getActivity()
            .runOnUiThread(() -> {
                // Create and show a black full-screen overlay during rotation
                ViewGroup rootView = (ViewGroup) getBridge().getActivity().getWindow().getDecorView().getRootView();

                // Remove any existing overlay
                if (rotationOverlay != null && rotationOverlay.getParent() != null) {
                    ((ViewGroup) rotationOverlay.getParent()).removeView(rotationOverlay);
                }

                // Create new black overlay
                rotationOverlay = new View(getContext());
                rotationOverlay.setBackgroundColor(Color.BLACK);
                ViewGroup.LayoutParams overlayParams = new ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                );
                rotationOverlay.setLayoutParams(overlayParams);
                rootView.addView(rotationOverlay);

                // Reapply current aspect ratio to recompute layout, then emit screenResize
                String ar = cameraXView.getAspectRatio();
                Log.d(TAG, "Reapplying aspect ratio: " + ar);

                // Re-get dimensions after potential layout pass
                android.util.DisplayMetrics newMetrics = getContext().getResources().getDisplayMetrics();
                int newScreenWidthPx = newMetrics.widthPixels;
                int newScreenHeightPx = newMetrics.heightPixels;
                int newWebViewWidth = webView.getWidth();
                int newWebViewHeight = webView.getHeight();

                Log.d(TAG, "New screen dimensions after rotation: " + newScreenWidthPx + "x" + newScreenHeightPx);
                Log.d(TAG, "New WebView dimensions after rotation: " + newWebViewWidth + "x" + newWebViewHeight);

                // Force aspect ratio recalculation on orientation change
                cameraXView.forceAspectRatioRecalculation(ar, null, null, () -> {
                    int[] bounds = cameraXView.getCurrentPreviewBounds();
                    Log.d(
                        TAG,
                        "New bounds after orientation change: x=" +
                            bounds[0] +
                            ", y=" +
                            bounds[1] +
                            ", width=" +
                            bounds[2] +
                            ", height=" +
                            bounds[3]
                    );
                    Log.d(
                        TAG,
                        "Bounds change: deltaX=" +
                            (bounds[0] - oldBounds[0]) +
                            ", deltaY=" +
                            (bounds[1] - oldBounds[1]) +
                            ", deltaWidth=" +
                            (bounds[2] - oldBounds[2]) +
                            ", deltaHeight=" +
                            (bounds[3] - oldBounds[3])
                    );

                    JSObject data = new JSObject();
                    data.put("x", bounds[0]);
                    data.put("y", bounds[1]);
                    data.put("width", bounds[2]);
                    data.put("height", bounds[3]);
                    notifyListeners("screenResize", data);

                    // Also emit orientationChange with a unified string value matching iOS
                    String o = getDeviceOrientationString();
                    JSObject oData = new JSObject();
                    oData.put("orientation", o);
                    notifyListeners("orientationChange", oData);

                    // Don't remove the overlay here - wait for camera to fully start
                    // The overlay will be removed after a delay to ensure camera is stable
                    if (rotationOverlay != null && rotationOverlay.getParent() != null) {
                        // Shorter delay for faster transition
                        int delay = "4:3".equals(ar) ? 200 : 150;
                        rotationOverlay.postDelayed(
                            () -> {
                                if (rotationOverlay != null && rotationOverlay.getParent() != null) {
                                    rotationOverlay
                                        .animate()
                                        .alpha(0f)
                                        .setDuration(100) // Faster fade out
                                        .withEndAction(() -> {
                                            if (rotationOverlay != null && rotationOverlay.getParent() != null) {
                                                ((ViewGroup) rotationOverlay.getParent()).removeView(rotationOverlay);
                                                rotationOverlay = null;
                                            }
                                        })
                                        .start();
                                }
                            },
                            delay
                        );
                    }

                    Log.d(TAG, "================================================================================");
                });
            });
    }

    /**
     * Compute a canonical orientation string matching iOS values:
     * "portrait", "portrait-upside-down", "landscape-left", "landscape-right", or "unknown".
     * Uses display rotation when available, with a fallback to configuration orientation.
     */
    private String getDeviceOrientationString() {
        try {
            int rotation = -1;
            // Try to obtain display rotation in a backward/forward-compatible way
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                android.view.Display display = getBridge().getActivity().getDisplay();
                if (display != null) {
                    rotation = display.getRotation();
                }
            } else {
                android.view.Display display = getBridge().getActivity().getWindowManager().getDefaultDisplay();
                if (display != null) {
                    rotation = display.getRotation();
                }
            }

            if (rotation == android.view.Surface.ROTATION_0) {
                return "portrait";
            } else if (rotation == android.view.Surface.ROTATION_90) {
                return "landscape-right";
            } else if (rotation == android.view.Surface.ROTATION_180) {
                return "portrait-upside-down";
            } else if (rotation == android.view.Surface.ROTATION_270) {
                return "landscape-left";
            }

            // Fallback to configuration if rotation unavailable
            int orientation = getContext().getResources().getConfiguration().orientation;
            if (orientation == Configuration.ORIENTATION_PORTRAIT) return "portrait";
            if (orientation == Configuration.ORIENTATION_LANDSCAPE) return "landscape-right"; // default, avoid generic
            return "unknown";
        } catch (Throwable t) {
            Log.w(TAG, "Failed to get precise orientation, falling back: " + t);
            int orientation = getContext().getResources().getConfiguration().orientation;
            if (orientation == Configuration.ORIENTATION_PORTRAIT) return "portrait";
            if (orientation == Configuration.ORIENTATION_LANDSCAPE) return "landscape-right"; // default, avoid generic
            return "unknown";
        }
    }

    @Override
    public void onPictureTaken(String base64, JSONObject exif) {
        PluginCall pluginCall = bridge.getSavedCall(captureCallbackId);
        if (pluginCall == null) {
            Log.e("CameraPreview", "onPictureTaken: captureCallbackId is null");
            return;
        }
        JSObject result = new JSObject();
        result.put("value", base64);
        result.put("exif", exif);
        pluginCall.resolve(result);
        bridge.releaseCall(pluginCall);
    }

    @Override
    public void onPictureTakenError(String message) {
        PluginCall pluginCall = bridge.getSavedCall(captureCallbackId);
        if (pluginCall == null) {
            Log.e("CameraPreview", "onPictureTakenError: captureCallbackId is null");
            return;
        }
        pluginCall.reject(message);
        bridge.releaseCall(pluginCall);
    }

    @Override
    public void onCameraStopped(CameraXView source) {
        if (cameraXView != null && cameraXView != source) {
            Log.d(TAG, "onCameraStopped: ignoring callback from stale instance");
            return;
        }
        // Ensure reference is cleared once the originating CameraXView has fully stopped
        if (cameraXView == source) {
            cameraXView = null;
        }

        PluginCall queuedCall = null;
        synchronized (pendingStartLock) {
            if (pendingStartCall != null) {
                queuedCall = pendingStartCall;
                pendingStartCall = null;
            }
        }

        if (queuedCall != null) {
            PluginCall finalQueuedCall = queuedCall;
            Log.d(TAG, "onCameraStopped: replaying pending start request");
            getBridge()
                .getActivity()
                .runOnUiThread(() -> start(finalQueuedCall));
        }
    }

    private JSObject getViewSize(double x, double y, double width, double height) {
        JSObject ret = new JSObject();
        // Return values with proper rounding to avoid gaps
        // For positions (x, y): ceil to avoid gaps at top/left
        // For dimensions (width, height): floor to avoid gaps at bottom/right
        ret.put("x", Math.ceil(x));
        ret.put("y", Math.ceil(y));
        ret.put("width", Math.floor(width));
        ret.put("height", Math.floor(height));
        return ret;
    }

    @Override
    public void onCameraStarted(int width, int height, int x, int y) {
        PluginCall call = bridge.getSavedCall(cameraStartCallbackId);
        if (call != null) {
            // Convert pixel values back to logical units
            DisplayMetrics metrics = getBridge().getActivity().getResources().getDisplayMetrics();
            float pixelRatio = metrics.density;

            // When WebView is offset from the top (e.g., below status bar),
            // we need to convert between JavaScript coordinates (relative to WebView)
            // and native coordinates (relative to screen)
            WebView webView = getBridge().getWebView();
            int webViewTopInset = 0;
            boolean isEdgeToEdgeActive = false;
            if (webView != null) {
                int[] location = new int[2];
                webView.getLocationOnScreen(location);
                webViewTopInset = location[1];
                isEdgeToEdgeActive = webViewTopInset > 0;
            }

            // Only convert to relative position if edge-to-edge is active
            int relativeY = isEdgeToEdgeActive ? (y - webViewTopInset) : y;

            Log.d("CameraPreview", "========================");
            Log.d("CameraPreview", "CAMERA STARTED - POSITION RETURNED:");
            Log.d("CameraPreview", "7. RETURNED (pixels) - x=" + x + ", y=" + y + ", width=" + width + ", height=" + height);
            Log.d("CameraPreview", "8. EDGE-TO-EDGE - " + (isEdgeToEdgeActive ? "ACTIVE" : "INACTIVE"));
            Log.d("CameraPreview", "9. WEBVIEW INSET - " + webViewTopInset);
            Log.d(
                "CameraPreview",
                "10. RELATIVE Y - " + relativeY + " (y=" + y + (isEdgeToEdgeActive ? " - inset=" + webViewTopInset : " unchanged") + ")"
            );
            Log.d(
                "CameraPreview",
                "11. RETURNED (logical) - x=" +
                    (x / pixelRatio) +
                    ", y=" +
                    (relativeY / pixelRatio) +
                    ", width=" +
                    (width / pixelRatio) +
                    ", height=" +
                    (height / pixelRatio)
            );
            Log.d("CameraPreview", "12. PIXEL RATIO - " + pixelRatio);
            Log.d("CameraPreview", "========================");

            // Calculate logical values with proper rounding to avoid sub-pixel issues
            double logicalWidth = width / pixelRatio;
            double logicalHeight = height / pixelRatio;
            double logicalX = x / pixelRatio;
            double logicalY = relativeY / pixelRatio;

            JSObject result = getViewSize(logicalX, logicalY, logicalWidth, logicalHeight);

            // Log exact calculations to debug one-pixel difference
            Log.d("CameraPreview", "========================");
            Log.d("CameraPreview", "FINAL POSITION CALCULATIONS:");
            Log.d("CameraPreview", "Pixel values: x=" + x + ", y=" + relativeY + ", width=" + width + ", height=" + height);
            Log.d("CameraPreview", "Pixel ratio: " + pixelRatio);
            Log.d(
                "CameraPreview",
                "Logical values (exact): x=" + logicalX + ", y=" + logicalY + ", width=" + logicalWidth + ", height=" + logicalHeight
            );
            Log.d(
                "CameraPreview",
                "Logical values (rounded): x=" +
                    Math.round(logicalX) +
                    ", y=" +
                    Math.round(logicalY) +
                    ", width=" +
                    Math.round(logicalWidth) +
                    ", height=" +
                    Math.round(logicalHeight)
            );

            // Check if previewContainer has any padding or margin that might cause offset
            if (cameraXView != null) {
                View previewContainer = cameraXView.getPreviewContainer();
                if (previewContainer != null) {
                    Log.d(
                        "CameraPreview",
                        "PreviewContainer padding: left=" +
                            previewContainer.getPaddingLeft() +
                            ", top=" +
                            previewContainer.getPaddingTop() +
                            ", right=" +
                            previewContainer.getPaddingRight() +
                            ", bottom=" +
                            previewContainer.getPaddingBottom()
                    );
                    ViewGroup.LayoutParams params = previewContainer.getLayoutParams();
                    if (params instanceof ViewGroup.MarginLayoutParams) {
                        ViewGroup.MarginLayoutParams marginParams = (ViewGroup.MarginLayoutParams) params;
                        Log.d(
                            "CameraPreview",
                            "PreviewContainer margins: left=" +
                                marginParams.leftMargin +
                                ", top=" +
                                marginParams.topMargin +
                                ", right=" +
                                marginParams.rightMargin +
                                ", bottom=" +
                                marginParams.bottomMargin
                        );
                    }
                }
            }
            Log.d("CameraPreview", "========================");

            // Log what we're returning
            Log.d(
                "CameraPreview",
                "Returning to JS - x: " +
                    logicalX +
                    " (from " +
                    logicalX +
                    "), y: " +
                    logicalY +
                    " (from " +
                    logicalY +
                    "), width: " +
                    logicalWidth +
                    " (from " +
                    logicalWidth +
                    "), height: " +
                    logicalHeight +
                    " (from " +
                    logicalHeight +
                    ")"
            );
            
            // Transition window background to transparent now that camera is ready
            // This prevents flickering during camera initialization
            boolean toBack = cameraXView != null && cameraXView.getSessionConfig() != null && cameraXView.getSessionConfig().isToBack();
            if (toBack) {
                try {
                    getBridge().getActivity().runOnUiThread(() -> {
                        try {
                            getBridge().getActivity().getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
                        } catch (Exception ignored) {}
                    });
                } catch (Exception ignored) {}
            }

            call.resolve(result);
            bridge.releaseCall(call);
            cameraStartCallbackId = null; // Prevent re-use
        }
    }

    @Override
    public void onSampleTaken(String result) {
        PluginCall call = bridge.getSavedCall(sampleCallbackId);
        if (call != null) {
            JSObject ret = new JSObject();
            ret.put("value", result);
            call.resolve(ret);
            bridge.releaseCall(call);
            sampleCallbackId = null;
        } else {
            Log.w("CameraPreview", "onSampleTaken: no pending call to resolve");
        }
    }

    @Override
    public void onSampleTakenError(String message) {
        PluginCall call = bridge.getSavedCall(sampleCallbackId);
        if (call != null) {
            call.reject(message);
            bridge.releaseCall(call);
            sampleCallbackId = null;
        } else {
            Log.e("CameraPreview", "Sample taken error (no pending call): " + message);
        }
    }

    @Override
    public void onCameraStartError(String message) {
        PluginCall call = bridge.getSavedCall(cameraStartCallbackId);
        if (call != null) {
            call.reject(message);
            bridge.releaseCall(call);
            cameraStartCallbackId = null;
        }
        
        // Restore original window background on error to prevent black screen
        if (originalWindowBackground != null) {
            try {
                getBridge().getActivity().runOnUiThread(() -> {
                    try {
                        getBridge().getActivity().getWindow().setBackgroundDrawable(originalWindowBackground);
                        originalWindowBackground = null;
                    } catch (Exception ignored) {}
                });
            } catch (Exception ignored) {}
        }
    }

    @PluginMethod
    public void setAspectRatio(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        String aspectRatio = call.getString("aspectRatio", "4:3");
        Float x = call.getFloat("x");
        Float y = call.getFloat("y");

        getActivity().runOnUiThread(() -> {
            cameraXView.setAspectRatio(aspectRatio, x, y, () -> {
                // Return the actual preview bounds after layout and camera operations are complete
                int[] bounds = cameraXView.getCurrentPreviewBounds();
                JSObject ret = new JSObject();
                ret.put("x", bounds[0]);
                ret.put("y", bounds[1]);
                ret.put("width", bounds[2]);
                ret.put("height", bounds[3]);
                call.resolve(ret);
            });
        });
    }

    @PluginMethod
    public void getAspectRatio(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        String aspectRatio = cameraXView.getAspectRatio();
        JSObject ret = new JSObject();
        ret.put("aspectRatio", aspectRatio);
        call.resolve(ret);
    }

    @PluginMethod
    public void setGridMode(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        String gridMode = call.getString("gridMode", "none");
        getActivity().runOnUiThread(() -> {
            cameraXView.setGridMode(gridMode);
            call.resolve();
        });
    }

    @PluginMethod
    public void getGridMode(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }
        JSObject ret = new JSObject();
        ret.put("gridMode", cameraXView.getGridMode());
        call.resolve(ret);
    }

    @PluginMethod
    public void getPreviewSize(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }

        // Convert pixel values back to logical units
        DisplayMetrics metrics = getBridge().getActivity().getResources().getDisplayMetrics();
        float pixelRatio = metrics.density;

        JSObject ret = new JSObject();
        // Use same rounding strategy as start method
        double x = Math.ceil(cameraXView.getPreviewX() / pixelRatio);
        double y = Math.ceil(cameraXView.getPreviewY() / pixelRatio);
        double width = Math.floor(cameraXView.getPreviewWidth() / pixelRatio);
        double height = Math.floor(cameraXView.getPreviewHeight() / pixelRatio);

        Log.d("CameraPreview", "getPreviewSize: x=" + x + ", y=" + y + ", width=" + width + ", height=" + height);
        ret.put("x", x);
        ret.put("y", y);
        ret.put("width", width);
        ret.put("height", height);
        call.resolve(ret);
    }

    @PluginMethod
    public void setPreviewSize(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }

        // Get values from call - null values will become 0
        Integer xParam = call.getInt("x");
        Integer yParam = call.getInt("y");
        Integer widthParam = call.getInt("width");
        Integer heightParam = call.getInt("height");

        // Apply pixel ratio conversion to non-null values
        DisplayMetrics metrics = getBridge().getActivity().getResources().getDisplayMetrics();
        float pixelRatio = metrics.density;

        // Check if edge-to-edge mode is active
        WebView webView = getBridge().getWebView();
        int webViewTopInset = 0;
        boolean isEdgeToEdgeActive = false;
        if (webView != null) {
            int[] location = new int[2];
            webView.getLocationOnScreen(location);
            webViewTopInset = location[1];
            isEdgeToEdgeActive = webViewTopInset > 0;
        }

        int x = (xParam != null && xParam > 0) ? (int) (xParam * pixelRatio) : 0;
        int y = (yParam != null && yParam > 0) ? (int) (yParam * pixelRatio) : 0;

        // Add edge-to-edge inset to Y if active
        if (isEdgeToEdgeActive && y > 0) {
            y += webViewTopInset;
        }
        int width = (widthParam != null && widthParam > 0) ? (int) (widthParam * pixelRatio) : 0;
        int height = (heightParam != null && heightParam > 0) ? (int) (heightParam * pixelRatio) : 0;

        cameraXView.setPreviewSize(x, y, width, height, () -> {
            // Return the actual preview bounds after layout operations are complete
            int[] bounds = cameraXView.getCurrentPreviewBounds();
            JSObject ret = new JSObject();
            ret.put("x", bounds[0]);
            ret.put("y", bounds[1]);
            ret.put("width", bounds[2]);
            ret.put("height", bounds[3]);
            call.resolve(ret);
        });
    }

    @PluginMethod
    public void deleteFile(PluginCall call) {
        String path = call.getString("path");
        if (path == null || path.isEmpty()) {
            call.reject("path parameter is required");
            return;
        }
        try {
            java.io.File f = new java.io.File(Objects.requireNonNull(Uri.parse(path).getPath()));
            boolean deleted = f.exists() && f.delete();
            JSObject ret = new JSObject();
            ret.put("success", deleted);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Failed to delete file: " + e.getMessage());
        }
    }

    @PluginMethod
    public void startRecordVideo(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }

        boolean disableAudio = call.getBoolean("disableAudio") != null
            ? Boolean.TRUE.equals(call.getBoolean("disableAudio"))
            : this.lastDisableAudio;
        this.lastDisableAudio = disableAudio;
        String permissionAlias = disableAudio ? CAMERA_ONLY_PERMISSION_ALIAS : CAMERA_WITH_AUDIO_PERMISSION_ALIAS;

        if (PermissionState.GRANTED.equals(getPermissionState(permissionAlias))) {
            try {
                cameraXView.startRecordVideo();
                call.resolve();
            } catch (Exception e) {
                call.reject("Failed to start video recording: " + e.getMessage());
            }
        } else {
            requestPermissionForAlias(permissionAlias, call, "handleVideoRecordingPermissionResult");
        }
    }

    @PluginMethod
    public void stopRecordVideo(PluginCall call) {
        if (cameraXView == null || !cameraXView.isRunning()) {
            call.reject("Camera is not running");
            return;
        }

        try {
            bridge.saveCall(call);
            final String cbId = call.getCallbackId();
            cameraXView.stopRecordVideo(
                new CameraXView.VideoRecordingCallback() {
                    @Override
                    public void onSuccess(String filePath) {
                        PluginCall saved = bridge.getSavedCall(cbId);
                        if (saved != null) {
                            JSObject result = new JSObject();
                            result.put("videoFilePath", filePath);
                            saved.resolve(result);
                            bridge.releaseCall(saved);
                        }
                    }

                    @Override
                    public void onError(String message) {
                        PluginCall saved = bridge.getSavedCall(cbId);
                        if (saved != null) {
                            saved.reject("Failed to stop video recording: " + message);
                            bridge.releaseCall(saved);
                        }
                    }
                }
            );
        } catch (Exception e) {
            call.reject("Failed to stop video recording: " + e.getMessage());
        }
    }

    @PermissionCallback
    private void handleVideoRecordingPermissionResult(PluginCall call) {
        // Use the persisted session value to determine which permission we requested
        String permissionAlias = this.lastDisableAudio ? CAMERA_ONLY_PERMISSION_ALIAS : CAMERA_WITH_AUDIO_PERMISSION_ALIAS;

        // Check if either permission is granted (mirroring handleCameraPermissionResult)
        if (
            PermissionState.GRANTED.equals(getPermissionState(CAMERA_ONLY_PERMISSION_ALIAS)) ||
            PermissionState.GRANTED.equals(getPermissionState(CAMERA_WITH_AUDIO_PERMISSION_ALIAS))
        ) {
            try {
                cameraXView.startRecordVideo();
                call.resolve();
            } catch (Exception e) {
                call.reject("Failed to start video recording: " + e.getMessage());
            }
        } else {
            call.reject("camera permission denied. enable camera access in Settings.", "cameraPermissionDenied");
        }
    }

    @PluginMethod
    public void getSafeAreaInsets(PluginCall call) {
        JSObject ret = new JSObject();
        int orientation = getContext().getResources().getConfiguration().orientation;

        int notchInsetPx = 0;

        try {
            View decorView = getBridge().getActivity().getWindow().getDecorView();
            WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(decorView);

            if (insets != null) {
                // Get display cutout insets (notch, punch hole, etc.)
                // this.Capacitor.Plugins.CameraPreview.getSafeAreaInsets()
                Insets cutout = insets.getInsets(WindowInsetsCompat.Type.displayCutout());

                // Get system bars insets (status bar, navigation bars)
                Insets sysBars = insets.getInsets(WindowInsetsCompat.Type.systemBars());

                // In portrait mode, notch is at the top
                // In landscape mode, notch is typically at the left side (or right, but left is more common)
                if (orientation == Configuration.ORIENTATION_PORTRAIT) {
                    // Portrait: return top inset (notch/status bar)
                    notchInsetPx = Math.max(cutout.top, sysBars.top);
                } else if (orientation == Configuration.ORIENTATION_LANDSCAPE) {
                    // Landscape: return left inset (notch moved to side)
                    notchInsetPx = Math.max(cutout.left, sysBars.left);
                    // Additional fallback: some devices might have the notch on the right in landscape
                    // If left is 0, check right side as well
                    if (notchInsetPx == 0) {
                        notchInsetPx = Math.max(cutout.right, sysBars.right);
                    }
                } else {
                    // Unknown orientation, default to top
                    notchInsetPx = Math.max(cutout.top, sysBars.top);
                }
            } else {
                // Fallback to status bar height if WindowInsets are not available
                notchInsetPx = getStatusBarHeightPx();
            }
        } catch (Exception e) {
            // Final fallback
            notchInsetPx = getStatusBarHeightPx();
        }

        // Convert pixels to dp for consistency with JS layout units
        float density = getContext().getResources().getDisplayMetrics().density;
        ret.put("orientation", orientation);
        ret.put("top", notchInsetPx / density);
        call.resolve(ret);
    }

    private int getStatusBarHeightPx() {
        int result = 0;
        @SuppressLint("InternalInsetResource")
        int resourceId = getContext().getResources().getIdentifier("status_bar_height", "dimen", "android");
        if (resourceId > 0) {
            result = getContext().getResources().getDimensionPixelSize(resourceId);
        }
        return result;
    }

    @PluginMethod
    public void getPluginVersion(final PluginCall call) {
        try {
            final JSObject ret = new JSObject();
            ret.put("version", this.pluginVersion);
            call.resolve(ret);
        } catch (final Exception e) {
            call.reject("Could not get plugin version", e);
        }
    }
}
