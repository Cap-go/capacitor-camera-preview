package app.capgo.capacitor.camera.preview;

import android.annotation.SuppressLint;
import android.graphics.Rect;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import com.google.android.gms.tasks.Task;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;
import com.google.mlkit.vision.face.FaceLandmark;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * ImageAnalysis.Analyzer implementation for real-time face detection using ML Kit.
 * Processes camera frames and detects faces with landmarks, contours, and classifications.
 */
public class FaceDetectionAnalyzer implements ImageAnalysis.Analyzer {

    private static final String TAG = "FaceDetectionAnalyzer";

    private final FaceDetector detector;
    private final FaceDetectionListener listener;
    private final int detectionInterval;
    private int frameCounter = 0;
    private boolean isProcessing = false;

    /**
     * Listener interface for face detection results.
     */
    public interface FaceDetectionListener {
        /**
         * Called when faces are detected in a frame.
         *
         * @param faces JSON array of detected faces
         * @param frameWidth Width of the frame
         * @param frameHeight Height of the frame
         * @param timestamp Timestamp of detection
         */
        void onFacesDetected(JSONArray faces, int frameWidth, int frameHeight, long timestamp);

        /**
         * Called when face detection fails.
         *
         * @param exception The exception that occurred
         */
        void onFaceDetectionError(Exception exception);
    }

    /**
     * Creates a new FaceDetectionAnalyzer with the specified options.
     *
     * @param options Face detection configuration options
     * @param listener Listener for face detection results
     */
    public FaceDetectionAnalyzer(FaceDetectorOptions options, FaceDetectionListener listener) {
        this.detector = FaceDetection.getClient(options);
        this.listener = listener;

        // Default to processing every frame, but can be configured
        JSONObject optionsJson = optionsToJson(options);
        this.detectionInterval = optionsJson.optInt("detectionInterval", 1);
    }

    /**
     * Analyzes a camera frame for face detection.
     *
     * @param imageProxy The camera frame to analyze
     */
    @Override
    @SuppressLint("UnsafeOptInUsageError")
    public void analyze(@NonNull ImageProxy imageProxy) {
        frameCounter++;

        // Skip frames based on detection interval
        if (frameCounter % detectionInterval != 0) {
            imageProxy.close();
            return;
        }

        // Skip if previous detection is still processing
        if (isProcessing) {
            imageProxy.close();
            return;
        }

        isProcessing = true;

        if (imageProxy.getImage() == null) {
            imageProxy.close();
            isProcessing = false;
            return;
        }

        InputImage image = InputImage.fromMediaImage(imageProxy.getImage(), imageProxy.getImageInfo().getRotationDegrees());

        int frameWidth = imageProxy.getWidth();
        int frameHeight = imageProxy.getHeight();
        long timestamp = System.currentTimeMillis();

        Task<List<Face>> result = detector
            .process(image)
            .addOnSuccessListener((faces) -> {
                try {
                    JSONArray facesArray = new JSONArray();

                    for (Face face : faces) {
                        JSONObject faceJson = faceToJson(face, frameWidth, frameHeight);
                        facesArray.put(faceJson);
                    }

                    if (listener != null) {
                        listener.onFacesDetected(facesArray, frameWidth, frameHeight, timestamp);
                    }
                } catch (JSONException e) {
                    Log.e(TAG, "Error converting faces to JSON", e);
                    if (listener != null) {
                        listener.onFaceDetectionError(e);
                    }
                } finally {
                    imageProxy.close();
                    isProcessing = false;
                }
            })
            .addOnFailureListener((e) -> {
                Log.e(TAG, "Face detection failed", e);
                if (listener != null) {
                    listener.onFaceDetectionError(e);
                }
                imageProxy.close();
                isProcessing = false;
            });
    }

