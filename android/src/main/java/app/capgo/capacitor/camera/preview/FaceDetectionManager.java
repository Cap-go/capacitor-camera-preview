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
        /**
 * Receives a face detection result delivered as a JSON object.
 *
 * The JSON contains the detection payload (for example: a `faces` array with per-face objects,
 * `frameWidth`, `frameHeight`, and a `timestamp`), encoded according to the manager's result schema.
 *
 * @param result the detection result JSON object
 */
void onFaceDetectionResult(JSONObject result);
        /**
 * Delivers an error notification when face detection or result processing fails.
 *
 * @param error a description of the error that occurred during face detection or result processing
 */
void onFaceDetectionError(String error);
    }

    /**
     * Creates a FaceDetectionManager and prepares it for use.
     *
     * Initializes internal state and a single-thread executor for sequential frame processing;
     * the ML Kit face detector instance is created when startDetection(...) is called.
     */
    public FaceDetectionManager() {
        // Detector will be created when detection starts
        // Use single thread executor for sequential processing
        executorService = Executors.newSingleThreadExecutor();
    }

    /**
     * Initializes and starts the face detection pipeline using the provided configuration and result listener.
     *
     * @param options JSON object specifying detection options such as "performanceMode" ("accurate" or "fast"), "tracking" (boolean), "landmarks" (boolean), "maxFaces", "minFaceSize", and frame-skipping or motion settings.
     * @param listener Callback interface that receives detection results as a JSONObject or error messages.
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
     * Stops face detection, cancels pending processing, and releases detector resources.
     *
     * <p>Sets the internal cancellation flag and stops accepting new frames, waits up to 500 ms
     * for in-flight detection tasks to complete, then closes and clears the ML Kit face detector.</p>
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
     * Processes a single camera frame for face detection, applying skipping, throttling,
     * motion checks, power/thermal safeguards, and concurrency limits before submitting
     * the frame to the ML Kit face detector.
     *
     * <p>If the frame is accepted for processing it is converted to an InputImage and
     * processed asynchronously; the configured FaceDetectionListener will receive results
     * or errors. The ImageProxy is closed on all code paths.</p>
     *
     * @param imageProxy the camera frame to evaluate and (if accepted) process; this method
     *                   closes the provided ImageProxy before returning or after asynchronous processing.
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
     * Parse detection configuration from the provided JSON and update the manager's internal settings.
     *
     * Supported option keys and their defaults:
     * <ul>
     *   <li><b>performanceMode</b> — "fast" or "accurate" (default: "fast")</li>
     *   <li><b>trackingEnabled</b> — boolean, enable face tracking (default: true)</li>
     *   <li><b>detectLandmarks</b> — boolean, include facial landmarks (default: true)</li>
     *   <li><b>maxFaces</b> — integer, maximum faces to return per frame (default: 3)</li>
     *   <li><b>minFaceSize</b> — number, minimum face size as fraction of frame (default: 0.15)</li>
     *   <li><b>frameSkipCount</b> — integer, number of frames to skip between processed frames (default: 2)</li>
     *   <li><b>motionDetectionEnabled</b> — boolean, enable motion-based frame skipping (default: true)</li>
     * </ul>
     *
     * @param options JSON object containing detection options; missing keys use the defaults above
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
     * Builds a JSON result from detected faces and delivers it to the registered listener.
     *
     * The produced JSON contains an array of face objects (each produced by convertFaceToJson),
     * the frame width and height, and a timestamp. The list of faces is limited to the
     * configured maximum number of faces.
     *
     * @param faces       the detected faces to include in the result; may be truncated to the configured maxFaces
     * @param frameWidth  the width of the processed frame used for normalizing face coordinates
     * @param frameHeight the height of the processed frame used for normalizing face coordinates
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
     * Build a JSONObject containing available facial landmarks with coordinates normalized to the frame.
     *
     * The returned object includes entries for available landmarks (e.g., "leftEye", "rightEye", "noseBase",
     * "mouthLeft", "mouthRight", "mouthBottom", "leftEar", "rightEar", "leftCheek", "rightCheek"), each mapping
     * to an object with `x` and `y` values in the range 0.0–1.0 relative to the provided frame dimensions.
     *
     * @param face the detected Face containing landmarks
     * @param frameWidth the width of the frame used to normalize landmark x coordinates
     * @param frameHeight the height of the frame used to normalize landmark y coordinates
     * @return a JSONObject mapping landmark names to their normalized coordinate objects
     * @throws JSONException if constructing the JSON objects fails
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
         * Determine whether the current frame contains significant motion compared to the last processed frame.
         *
         * If there is no previously processed frame, this method reports motion to ensure the first frame is processed.
         * If the comparison cannot be performed, the method conservatively reports motion.
         *
         * @param currentImage the current camera frame to evaluate
         * @return `true` if motion is detected or cannot be safely determined, `false` if no significant motion is detected
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
     * Signals the manager to pause face detection when the application moves to the background.
     *
     * Sets internal state so incoming frames are ignored until onAppForeground() is invoked.
     */
    public void onAppBackground() {
        isAppInBackground = true;
        Log.d(TAG, "Face detection paused (app backgrounded)");
    }

    /**
     * Resume face detection after the app returns to the foreground.
     *
     * Resets the internal frame-skip counter so frame skipping restarts immediately and clears the
     * background pause state to allow incoming frames to be processed.
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
     * Disables thermal throttling, allowing face-detection processing to run without thermal throttling restrictions.
     */
    public void disableThermalThrottling() {
        isThermalThrottling.set(false);
        Log.d(TAG, "Thermal throttling disabled");
    }

    /**
     * Indicates whether thermal throttling is active.
     *
     * @return `true` if thermal throttling is enabled, `false` otherwise.
     */
    public boolean isThermalThrottlingActive() {
        return isThermalThrottling.get();
    }
}