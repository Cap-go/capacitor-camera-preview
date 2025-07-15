package com.ahm.capacitor.camera.preview;

import static android.Manifest.permission.CAMERA;
import static android.Manifest.permission.RECORD_AUDIO;

import android.content.Context;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.graphics.Point;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Display;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import androidx.annotation.NonNull;
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
import com.ahm.capacitor.camera.preview.model.CameraDevice;
import com.ahm.capacitor.camera.preview.model.CameraSessionConfiguration;
import com.ahm.capacitor.camera.preview.model.ZoomFactors;
import com.ahm.capacitor.camera.preview.model.CameraLens;
import com.ahm.capacitor.camera.preview.Camera2View;
import java.util.List;
import java.util.Objects;

@CapacitorPlugin(
  name = "CameraPreview",
  permissions = {
    @Permission(
      strings = { CAMERA, RECORD_AUDIO },
      alias = CameraPreview.CAMERA_WITH_AUDIO_PERMISSION_ALIAS
    ),
    @Permission(
      strings = { CAMERA },
      alias = CameraPreview.CAMERA_ONLY_PERMISSION_ALIAS
    ),
  }
)
public class CameraPreview
  extends Plugin
  implements Camera2View.Camera2ViewListener {

  static final String CAMERA_WITH_AUDIO_PERMISSION_ALIAS = "cameraWithAudio";
  static final String CAMERA_ONLY_PERMISSION_ALIAS = "cameraOnly";

  private String captureCallbackId = "";
  private String snapshotCallbackId = "";
  private String cameraStartCallbackId = "";

  // keep track of previously specified orientation to support locking orientation:
  private int previousOrientationRequest =
    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;

  private Camera2View camera2View;

  @PluginMethod
  public void start(PluginCall call) {
    boolean disableAudio = call.getBoolean("disableAudio", true); // Default to true (camera only)
    String permissionAlias = disableAudio
      ? CAMERA_ONLY_PERMISSION_ALIAS
      : CAMERA_WITH_AUDIO_PERMISSION_ALIAS;

    if (PermissionState.GRANTED.equals(getPermissionState(permissionAlias))) {
      startCamera(call);
    } else {
      requestPermissionForAlias(
        permissionAlias,
        call,
        "handleCameraPermissionResult"
      );
    }
  }

  @PluginMethod
  public void flip(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    Logger.debug(getLogTag(), "flip: Starting camera flip");
    try {
      camera2View.flipCamera();
      Logger.debug(getLogTag(), "flip: Camera flip completed successfully");
      call.resolve();
    } catch (Exception e) {
      Logger.debug(getLogTag(), "flip: Camera flip exception: " + e.getMessage());
      call.reject("failed to flip camera: " + e.getMessage());
    }
  }

  @PluginMethod
  public void setOpacity(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    // Opacity setting is not supported in Camera2View for now
    call.reject("setOpacity is not supported in Camera2 implementation");
  }

  @PluginMethod
  public void capture(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    bridge.saveCall(call);
    captureCallbackId = call.getCallbackId();

    Integer quality = Objects.requireNonNull(call.getInt("quality", 85));
    camera2View.capturePhoto(quality);
  }

  @PluginMethod
  public void captureSample(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    bridge.saveCall(call);
    snapshotCallbackId = call.getCallbackId();

    Integer quality = Objects.requireNonNull(call.getInt("quality", 85));
    camera2View.captureSample(quality);
  }

  @PluginMethod
  public void getSupportedPictureSizes(final PluginCall call) {
    try {
      if (camera2View == null) {
        camera2View = new Camera2View(getContext(), getBridge().getWebView());
      }

      JSArray ret = new JSArray();

      // Get available devices and their picture sizes
      List<CameraDevice> devices = camera2View.getAvailableDevices();
      for (CameraDevice device : devices) {
        JSObject cameraInfo = new JSObject();
        cameraInfo.put("facing", device.getPosition().equals("front") ? "Front" : "Back");

        JSArray supportedPictureSizes = new JSArray();

        // Add some common sizes (could be enhanced to get actual sizes from camera characteristics)
        JSObject size1 = new JSObject();
        size1.put("width", 1920);
        size1.put("height", 1080);
        supportedPictureSizes.put(size1);

        JSObject size2 = new JSObject();
        size2.put("width", 1280);
        size2.put("height", 720);
        supportedPictureSizes.put(size2);

        JSObject size3 = new JSObject();
        size3.put("width", 640);
        size3.put("height", 480);
        supportedPictureSizes.put(size3);

        cameraInfo.put("supportedPictureSizes", supportedPictureSizes);
        ret.put(cameraInfo);
      }

      JSObject finalRet = new JSObject();
      finalRet.put("supportedPictureSizes", ret);
      call.resolve(finalRet);
    } catch (Exception e) {
      Logger.debug(getLogTag(), "Error getting supported picture sizes: " + e.getMessage());
      call.reject("Error getting supported picture sizes: " + e.getMessage());
    }
  }

  @PluginMethod
  public void stop(final PluginCall call) {
    bridge
      .getActivity()
      .runOnUiThread(
        new Runnable() {
          @Override
          public void run() {
            // allow orientation changes after closing camera:
            getBridge()
              .getActivity()
              .setRequestedOrientation(previousOrientationRequest);

            if (camera2View != null && camera2View.isRunning()) {
              camera2View.stopSession();
              camera2View = null;
              call.resolve();
            } else {
              call.reject("camera already stopped");
            }
          }
        }
      );
  }

  @PluginMethod
  public void getSupportedFlashModes(PluginCall call) {
    try {
      if (camera2View == null) {
        camera2View = new Camera2View(getContext(), getBridge().getWebView());
      }

      List<String> supportedFlashModes = camera2View.getSupportedFlashModes();
      JSArray jsonFlashModes = new JSArray();

      for (String mode : supportedFlashModes) {
        jsonFlashModes.put(mode);
      }

      JSObject jsObject = new JSObject();
      jsObject.put("result", jsonFlashModes);
      call.resolve(jsObject);
    } catch (Exception e) {
      Logger.debug(getLogTag(), "Error getting supported flash modes: " + e.getMessage());
      call.reject("Error getting supported flash modes: " + e.getMessage());
    }
  }

  @PluginMethod
  public void getHorizontalFov(PluginCall call) {
    try {
      if (camera2View == null) {
        camera2View = new Camera2View(getContext(), getBridge().getWebView());
      }

      // For now, return a default value as Camera2 FOV calculation is more complex
      JSObject jsObject = new JSObject();
      jsObject.put("result", 60.0); // Default FOV value
      call.resolve(jsObject);
    } catch (Exception e) {
      Logger.debug(getLogTag(), "Error getting horizontal FOV: " + e.getMessage());
      call.reject("Error getting horizontal FOV: " + e.getMessage());
    }
  }

  @PluginMethod
  public void setFlashMode(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    String flashMode = call.getString("flashMode");
    if (flashMode == null || flashMode.isEmpty()) {
      call.reject("flashMode required parameter is missing");
      return;
    }

    try {
      camera2View.setFlashMode(flashMode);
      call.resolve();
    } catch (Exception e) {
      call.reject("Failed to set flash mode: " + e.getMessage());
    }
  }

  @PluginMethod
  public void isRunning(PluginCall call) {
    boolean running = camera2View != null && camera2View.isRunning();
    JSObject jsObject = new JSObject();
    jsObject.put("isRunning", running);
    call.resolve(jsObject);
  }

  @PluginMethod
  public void getAvailableDevices(PluginCall call) {
    Logger.debug(getLogTag(), "getAvailableDevices called");

    if (camera2View == null) {
      Logger.debug(getLogTag(), "Creating temporary Camera2View to get device list");
      camera2View = new Camera2View(getContext(), getBridge().getWebView());
    }

    try {
      List<CameraDevice> devices = camera2View.getAvailableDevices();
      Logger.debug(getLogTag(), "Found " + devices.size() + " camera devices");

      JSArray devicesArray = new JSArray();

      for (CameraDevice device : devices) {
        Logger.debug(getLogTag(), "Device: ID=" + device.getDeviceId() +
                    ", Label=" + device.getLabel() +
                    ", Position=" + device.getPosition() +
                    ", Type=" + device.getDeviceType());

        JSObject deviceJson = new JSObject();
        deviceJson.put("deviceId", device.getDeviceId());
        deviceJson.put("label", device.getLabel());
        deviceJson.put("position", device.getPosition());
        deviceJson.put("deviceType", device.getDeviceType());
        devicesArray.put(deviceJson);
      }

      JSObject result = new JSObject();
      result.put("devices", devicesArray);
      Logger.debug(getLogTag(), "Returning " + devicesArray.length() + " devices to client");
      call.resolve(result);
    } catch (Exception e) {
      Logger.error(getLogTag(), "Error getting available devices", e);
      call.reject("Error getting available devices: " + e.getMessage());
    }
  }

  @PluginMethod
  public void getZoom(PluginCall call) {
    try {
      if (camera2View == null) {
        camera2View = new Camera2View(getContext(), getBridge().getWebView());
      }

      ZoomFactors zoomFactors = camera2View.getZoomFactors();
      Logger.debug(getLogTag(), "Zoom factors: " + zoomFactors.getMin() + ", " + zoomFactors.getMax() + ", " + zoomFactors.getCurrent());
      JSObject result = new JSObject();
      result.put("min", zoomFactors.getMin());
      result.put("max", zoomFactors.getMax());
      result.put("current", zoomFactors.getCurrent());
      call.resolve(result);
    } catch (Exception e) {
      Logger.debug(getLogTag(), "Error getting zoom capabilities: " + e.getMessage());
      call.reject("Error getting zoom capabilities: " + e.getMessage());
    }
  }

  @PluginMethod
  public void setZoom(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    Float level = call.getFloat("level");
    if (level == null) {
      call.reject("level parameter is required");
      return;
    }

    try {
      camera2View.setZoom(level);
      call.resolve();
    } catch (Exception e) {
      call.reject("Failed to set zoom: " + e.getMessage());
    }
  }

  @PluginMethod
  public void getFlashMode(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    String currentFlashMode = camera2View.getFlashMode();
    JSObject result = new JSObject();
    result.put("flashMode", currentFlashMode);
    call.resolve(result);
  }

  @PluginMethod
  public void getDeviceId(PluginCall call) {
    String deviceId = "";
    if (camera2View != null && camera2View.isRunning()) {
      deviceId = camera2View.getCurrentDeviceId();
    }

    JSObject result = new JSObject();
    result.put("deviceId", deviceId != null ? deviceId : "");
    call.resolve(result);
  }

  @PluginMethod
  public void getAvailableLenses(PluginCall call) {
    if (camera2View == null) {
      call.reject("Camera is not initialized");
      return;
    }

    try {
      List<CameraLens> lenses = camera2View.getAvailableLenses();
      Logger.debug(getLogTag(), "Found " + lenses.size() + " camera lenses");

      JSArray lensesArray = new JSArray();

      for (CameraLens lens : lenses) {
        JSObject lensJson = new JSObject();
        lensJson.put("id", lens.getId());
        lensJson.put("label", lens.getLabel());
        lensJson.put("position", lens.getPosition());
        lensJson.put("deviceType", lens.getDeviceType());
        lensJson.put("focalLength", lens.getFocalLength());
        lensJson.put("minZoom", lens.getMinZoom());
        lensJson.put("maxZoom", lens.getMaxZoom());
        lensJson.put("baseZoomRatio", lens.getBaseZoomRatio());
        lensJson.put("isActive", lens.isActive());
        lensesArray.put(lensJson);
      }

      JSObject result = new JSObject();
      result.put("lenses", lensesArray);
      call.resolve(result);
    } catch (Exception e) {
      Logger.error(getLogTag(), "Error getting available lenses", e);
      call.reject("Error getting available lenses: " + e.getMessage());
    }
  }

  @PluginMethod
  public void getCurrentLens(PluginCall call) {
    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    try {
      com.ahm.capacitor.camera.preview.model.CameraLens lens = camera2View.getCurrentLens();

      if (lens == null) {
        call.reject("No current lens available");
        return;
      }

      JSObject lensJson = new JSObject();
      lensJson.put("id", lens.getId());
      lensJson.put("label", lens.getLabel());
      lensJson.put("position", lens.getPosition());
      lensJson.put("deviceType", lens.getDeviceType());
      lensJson.put("focalLength", lens.getFocalLength());
      lensJson.put("minZoom", lens.getMinZoom());
      lensJson.put("maxZoom", lens.getMaxZoom());
      lensJson.put("baseZoomRatio", lens.getBaseZoomRatio());
      lensJson.put("isActive", lens.isActive());

      JSObject result = new JSObject();
      result.put("lens", lensJson);
      call.resolve(result);
    } catch (Exception e) {
      call.reject("Failed to get current lens: " + e.getMessage());
    }
  }

  @PluginMethod
  public void setDeviceId(PluginCall call) {
    String deviceId = call.getString("deviceId");
    if (deviceId == null || deviceId.isEmpty()) {
      call.reject("deviceId parameter is required");
      return;
    }

    if (camera2View == null || !camera2View.isRunning()) {
      call.reject("Camera is not running");
      return;
    }

    try {
      camera2View.switchToDevice(deviceId);
      call.resolve();
    } catch (Exception e) {
      call.reject("Failed to switch camera: " + e.getMessage());
    }
  }

  @PluginMethod
  public void startRecordVideo(final PluginCall call) {
    call.reject("Video recording is not yet supported in Camera2 implementation");
  }

  @PluginMethod
  public void stopRecordVideo(PluginCall call) {
    call.reject("Video recording is not yet supported in Camera2 implementation");
  }

  @PermissionCallback
  private void handleCameraPermissionResult(PluginCall call) {
    boolean disableAudio = call.getBoolean("disableAudio", true); // Default to true (camera only)
    String permissionAlias = disableAudio
      ? CAMERA_ONLY_PERMISSION_ALIAS
      : CAMERA_WITH_AUDIO_PERMISSION_ALIAS;

    if (PermissionState.GRANTED.equals(getPermissionState(permissionAlias))) {
      startCamera(call);
    } else {
      call.reject("Permission failed");
    }
  }

  private void startCamera(final PluginCall call) {
    Logger.debug(getLogTag(), "startCamera called");

    String positionParam = call.getString("position");
    final String deviceId = call.getString("deviceId");

    final String position;
    if (positionParam == null || positionParam.isEmpty() || "rear".equals(positionParam) || "back".equals(positionParam)) {
      position = "rear";
    } else {
      position = "front";
    }

    @NonNull
    final Integer x = Objects.requireNonNull(call.getInt("x", 0));
    @NonNull
    final Integer y = Objects.requireNonNull(call.getInt("y", 0));
    @NonNull
    final Integer width = Objects.requireNonNull(call.getInt("width", 0));
    @NonNull
    final Integer height = Objects.requireNonNull(call.getInt("height", 0));
    @NonNull
    final Integer paddingBottom = Objects.requireNonNull(
      call.getInt("paddingBottom", 0)
    );
    // For rear cameras, default to being behind the webview
    final boolean defaultToBack = "rear".equals(position);
    final Boolean toBack = Objects.requireNonNull(
      call.getBoolean("toBack", defaultToBack)
    );

    Logger.debug(getLogTag(), "Camera config - Position: " + position + " (from: " + positionParam + "), DeviceId: " + deviceId + ", ToBack: " + toBack);
    final Boolean storeToFile = Objects.requireNonNull(
      call.getBoolean("storeToFile", false)
    );
    final Boolean enableOpacity = Objects.requireNonNull(
      call.getBoolean("enableOpacity", false)
    );
    final Boolean enableZoom = Objects.requireNonNull(
      call.getBoolean("enableZoom", false)
    );
    final Boolean disableExifHeaderStripping = Objects.requireNonNull(
      call.getBoolean("disableExifHeaderStripping", false)
    );
    final Boolean lockOrientation = Objects.requireNonNull(
      call.getBoolean("lockAndroidOrientation", false)
    );
    final Boolean disableAudio = call.getBoolean("disableAudio", true); // Default to true (camera only)

    Logger.debug(getLogTag(), "Camera dimensions - x:" + x + ", y:" + y + ", width:" + width + ", height:" + height);

    previousOrientationRequest = getBridge()
      .getActivity()
      .getRequestedOrientation();

    try {
      Logger.debug(getLogTag(), "Creating Camera2View instance");
      camera2View = new Camera2View(getContext(), getBridge().getWebView());
      camera2View.setListener(this);
      Logger.debug(getLogTag(), "Camera2View created successfully");
    } catch (Exception e) {
      Logger.error(getLogTag(), "Error creating Camera2View", e);
      call.reject("Error creating camera: " + e.getMessage());
      return;
    }

    bridge
      .getActivity()
      .runOnUiThread(
        new Runnable() {
          @Override
          public void run() {
            Logger.debug(getLogTag(), "Starting camera configuration on UI thread");

            DisplayMetrics metrics = getBridge()
              .getActivity()
              .getResources()
              .getDisplayMetrics();
            // lock orientation if specified in options:
            if (lockOrientation) {
              Logger.debug(getLogTag(), "Locking screen orientation");
              getBridge()
                .getActivity()
                .setRequestedOrientation(
                  ActivityInfo.SCREEN_ORIENTATION_LOCKED
                );
            }

            // offset
            int computedX = (int) TypedValue.applyDimension(
              TypedValue.COMPLEX_UNIT_DIP,
              x,
              metrics
            );
            int computedY = (int) TypedValue.applyDimension(
              TypedValue.COMPLEX_UNIT_DIP,
              y,
              metrics
            );

            // size
            int computedWidth;
            int computedHeight;
            int computedPaddingBottom;

            if (paddingBottom != 0) {
              computedPaddingBottom = (int) TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                paddingBottom,
                metrics
              );
            } else {
              computedPaddingBottom = 0;
            }

            if (width != 0) {
              computedWidth = (int) TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                width,
                metrics
              );
            } else {
              Display defaultDisplay = getBridge()
                .getActivity()
                .getWindowManager()
                .getDefaultDisplay();
              final Point size = new Point();
              defaultDisplay.getSize(size);

              computedWidth = (int) TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_PX,
                size.x,
                metrics
              );
            }

            if (height != 0) {
              computedHeight =
                (int) TypedValue.applyDimension(
                  TypedValue.COMPLEX_UNIT_DIP,
                  height,
                  metrics
                ) -
                computedPaddingBottom;
            } else {
              Display defaultDisplay = getBridge()
                .getActivity()
                .getWindowManager()
                .getDefaultDisplay();
              final Point size = new Point();
              defaultDisplay.getSize(size);

              computedHeight =
                (int) TypedValue.applyDimension(
                  TypedValue.COMPLEX_UNIT_PX,
                  size.y,
                  metrics
                ) -
                computedPaddingBottom;
            }

            Logger.debug(getLogTag(), "Computed dimensions - x:" + computedX + ", y:" + computedY +
                        ", width:" + computedWidth + ", height:" + computedHeight + ", paddingBottom:" + computedPaddingBottom);

            // Create camera session configuration
            CameraSessionConfiguration config = new CameraSessionConfiguration(
              deviceId,
              position,
              computedX,
              computedY,
              computedWidth,
              computedHeight,
              computedPaddingBottom,
              toBack,
              storeToFile,
              enableOpacity,
              enableZoom,
              disableExifHeaderStripping,
              disableAudio,
              1.0f // default zoom factor
            );

            Logger.debug(getLogTag(), "Created camera session configuration");

            // Save call for callback
            bridge.saveCall(call);
            cameraStartCallbackId = call.getCallbackId();

            try {
              Logger.debug(getLogTag(), "Starting camera session with config");
              // Start camera session
              camera2View.startSession(config);
              Logger.debug(getLogTag(), "Camera session start initiated");
            } catch (Exception e) {
              Logger.error(getLogTag(), "Error starting camera session", e);
              PluginCall savedCall = bridge.getSavedCall(cameraStartCallbackId);
              if (savedCall != null) {
                savedCall.reject("Error starting camera: " + e.getMessage());
                bridge.releaseCall(savedCall);
              }
            }
          }
        }
      );
  }

  @Override
  protected void handleOnResume() {
    super.handleOnResume();
  }

  // Camera2View.Camera2ViewListener implementation
  @Override
  public void onPictureTaken(String result) {
    Logger.debug(getLogTag(), "onPictureTaken callback received");
    JSObject jsObject = new JSObject();
    jsObject.put("value", result);
    bridge.getSavedCall(captureCallbackId).resolve(jsObject);
  }

  @Override
  public void onPictureTakenError(String message) {
    Logger.debug(getLogTag(), "onPictureTakenError: " + message);
    bridge.getSavedCall(captureCallbackId).reject(message);
  }

  @Override
  public void onSampleTaken(String result) {
    Logger.debug(getLogTag(), "onSampleTaken callback received");
    JSObject jsObject = new JSObject();
    jsObject.put("value", result);
    bridge.getSavedCall(snapshotCallbackId).resolve(jsObject);
  }

  @Override
  public void onSampleTakenError(String message) {
    Logger.debug(getLogTag(), "onSampleTakenError: " + message);
    bridge.getSavedCall(snapshotCallbackId).reject(message);
  }

  @Override
  public void onCameraStarted() {
    Logger.debug(getLogTag(), "onCameraStarted callback received - camera successfully started");
    PluginCall pluginCall = bridge.getSavedCall(cameraStartCallbackId);
    if (pluginCall != null) {
      pluginCall.resolve();
      bridge.releaseCall(pluginCall);
    } else {
      Logger.warn(getLogTag(), "onCameraStarted: No saved call found");
    }
  }

  @Override
  public void onCameraStartError(String message) {
    Logger.debug(getLogTag(), "onCameraStartError: " + message);
    PluginCall pluginCall = bridge.getSavedCall(cameraStartCallbackId);
    if (pluginCall != null) {
      pluginCall.reject(message);
      bridge.releaseCall(pluginCall);
    } else {
      Logger.warn(getLogTag(), "onCameraStartError: No saved call found");
    }
  }


}
