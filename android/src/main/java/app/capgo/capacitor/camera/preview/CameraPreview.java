package app.capgo.capacitor.camera.preview;

import static android.Manifest.permission.CAMERA;
import static android.Manifest.permission.RECORD_AUDIO;

import android.Manifest;
import android.content.pm.ActivityInfo;
import android.graphics.Rect;
import android.util.Log;
import androidx.annotation.NonNull;
import app.capgo.capacitor.camera.preview.model.CameraSessionConfiguration;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;
import java.util.List;

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
    private CameraXView cameraXView;
    private CameraSessionConfiguration lastSessionConfig;
    private static final String TAG = "CameraPreview";
    static final String CAMERA_WITH_AUDIO_PERMISSION_ALIAS = "cameraWithAudio";
    static final String CAMERA_ONLY_PERMISSION_ALIAS = "cameraOnly";
    static final String CAMERA_WITH_LOCATION_PERMISSION_ALIAS = "cameraWithLocation";
    static final String MICROPHONE_ONLY_PERMISSION_ALIAS = "microphoneOnly";

    @Override
    public void load() {
        super.load();
        // حل ملاحظة البوت: PERFORMANCE_MODE_FAST مع تقليل العمليات المعقدة للسرعة
        FaceDetectorOptions options = new FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .build();
        faceDetector = FaceDetection.getClient(options);
    }

    // حل ملاحظة البوت (Major): تحويل إحداثيات الوجه لأرقام منظمة بدل نص عشوائي
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
                            Rect bounds = face.getBoundingBox();
                            
                            // إرسال البيانات كأرقام (x, y, width, height) كما طلب البوت
                            faceObj.put("x", bounds.left);
                            faceObj.put("y", bounds.top);
                            faceObj.put("width", bounds.width());
                            faceObj.put("height", bounds.height());
                            
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
    }
}
