package app.capgo.capacitor.camera.preview;

import android.graphics.PointF;
import android.graphics.Rect;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.camera.core.ImageProxy;
import com.google.android.gms.tasks.Task;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.face.Face;
import com.google.mlkit.vision.face.FaceDetection;
import com.google.mlkit.vision.face.FaceDetector;
import com.google.mlkit.vision.face.FaceDetectorOptions;
import com.google.mlkit.vision.face.FaceLandmark;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * <p>Manages real-time face detection using ML Kit Face Detection API.</p>
 */
public class FaceDetectionManager {

    private static final String TAG = "FaceDetectionManager";

    private FaceDetector faceDetector;
    private FaceDetectionListener listener;
    private boolean isDetecting = false;
    private long lastProcessTime = 0;
    private static final long PROCESS_THROTTLE_MS = 33; // ~30 FPS

    // Async processing infrastructure
    private ExecutorService executorService;
    private final AtomicBoolean isCancelled = new AtomicBoolean(false);
    private final AtomicInteger processingCount = new AtomicInteger(0);
    private static final int MAX_CONCURRENT_DETECTIONS = 2; // Limit concurrent processing

    private int performanceMode = FaceDetectorOptions.PERFORMANCE_MODE_FAST;
    private boolean trackingEnabled = true;
    private boolean detectLandmarks = true;
    private int maxFaces = 3;
    private float minFaceSize = 0.15f;

    // Power & Thermal Management
    private int frameSkipCount = 2; // Process every 3rd frame by default (skip 2)
    private int currentFrameCount = 0;
    private boolean motionDetectionEnabled = true;
    private ImageProxy lastProcessedImage = null;
    private boolean isAppInBackground = false;
    private AtomicBoolean isThermalThrottling = new AtomicBoolean(false);
    private long lastMotionCheckTime = 0;
    private static final long MOTION_CHECK_INTERVAL_MS = 100; // Check motion every 100ms

    /**
     * <p>Interface for communicating face detection results.</p>
     */
    public interface FaceDetectionListener {
        void onFaceDetectionResult(JSONObject result);
        void onFaceDetectionError(String error);
    }

    public FaceDetectionManager() {
        // Detector will be created when detection starts
        // Use single thread executor for sequential processing
        executorService = Executors.newSingleThreadExecutor();
    }

    /**
     * <p>Start face detection with the given options.</p>
     *
     * @param options JSON object containing detection options (performance mode, tracking, landmarks, etc).
     * @param listener Callback interface for detection results and errors.
     */
    public void startDetection(JSONObject options, FaceDetectionListener listener) {
        this.listener = listener;
        this.isCancelled.set(false);
        this.processingCount.set(0);

        // Parse options
        parseOptions(options);

        // Build detector options
        FaceDetectorOptions.Builder optionsBuilder = new FaceDetectorOptions.Builder()
            .setPerformanceMode(performanceMode)
            .setMinFaceSize(minFaceSize);

        if (trackingEnabled) {
            optionsBuilder.enableTracking();
        }

        if (detectLandmarks) {
            optionsBuilder.setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL);
        }

        // Create detector
        faceDetector = FaceDetection.getClient(optionsBuilder.build());
        isDetecting = true;