    /**
     * Converts a detected Face to a JSON object with normalized coordinates.
     *
     * @param face The detected face
     * @param frameWidth Width of the frame
     * @param frameHeight Height of the frame
     * @return JSON object representing the face
     * @throws JSONException if JSON creation fails
     */
    private JSONObject faceToJson(Face face, int frameWidth, int frameHeight) throws JSONException {
        JSONObject faceJson = new JSONObject();

        // Tracking ID
        if (face.getTrackingId() != null) {
            faceJson.put("trackingId", face.getTrackingId());
        } else {
            faceJson.put("trackingId", -1);
        }

        // Bounding box (normalized to 0-1)
        Rect bounds = face.getBoundingBox();
        JSONObject boundsJson = new JSONObject();
        boundsJson.put("x", (double) bounds.left / frameWidth);
        boundsJson.put("y", (double) bounds.top / frameHeight);
        boundsJson.put("width", (double) bounds.width() / frameWidth);
        boundsJson.put("height", (double) bounds.height() / frameHeight);
        faceJson.put("bounds", boundsJson);

        // Angles
        JSONObject anglesJson = new JSONObject();
        anglesJson.put("roll", face.getHeadEulerAngleZ()); // Roll
        anglesJson.put("yaw", face.getHeadEulerAngleY()); // Yaw
        anglesJson.put("pitch", face.getHeadEulerAngleX()); // Pitch
        faceJson.put("angles", anglesJson);

        // Landmarks (if available)
        JSONObject landmarksJson = new JSONObject();
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.LEFT_EYE, "leftEye", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.RIGHT_EYE, "rightEye", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.NOSE_BASE, "nose", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.MOUTH_BOTTOM, "mouth", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.LEFT_EAR, "leftEar", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.RIGHT_EAR, "rightEar", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.LEFT_CHEEK, "leftCheek", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.RIGHT_CHEEK, "rightCheek", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.MOUTH_LEFT, "leftMouth", frameWidth, frameHeight);
        addLandmarkIfAvailable(landmarksJson, face, FaceLandmark.MOUTH_RIGHT, "rightMouth", frameWidth, frameHeight);

        if (landmarksJson.length() > 0) {
            faceJson.put("landmarks", landmarksJson);
        }

        // Classification probabilities (if available)
        if (face.getSmilingProbability() != null) {
            faceJson.put("smilingProbability", face.getSmilingProbability());
        }
        if (face.getLeftEyeOpenProbability() != null) {
            faceJson.put("leftEyeOpenProbability", face.getLeftEyeOpenProbability());
        }
        if (face.getRightEyeOpenProbability() != null) {
            faceJson.put("rightEyeOpenProbability", face.getRightEyeOpenProbability());
        }

        return faceJson;
    }

    /**
     * Adds a landmark to the landmarks JSON object if it's available.
     */
    private void addLandmarkIfAvailable(JSONObject landmarksJson, Face face, int landmarkType, String key, int frameWidth, int frameHeight)
        throws JSONException {
        FaceLandmark landmark = face.getLandmark(landmarkType);
        if (landmark != null && landmark.getPosition() != null) {
            JSONObject pointJson = new JSONObject();
            pointJson.put("x", (double) landmark.getPosition().x / frameWidth);
            pointJson.put("y", (double) landmark.getPosition().y / frameHeight);
            landmarksJson.put(key, pointJson);
        }
    }

    /**
     * Converts detector options to JSON (stub for future use).
     */
    private JSONObject optionsToJson(FaceDetectorOptions options) {
        // This is a placeholder - options would come from the plugin configuration
        JSONObject json = new JSONObject();
        try {
            json.put("detectionInterval", 1);
        } catch (JSONException e) {
            Log.e(TAG, "Error creating options JSON", e);
        }
        return json;
    }

    /**
     * Closes the face detector and releases resources.
     */
    public void close() {
        try {
            detector.close();
        } catch (Exception e) {
            Log.e(TAG, "Error closing face detector", e);
        }
    }
}
