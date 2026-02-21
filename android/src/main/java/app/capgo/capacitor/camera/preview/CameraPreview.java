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
import androidx.annotation.NonNull;
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
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;
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

    private FaceDetector faceDetector;
    private final String pluginVersion = "";

    @Override
    public void load() {
        super.load();
        // Initialize Face Detector
        FaceDetectorOptions options = new FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
                .build();
        faceDetector = FaceDetection.getClient(options);
    }

    // This method will be called when a face is detected
    private void processFaceDetection(InputImage image) {
        faceDetector.process(image)
            .addOnSuccessListener(new OnSuccessListener<List<Face>>() {
                @Override
                public void onSuccess(List<Face> faces) {
                    if (faces.size() > 0) {
                        JSObject ret = new JSObject();
                        JSArray facesArray = new JSArray();
                        for (Face face : faces) {
                            JSObject faceObj = new JSObject();
                            faceObj.put("bounds", face.getBoundingBox().flattenToString());
                            facesArray.put(faceObj);
                        }
                        ret.put("faces", facesArray);
                        notifyListeners("onFaceDetected", ret);
                    }
                }
            })
            .addOnFailureListener(new OnFailureListener() {
                @Override
                public void onFailure(@NonNull Exception e) {
                    Log.e(TAG, "Face detection failed", e);
                }
            });
    }

    @Override
    protected void handleOnPause() {
        super.handleOnPause();
        if (cameraXView != null && cameraXView.isRunning()) {
            lastSessionConfig = cameraXView.getSessionConfig();
            cameraXView.stopSession();
        }
    }

    @Override
    protected void handleOnResume() {
        super.handleOnResume();
        if (lastSessionConfig != null) {
            if (lastSessionConfig.isToBack()) {
                try {
                    getBridge().getActivity().getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(android.graphics.Color.BLACK));
                    getBridge().getWebView().setBackgroundColor(android.graphics.Color.BLACK);
                } catch (Exception ignored) {}
            }
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
        if (faceDetector != null) {
            faceDetector.close();
        }
        lastSessionConfig = null;
    }

    private CameraSessionConfiguration lastSessionConfig;
    private static final String TAG = "CameraPreview";
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
    private CameraXView