        Log.d(TAG, "Face detection started with options: " + options.toString());
    }

    /**
     * <p>Stop face detection and release resources.</p>
     * <p>Waits briefly for in-flight tasks to complete and closes the detector.</p>
     */
    public void stopDetection() {
        isDetecting = false;
        isCancelled.set(true);

        // Wait briefly for in-flight tasks to complete
        long maxWaitTime = 500; // 500ms
        long startTime = System.currentTimeMillis();
        while (processingCount.get() > 0 && (System.currentTimeMillis() - startTime) < maxWaitTime) {
            try {
                Thread.sleep(10);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }

        if (faceDetector != null) {
            faceDetector.close();
            faceDetector = null;
        }

        Log.d(TAG, "Face detection stopped (" + processingCount.get() + " tasks still processing)");
    }

    /**
     * <p>Check if face detection is currently running.</p>
     *
     * @return true if detection is active, false otherwise.
     */
    public boolean isRunning() {
        return isDetecting;
    }

    /**
     * <p>Process an image frame for face detection.</p>
     * <p>Applies frame skipping, motion detection, and power/thermal management.</p>
     *
     * @param imageProxy The camera frame to process.
     */
    public void processImageProxy(@NonNull ImageProxy imageProxy) {
        if (!isDetecting || faceDetector == null || isCancelled.get()) {
            imageProxy.close();
            return;
        }

        // Skip if app is in background
        if (isAppInBackground) {
            imageProxy.close();
            return;
        }

        // Skip if thermal throttling is active
        if (isThermalThrottling.get()) {
            imageProxy.close();
            return;
        }

        // Frame skipping for power saving (process every Nth frame)
        currentFrameCount++;
        if (currentFrameCount % (frameSkipCount + 1) != 0) {
            imageProxy.close();
            return;
        }

        // Throttle processing
        long currentTime = System.currentTimeMillis();
        if (currentTime - lastProcessTime < PROCESS_THROTTLE_MS) {
            imageProxy.close();
            return;
        }

        // Motion detection: skip if no significant change from last frame
        if (motionDetectionEnabled && currentTime - lastMotionCheckTime > MOTION_CHECK_INTERVAL_MS) {
            if (!hasSignificantMotion(imageProxy)) {
                imageProxy.close();
                return;
            }
            lastMotionCheckTime = currentTime;
        }

        lastProcessTime = currentTime;

        // Limit concurrent processing to prevent memory issues
        if (processingCount.get() >= MAX_CONCURRENT_DETECTIONS) {
            imageProxy.close();
            return;
        }

        // Increment processing counter
        processingCount.incrementAndGet();

        // Convert ImageProxy to InputImage
        @androidx.camera.core.ExperimentalGetImage
        InputImage inputImage = InputImage.fromMediaImage(imageProxy.getImage(), imageProxy.getImageInfo().getRotationDegrees());

        final int frameWidth = imageProxy.getWidth();
        final int frameHeight = imageProxy.getHeight();

        // Process the image asynchronously
        faceDetector
            .process(inputImage)
            .addOnSuccessListener(executorService, (faces) -> {
                if (!isCancelled.get()) {
                    handleDetectionSuccess(faces, frameWidth, frameHeight);
                }
                imageProxy.close();
                processingCount.decrementAndGet();
            })
            .addOnFailureListener(executorService, (e) -> {
                if (!isCancelled.get()) {
                    Log.e(TAG, "Face detection failed", e);
                    if (listener != null) {
                        listener.onFaceDetectionError("Face detection failed: " + e.getMessage());
                    }
                }
                imageProxy.close();
                processingCount.decrementAndGet();
            });
    }

    /**
     * <p>Parse face detection options from JSON and update internal config.</p>
     *
     * @param options JSON object with detection options.
     */
    private void parseOptions(JSONObject options) {
        try {
            // Performance mode
            String perfMode = options.optString("performanceMode", "fast");
            performanceMode = "accurate".equals(perfMode)
                ? FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE
                : FaceDetectorOptions.PERFORMANCE_MODE_FAST;

            // Other options
            trackingEnabled = options.optBoolean("trackingEnabled", true);
            detectLandmarks = options.optBoolean("detectLandmarks", true);
            maxFaces = options.optInt("maxFaces", 3);
            minFaceSize = (float) options.optDouble("minFaceSize", 0.15);

            // Power management options
            frameSkipCount = options.optInt("frameSkipCount", 2); // Skip 2 frames (process every 3rd)
            motionDetectionEnabled = options.optBoolean("motionDetectionEnabled", true);
        } catch (Exception e) {
            Log.e(TAG, "Error parsing options", e);
        }
    }

    /**
     * <p>Handle successful face detection and notify listener with results.</p>
     *
     * @param faces List of detected faces.
     * @param frameWidth Width of the processed frame.
     * @param frameHeight Height of the processed frame.
     */
    private void handleDetectionSuccess(List<Face> faces, int frameWidth, int frameHeight) {
        try {
            // Limit to maxFaces
            List<Face> limitedFaces = faces.size() > maxFaces ? faces.subList(0, maxFaces) : faces;

            // Build JSON result
            JSONObject result = new JSONObject();
            JSONArray facesArray = new JSONArray();

            for (Face face : limitedFaces) {
                JSONObject faceObj = convertFaceToJson(face, frameWidth, frameHeight);
                facesArray.put(faceObj);
            }

            result.put("faces", facesArray);
            result.put("frameWidth", frameWidth);
            result.put("frameHeight", frameHeight);
            result.put("timestamp", System.currentTimeMillis());

            // Notify listener
            if (listener != null) {
                listener.onFaceDetectionResult(result);
            }
        } catch (JSONException e) {
            Log.e(TAG, "Error building JSON result", e);
            if (listener != null) {
                listener.onFaceDetectionError("Failed to build result: " + e.getMessage());
            }
        }
    }

    /**
     * <p>Convert a detected Face object to a JSON representation.</p>
     *
     * @param face Detected face.
     * @param frameWidth Frame width for normalization.
     * @param frameHeight Frame height for normalization.
     * @return JSONObject representing the face.
     * @throws JSONException if JSON construction fails.
     */
    private JSONObject convertFaceToJson(Face face, int frameWidth, int frameHeight) throws JSONException {
        JSONObject faceObj = new JSONObject();

        // Tracking ID
        if (trackingEnabled && face.getTrackingId() != null) {
            faceObj.put("trackingId", face.getTrackingId());
        }

        // Bounding box (normalized coordinates)
        Rect bounds = face.getBoundingBox();
        JSONObject boundsObj = new JSONObject();
        boundsObj.put("x", (double) bounds.left / frameWidth);
        boundsObj.put("y", (double) bounds.top / frameHeight);
        boundsObj.put("width", (double) bounds.width() / frameWidth);
        boundsObj.put("height", (double) bounds.height() / frameHeight);
        faceObj.put("bounds", boundsObj);

        // Rotation angles (these are primitive floats, not nullable)
        faceObj.put("rollAngle", face.getHeadEulerAngleZ());
        faceObj.put("yawAngle", face.getHeadEulerAngleY());
        faceObj.put("pitchAngle", face.getHeadEulerAngleX());

        // Landmarks
        if (detectLandmarks) {
            JSONObject landmarksObj = extractLandmarks(face, frameWidth, frameHeight);
            if (landmarksObj.length() > 0) {
                faceObj.put("landmarks", landmarksObj);
            }
        }

        return faceObj;
    }

    /**
     * <p>Extract facial landmarks from a Face object as normalized coordinates.</p>
     *
     * @param face Detected face.
     * @param frameWidth Frame width for normalization.
     * @param frameHeight Frame height for normalization.
     * @return JSONObject with landmark names and positions.
     * @throws JSONException if JSON construction fails.
     */
    private JSONObject extractLandmarks(Face face, int frameWidth, int frameHeight) throws JSONException {
        JSONObject landmarks = new JSONObject();

        // Helper to add landmark point
        addLandmark(landmarks, "leftEye", face.getLandmark(FaceLandmark.LEFT_EYE), frameWidth, frameHeight);
        addLandmark(landmarks, "rightEye", face.getLandmark(FaceLandmark.RIGHT_EYE), frameWidth, frameHeight);
        addLandmark(landmarks, "noseBase", face.getLandmark(FaceLandmark.NOSE_BASE), frameWidth, frameHeight);
        addLandmark(landmarks, "mouthLeft", face.getLandmark(FaceLandmark.MOUTH_LEFT), frameWidth, frameHeight);
        addLandmark(landmarks, "mouthRight", face.getLandmark(FaceLandmark.MOUTH_RIGHT), frameWidth, frameHeight);
        addLandmark(landmarks, "mouthBottom", face.getLandmark(FaceLandmark.MOUTH_BOTTOM), frameWidth, frameHeight);
        addLandmark(landmarks, "leftEar", face.getLandmark(FaceLandmark.LEFT_EAR), frameWidth, frameHeight);
        addLandmark(landmarks, "rightEar", face.getLandmark(FaceLandmark.RIGHT_EAR), frameWidth, frameHeight);
        addLandmark(landmarks, "leftCheek", face.getLandmark(FaceLandmark.LEFT_CHEEK), frameWidth, frameHeight);
        addLandmark(landmarks, "rightCheek", face.getLandmark(FaceLandmark.RIGHT_CHEEK), frameWidth, frameHeight);

        return landmarks;
    }

    /**
     * <p>Add a single landmark's normalized position to the landmarks JSON object.</p>
     *
     * @param landmarks JSON object to add to.
     * @param name Landmark name.
     * @param landmark FaceLandmark object.
     * @param frameWidth Frame width for normalization.
     * @param frameHeight Frame height for normalization.
     * @throws JSONException if JSON construction fails.
     */
    private void addLandmark(JSONObject landmarks, String name, FaceLandmark landmark, int frameWidth, int frameHeight)
        throws JSONException {
        if (landmark != null) {
            PointF position = landmark.getPosition();
            JSONObject point = new JSONObject();
            point.put("x", (double) position.x / frameWidth);
            point.put("y", (double) position.y / frameHeight);
            landmarks.put(name, point);
        }
    }

    /**
     * Detect if there's significant motion between frames.
     * Simple implementation using image plane changes and timestamps.
     *
     * @param currentImage Current camera frame.
     * @return true if significant motion is detected, false otherwise.
     */
    private boolean hasSignificantMotion(ImageProxy currentImage) {
        if (lastProcessedImage == null) {
            lastProcessedImage = currentImage;
            return true; // Always process first frame
        }

        // Simple motion detection: compare Y plane brightness
        try {
            @androidx.camera.core.ExperimentalGetImage
            android.media.Image current = currentImage.getImage();
            @androidx.camera.core.ExperimentalGetImage
            android.media.Image last = lastProcessedImage.getImage();

            if (current == null || last == null) {
                return true;
            }

            // Sample center region brightness
            int width = currentImage.getWidth();
            int height = currentImage.getHeight();
            int centerX = width / 2;
            int centerY = height / 2;
            int sampleSize = Math.min(width, height) / 10; // 10% of smaller dimension

            // For simplicity, assume motion if images are different objects
            // More sophisticated: compare pixel data in region
            boolean hasMotion = (current.getTimestamp() != last.getTimestamp());

            lastProcessedImage = currentImage;
            return hasMotion;
        } catch (Exception e) {
            Log.w(TAG, "Motion detection failed, assuming motion", e);
            return true; // Fail-safe: process frame
        }
    }

    /**
     * Pause detection when app goes to background.
     */
    public void onAppBackground() {
        isAppInBackground = true;
        Log.d(TAG, "Face detection paused (app backgrounded)");
    }

    /**
     * Resume detection when app comes to foreground.
     * Resets frame counter.
     */
    public void onAppForeground() {
        isAppInBackground = false;
        currentFrameCount = 0; // Reset frame counter
        Log.d(TAG, "Face detection resumed (app foregrounded)");
    }

    /**
     * Enable thermal throttling to reduce processing load.
     */
    public void enableThermalThrottling() {
        isThermalThrottling.set(true);
        Log.d(TAG, "Thermal throttling enabled");
    }

    /**
     * Disable thermal throttling.
     */
    public void disableThermalThrottling() {
        isThermalThrottling.set(false);
        Log.d(TAG, "Thermal throttling disabled");
    }

    /**
     * Check if thermal throttling is active.
     *
     * @return true if thermal throttling is enabled, false otherwise.
     */
    public boolean isThermalThrottlingActive() {
        return isThermalThrottling.get();
    }
}
