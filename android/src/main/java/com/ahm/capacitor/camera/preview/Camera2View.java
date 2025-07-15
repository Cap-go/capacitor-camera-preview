package com.ahm.capacitor.camera.preview;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.CaptureResult;
import android.hardware.camera2.TotalCaptureResult;
import android.hardware.camera2.params.OutputConfiguration;
import android.hardware.camera2.params.SessionConfiguration;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Base64;
import android.util.Log;
import android.util.Range;
import android.util.Size;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.app.Activity;

import androidx.annotation.NonNull;

import com.ahm.capacitor.camera.preview.model.CameraSessionConfiguration;
import com.ahm.capacitor.camera.preview.model.ZoomFactors;
import com.ahm.capacitor.camera.preview.model.CameraLens;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.io.FileOutputStream;
import java.io.File;
import java.util.ArrayList;
import java.util.Set;
import java.util.concurrent.Executors;

public class Camera2View {
    private static final String TAG = "Camera2View";

    public interface Camera2ViewListener {
        void onPictureTaken(String result);
        void onPictureTakenError(String message);
        void onSampleTaken(String result);
        void onSampleTakenError(String message);
        void onCameraStarted();
        void onCameraStartError(String message);
    }

    // Camera components
    private CameraManager cameraManager;
    private CameraDevice cameraDevice;
    private CameraCaptureSession captureSession;
    private ImageReader imageReader;
    private ImageReader sampleImageReader;

    // Surface and preview
    private SurfaceView surfaceView;
    private Surface previewSurface;

    // Camera state
    private String currentCameraId;
    private String currentLogicalCameraId;
    private boolean isCurrentCameraPhysical = false;
    private CameraCharacteristics cameraCharacteristics;
    private CaptureRequest.Builder previewRequestBuilder;
    private CaptureRequest previewRequest;
    private List<CameraLens> sortedLenses;
    private CaptureRequest.Key<Integer> currentControlFlashMode = CaptureRequest.CONTROL_AE_MODE;
    private int currentFlashMode = CameraMetadata.CONTROL_AE_MODE_ON;
    private float currentZoomRatio = 1.0f;

    // Threading
    private HandlerThread backgroundThread;
    private Handler backgroundHandler;
    private final Semaphore cameraOpenCloseLock = new Semaphore(1);

    // Configuration
    private CameraSessionConfiguration sessionConfig;
    private Camera2ViewListener listener;
    private Context context;
    private WebView webView;

    // State tracking
    private boolean isRunning = false;

    public Camera2View(Context context, WebView webView) {
        this.context = context;
        this.webView = webView;
        this.cameraManager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
    }

    public void setListener(Camera2ViewListener listener) {
        this.listener = listener;
    }

    public boolean isRunning() {
        return isRunning;
    }

    public void startSession(CameraSessionConfiguration config) {
        Log.d(TAG, "startSession: Starting camera session with config");
        Log.d(TAG, "startSession: DeviceId=" + config.getDeviceId() +
                   ", Position=" + config.getPosition() +
                   ", Dimensions=" + config.getWidth() + "x" + config.getHeight());

        this.sessionConfig = config;

        try {
            Log.d(TAG, "startSession: Starting background thread");
            startBackgroundThread();

            Log.d(TAG, "startSession: Opening camera (surface view will be set up after camera is ready)");
            openCamera();
        } catch (Exception e) {
            Log.e(TAG, "startSession: Error during initialization", e);
            if (listener != null) {
                listener.onCameraStartError("Camera initialization failed: " + e.getMessage());
            }
        }
    }

    public void stopSession() {
        Log.d(TAG, "stopSession: Stopping camera session");
        isRunning = false;
        closeCamera();
        stopBackgroundThread();
        removeSurfaceView();
        Log.d(TAG, "stopSession: Camera session stopped");
    }

    private void startBackgroundThread() {
        backgroundThread = new HandlerThread("CameraBackground");
        backgroundThread.start();
        backgroundHandler = new Handler(backgroundThread.getLooper());
    }

    private void stopBackgroundThread() {
        if (backgroundThread != null) {
            backgroundThread.quitSafely();
            try {
                backgroundThread.join();
                backgroundThread = null;
                backgroundHandler = null;
            } catch (InterruptedException e) {
                Log.e(TAG, "Error stopping background thread", e);
            }
        }
    }

    private void setupSurfaceView() {
        Log.d(TAG, "setupSurfaceView: Setting up surface view");

        // Remove existing surface view if any
        if (surfaceView != null) {
            Log.d(TAG, "setupSurfaceView: Removing existing surface view");
            removeSurfaceView();
        }

        // Make WebView transparent if needed
        if (sessionConfig.isToBack()) {
            webView.setBackgroundColor(android.graphics.Color.TRANSPARENT);
        }

        surfaceView = new SurfaceView(context);

        // Calculate proper aspect ratio for preview
        Size previewSize = getOptimalPreviewSize();
        if (previewSize != null) {
            Log.d(TAG, "setupSurfaceView: Using optimal preview size: " + previewSize.getWidth() + "x" + previewSize.getHeight());

            // Calculate aspect ratio
            float aspectRatio = (float) previewSize.getWidth() / previewSize.getHeight();

            int targetWidth = sessionConfig.getWidth();
            int targetHeight = sessionConfig.getHeight() - sessionConfig.getPaddingBottom();

            // Adjust dimensions to maintain aspect ratio
            if (targetWidth / aspectRatio <= targetHeight) {
                targetHeight = (int) (targetWidth / aspectRatio);
            } else {
                targetWidth = (int) (targetHeight * aspectRatio);
            }

            Log.d(TAG, "setupSurfaceView: Adjusted surface size: " + targetWidth + "x" + targetHeight +
                      " (aspect ratio: " + aspectRatio + ")");

            ViewGroup.LayoutParams layoutParams = new ViewGroup.LayoutParams(targetWidth, targetHeight);
            surfaceView.setLayoutParams(layoutParams);
        } else {
            // Fallback to original dimensions
            ViewGroup.LayoutParams layoutParams = new ViewGroup.LayoutParams(
                sessionConfig.getWidth(),
                sessionConfig.getHeight() - sessionConfig.getPaddingBottom()
            );
            surfaceView.setLayoutParams(layoutParams);
        }

        ViewGroup parent = (ViewGroup) webView.getParent();
        if (parent != null) {
            if (sessionConfig.isToBack()) {
                parent.addView(surfaceView, 0);
                parent.bringChildToFront(webView);
            } else {
                parent.addView(surfaceView);
            }
        }

        surfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(@NonNull SurfaceHolder holder) {
                Log.d(TAG, "surfaceCreated: Preview surface created");
                previewSurface = holder.getSurface();
                Log.d(TAG, "surfaceCreated: CameraDevice available: " + (cameraDevice != null));
                Log.d(TAG, "surfaceCreated: CaptureSession available: " + (captureSession != null));

                // Only create session if we have camera device but no active session
                if (cameraDevice != null && captureSession == null) {
                    Log.d(TAG, "surfaceCreated: Creating camera preview session");
                    createCameraPreviewSession();
                } else if (cameraDevice != null && captureSession != null) {
                    Log.d(TAG, "surfaceCreated: Camera session already exists, skipping creation");
                } else {
                    Log.w(TAG, "surfaceCreated: Camera device not ready, waiting for camera opening");
                }
            }

            @Override
            public void surfaceChanged(@NonNull SurfaceHolder holder, int format, int width, int height) {
                Log.d(TAG, "surfaceChanged: Surface format=" + format + ", size=" + width + "x" + height);
                // Handle surface changes if needed
            }

            @Override
            public void surfaceDestroyed(@NonNull SurfaceHolder holder) {
                Log.d(TAG, "surfaceDestroyed: Preview surface destroyed");
                previewSurface = null;

                // Close any existing session when surface is destroyed
                if (captureSession != null) {
                    Log.d(TAG, "surfaceDestroyed: Closing capture session");
                    captureSession.close();
                    captureSession = null;
                }
            }
        });
    }

    private void removeSurfaceView() {
        Log.d(TAG, "removeSurfaceView: Removing surface view and cleaning up");

        // Clear surface reference first to prevent any usage during cleanup
        previewSurface = null;

        if (surfaceView != null) {
            ViewGroup parent = (ViewGroup) surfaceView.getParent();
            if (parent != null) {
                parent.removeView(surfaceView);
            }
            surfaceView = null;
            Log.d(TAG, "removeSurfaceView: Surface view removed from parent");
        }

        // Reset WebView background
        webView.setBackgroundColor(android.graphics.Color.WHITE);
        Log.d(TAG, "removeSurfaceView: Cleanup complete");
    }

    @SuppressLint("MissingPermission")
    private void openCamera() {
        Log.d(TAG, "openCamera: Attempting to open camera");
        try {
            Log.d(TAG, "openCamera: Trying to acquire camera lock");
            if (!cameraOpenCloseLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) {
                Log.e(TAG, "openCamera: Timeout waiting to lock camera opening");
                if (listener != null) {
                    listener.onCameraStartError("Time out waiting to lock camera opening.");
                }
                return;
            }
            Log.d(TAG, "openCamera: Camera lock acquired");

            // Determine which camera to use
            String cameraIdToOpen;
            if (currentLogicalCameraId != null) {
                // We're switching cameras and already have the logical camera ID set
                cameraIdToOpen = currentLogicalCameraId;
                Log.d(TAG, "openCamera: Using stored logical camera ID: " + cameraIdToOpen +
                           " (for " + (isCurrentCameraPhysical ? "physical" : "logical") + " camera " + currentCameraId + ")");
            } else if (sessionConfig.getDeviceId() != null && !sessionConfig.getDeviceId().isEmpty()) {
                // Initial camera setup from session config - need to check if it's physical or logical
                String requestedDeviceId = sessionConfig.getDeviceId();
                Log.d(TAG, "openCamera: Checking if device ID " + requestedDeviceId + " is logical or physical");

                // Check if it's a logical camera first
                String[] logicalCameraIds;
                try {
                    logicalCameraIds = cameraManager.getCameraIdList();
                } catch (CameraAccessException e) {
                    Log.e(TAG, "openCamera: Error getting camera list: " + e.getMessage());
                    if (listener != null) {
                        listener.onCameraStartError("Error getting camera list: " + e.getMessage());
                    }
                    cameraOpenCloseLock.release();
                    return;
                }

                boolean isLogical = false;
                for (String logicalId : logicalCameraIds) {
                    if (logicalId.equals(requestedDeviceId)) {
                        isLogical = true;
                        break;
                    }
                }

                if (isLogical) {
                    // It's a logical camera
                    currentCameraId = requestedDeviceId;
                    currentLogicalCameraId = requestedDeviceId;
                    isCurrentCameraPhysical = false;
                    cameraIdToOpen = requestedDeviceId;
                    Log.d(TAG, "openCamera: Device " + requestedDeviceId + " is a logical camera");
                } else {
                    // Check if it's a physical camera
                    String parentLogicalId = null;
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                        for (String logicalId : logicalCameraIds) {
                            try {
                                CameraCharacteristics chars = cameraManager.getCameraCharacteristics(logicalId);
                                java.util.Set<String> physicalIds = chars.getPhysicalCameraIds();
                                if (physicalIds.contains(requestedDeviceId)) {
                                    parentLogicalId = logicalId;
                                    Log.d(TAG, "openCamera: Device " + requestedDeviceId + " is a physical camera under logical camera " + logicalId);
                                    break;
                                }
                            } catch (Exception e) {
                                Log.w(TAG, "openCamera: Error checking physical cameras for " + logicalId + ": " + e.getMessage());
                            }
                        }
                    }

                    if (parentLogicalId != null) {
                        // It's a physical camera
                        currentCameraId = requestedDeviceId;
                        currentLogicalCameraId = parentLogicalId;
                        isCurrentCameraPhysical = true;
                        cameraIdToOpen = parentLogicalId;
                        Log.d(TAG, "openCamera: Will open logical camera " + parentLogicalId + " to access physical camera " + requestedDeviceId);
                    } else {
                        // Not found as logical or physical - treat as logical and let it fail gracefully
                        Log.w(TAG, "openCamera: Device " + requestedDeviceId + " not found as logical or physical camera, treating as logical");
                        currentCameraId = requestedDeviceId;
                        currentLogicalCameraId = requestedDeviceId;
                        isCurrentCameraPhysical = false;
                        cameraIdToOpen = requestedDeviceId;
                    }
                }
            } else {
                // Find camera by position
                Log.d(TAG, "openCamera: Looking for camera by position: " + sessionConfig.getPosition());
                currentCameraId = getCameraIdByPosition(sessionConfig.getPosition());
                currentLogicalCameraId = currentCameraId;
                isCurrentCameraPhysical = false;
                cameraIdToOpen = currentCameraId;
                Log.d(TAG, "openCamera: Found camera ID for position: " + currentCameraId);
            }

            if (cameraIdToOpen == null) {
                Log.e(TAG, "openCamera: No camera found for position: " + sessionConfig.getPosition());
                if (listener != null) {
                    listener.onCameraStartError("No camera found for position: " + sessionConfig.getPosition());
                }
                cameraOpenCloseLock.release();
                return;
            }

            Log.d(TAG, "openCamera: Getting camera characteristics for: " + cameraIdToOpen);
            cameraCharacteristics = cameraManager.getCameraCharacteristics(cameraIdToOpen);

            // Setup physical lenses for seamless zoom
            setupLenses();

            StreamConfigurationMap streamMap = cameraCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            if (streamMap == null) {
                Log.e(TAG, "openCamera: No stream configuration map available");
                if (listener != null) {
                    listener.onCameraStartError("Camera configuration not available");
                }
                cameraOpenCloseLock.release();
                return;
            }

            Size[] jpegSizes = streamMap.getOutputSizes(ImageFormat.JPEG);
            Log.d(TAG, "openCamera: Available JPEG sizes: " + (jpegSizes != null ? jpegSizes.length : 0));

            int width = 640;
            int height = 480;
            if (jpegSizes != null && jpegSizes.length > 0) {
                width = jpegSizes[0].getWidth();
                height = jpegSizes[0].getHeight();
                Log.d(TAG, "openCamera: Using JPEG size: " + width + "x" + height);
            } else {
                Log.w(TAG, "openCamera: No JPEG sizes available, using defaults: " + width + "x" + height);
            }

            Log.d(TAG, "openCamera: Creating image readers");
            imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 1);
            imageReader.setOnImageAvailableListener(onImageAvailableListener, backgroundHandler);

            // Setup sample image reader for lower quality captures
            sampleImageReader = ImageReader.newInstance(width / 2, height / 2, ImageFormat.JPEG, 1);
            sampleImageReader.setOnImageAvailableListener(onSampleImageAvailableListener, backgroundHandler);

            Log.d(TAG, "openCamera: Opening camera device: " + cameraIdToOpen);
            cameraManager.openCamera(cameraIdToOpen, deviceStateCallback, backgroundHandler);

        } catch (CameraAccessException e) {
            Log.e(TAG, "Error opening camera", e);
            if (listener != null) {
                listener.onCameraStartError("Error opening camera: " + e.getMessage());
            }
        } catch (InterruptedException e) {
            if (listener != null) {
                listener.onCameraStartError("Interrupted while trying to lock camera opening.");
            }
        }
    }

    private void setupLenses() {
        sortedLenses = new ArrayList<>();
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.P) {
            return;
        }

        try {
            Set<String> physicalCameraIds = cameraCharacteristics.getPhysicalCameraIds();
            if (physicalCameraIds.isEmpty()) {
                // Not a logical camera, just add itself as a single lens
                float[] focalLengths = cameraCharacteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);
                Float maxZoom = cameraCharacteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
                String deviceType = detectDeviceType(cameraCharacteristics, currentLogicalCameraId);
                String label = createLabel(currentLogicalCameraId, sessionConfig.getPosition(), deviceType);
                String position = sessionConfig.getPosition();

                if (focalLengths != null && focalLengths.length > 0 && maxZoom != null) {
                    CameraLens lens = new CameraLens(currentLogicalCameraId, label, position, deviceType, focalLengths[0], 1.0f, maxZoom, 1.0f, true);
                    sortedLenses.add(lens);
                }
                return;
            }

            float minFocalLength = Float.MAX_VALUE;
            for (String id : physicalCameraIds) {
                CameraCharacteristics chars = cameraManager.getCameraCharacteristics(id);
                float[] focalLengths = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);
                if (focalLengths != null && focalLengths.length > 0) {
                    minFocalLength = Math.min(minFocalLength, focalLengths[0]);
                }
            }

            for (String id : physicalCameraIds) {
                CameraCharacteristics chars = cameraManager.getCameraCharacteristics(id);
                float[] focalLengths = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);

                Log.d(TAG, "setupLenses: Camera id: " + id);
                Log.d(TAG, "setupLenses: Focal lengths: " + Arrays.toString(focalLengths));
                Log.d(TAG, "setupLenses: facing: " + chars.get(CameraCharacteristics.LENS_FACING));
                Float maxZoom = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
                String deviceType = detectDeviceType(cameraCharacteristics, currentLogicalCameraId);
                String label = createLabel(currentLogicalCameraId, sessionConfig.getPosition(), deviceType);
                String position = sessionConfig.getPosition();
                Log.d(TAG, "setupLenses: Max zoom: " + maxZoom);

                if (focalLengths != null && focalLengths.length > 0 && maxZoom != null) {
                    CameraLens lens = new CameraLens(id, label, position, deviceType, focalLengths[0], 1.0f, maxZoom, focalLengths[0] / minFocalLength, true);
                    sortedLenses.add(lens);
                }
            }

            Collections.sort(sortedLenses, Comparator.comparingDouble(l -> l.getFocalLength()));

            Log.d(TAG, "setupLenses: Found " + sortedLenses.size() + " lenses.");
            for (CameraLens lens : sortedLenses) {
                Log.d(TAG, "Lens: id=" + lens.getId() + ", focalLength=" + lens.getFocalLength() + ", baseZoom=" + lens.getBaseZoomRatio() + ", maxZoom=" + lens.getMaxZoom());
            }

        } catch (CameraAccessException e) {
            Log.e(TAG, "setupLenses: Error accessing camera characteristics for physical devices.", e);
        }
    }

    private String getCameraIdByPosition(String position) {
        Log.d(TAG, "getCameraIdByPosition: Looking for position: " + position);
        try {
            String[] cameraIdList = cameraManager.getCameraIdList();
            Log.d(TAG, "getCameraIdByPosition: Found " + cameraIdList.length + " cameras");
            Log.d(TAG, "getCameraIdByPosition: Camera IDs: " + Arrays.toString(cameraIdList));

            for (String cameraId : cameraIdList) {
                CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraId);
                Integer facing = characteristics.get(CameraCharacteristics.LENS_FACING);

                Log.d(TAG, "getCameraIdByPosition: Camera " + cameraId + " facing: " + facing);

                if (facing != null) {
                    if ("front".equals(position) && facing == CameraCharacteristics.LENS_FACING_FRONT) {
                        Log.d(TAG, "getCameraIdByPosition: Found front camera: " + cameraId);
                        return cameraId;
                    } else if (("rear".equals(position) || "back".equals(position)) && facing == CameraCharacteristics.LENS_FACING_BACK) {
                        Log.d(TAG, "getCameraIdByPosition: Found rear camera: " + cameraId);
                        return cameraId;
                    }
                }
            }
            Log.w(TAG, "getCameraIdByPosition: No camera found for position: " + position);
        } catch (CameraAccessException e) {
            Log.e(TAG, "getCameraIdByPosition: Error getting camera ID by position", e);
        }
        return null;
    }

    private final CameraDevice.StateCallback deviceStateCallback = new CameraDevice.StateCallback() {
        @Override
        public void onOpened(@NonNull CameraDevice camera) {
            Log.d(TAG, "deviceStateCallback.onOpened: Camera device opened successfully");
            Log.d(TAG, "deviceStateCallback.onOpened: Requested camera ID: " + currentCameraId +
                      " (logical: " + currentLogicalCameraId + ", isPhysical: " + isCurrentCameraPhysical + ")");
            Log.d(TAG, "deviceStateCallback.onOpened: Opened camera device ID: " + camera.getId());
            cameraOpenCloseLock.release();
            cameraDevice = camera;

                        // Now that we have camera characteristics, set up surface view with proper dimensions on UI thread
            Log.d(TAG, "deviceStateCallback.onOpened: Setting up surface view with camera characteristics");
            if (context instanceof Activity) {
                Activity activity = (Activity) context;
                activity.runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        setupSurfaceView();
                    }
                });
            } else {
                setupSurfaceView(); // Fallback for non-Activity contexts
            }

            Log.d(TAG, "deviceStateCallback.onOpened: PreviewSurface available: " + (previewSurface != null));
            Log.d(TAG, "deviceStateCallback.onOpened: CaptureSession available: " + (captureSession != null));

            // Don't create session here - let surfaceCreated callback handle it
            // This prevents the race condition where setupSurfaceView destroys the old surface
            // but the new surface isn't ready yet
            Log.d(TAG, "deviceStateCallback.onOpened: Waiting for surface creation to complete before creating session");
        }

        @Override
        public void onDisconnected(@NonNull CameraDevice camera) {
            Log.w(TAG, "deviceStateCallback.onDisconnected: Camera device disconnected");
            cameraOpenCloseLock.release();
            camera.close();
            cameraDevice = null;
        }

        @Override
        public void onError(@NonNull CameraDevice camera, int error) {
            Log.e(TAG, "deviceStateCallback.onError: Camera device error: " + error);
            cameraOpenCloseLock.release();
            camera.close();
            cameraDevice = null;
            if (listener != null) {
                listener.onCameraStartError("Camera device error: " + error);
            }
        }
    };

    private void createCameraPreviewSession() {
        Log.d(TAG, "createCameraPreviewSession: Starting camera preview session creation");
        try {
            if (cameraDevice == null) {
                Log.e(TAG, "createCameraPreviewSession: Cannot create session - camera device is null");
                return;
            }

            if (previewSurface == null) {
                Log.e(TAG, "createCameraPreviewSession: Cannot create session - preview surface is null");
                return;
            }

            if (!previewSurface.isValid()) {
                Log.e(TAG, "createCameraPreviewSession: Cannot create session - preview surface is not valid");
                return;
            }

            Log.d(TAG, "createCameraPreviewSession: All prerequisites met - camera device and valid surface available");

            previewRequestBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            previewRequestBuilder.addTarget(previewSurface);

            Log.d(TAG, "createCameraPreviewSession: Creating capture session...");

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                OutputConfiguration previewOutputConfig = new OutputConfiguration(previewSurface);
                List<OutputConfiguration> outputs = new ArrayList<>();
                outputs.add(previewOutputConfig);

                // If we're using a physical lens on a logical camera, specify it.
                if (isCurrentCameraPhysical) {
                    previewOutputConfig.setPhysicalCameraId(currentCameraId);
                    Log.d(TAG, "createCameraPreviewSession: Targeting physical camera " + currentCameraId);
                }

                SessionConfiguration sessionConfig = new SessionConfiguration(
                    SessionConfiguration.SESSION_REGULAR,
                    outputs,
                    backgroundHandler::post, // Use background handler for callbacks
                    new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(@NonNull CameraCaptureSession session) {
                           handleSessionConfigured(session);
                        }

                        @Override
                        public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                            handleSessionConfigureFailed(session);
                        }
                    }
                );
                cameraDevice.createCaptureSession(sessionConfig);

            } else {
                 // Fallback for older APIs that don't support physical cameras
                cameraDevice.createCaptureSession(
                    Arrays.asList(previewSurface),
                    new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(@NonNull CameraCaptureSession session) {
                            handleSessionConfigured(session);
                        }

                        @Override
                        public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                           handleSessionConfigureFailed(session);
                        }
                    },
                    null
                );
            }

        } catch (CameraAccessException e) {
            Log.e(TAG, "createCameraPreviewSession: Error creating session", e);
            if (listener != null) {
                listener.onCameraStartError("Error creating preview session: " + e.getMessage());
            }
        } catch (Exception e) {
            Log.e(TAG, "createCameraPreviewSession: Unexpected error", e);
            if (listener != null) {
                listener.onCameraStartError("Unexpected error creating preview session: " + e.getMessage());
            }
        }
    }

    private void handleSessionConfigured(CameraCaptureSession session) {
        Log.d(TAG, "handleSessionConfigured: Camera session configured successfully");
        if (cameraDevice == null) {
            Log.e(TAG, "handleSessionConfigured: Camera device became null");
            return;
        }

        captureSession = session;
        try {
            Log.d(TAG, "handleSessionConfigured: Setting up preview request");
            previewRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            // Set flash
            previewRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE, currentFlashMode);

            // Set current zoom ratio when session is configured
            if (currentZoomRatio != 1.0f) {
                Log.d(TAG, "handleSessionConfigured: Setting current zoom: " + currentZoomRatio);
                setZoomInternal(currentZoomRatio);
            } else if (sessionConfig.getZoomFactor() != 1.0f) {
                Log.d(TAG, "handleSessionConfigured: Setting initial session config zoom: " + sessionConfig.getZoomFactor());
                setZoomInternal(sessionConfig.getZoomFactor());
            }

            previewRequest = previewRequestBuilder.build();
            Log.d(TAG, "handleSessionConfigured: Starting repeating capture request");
            captureSession.setRepeatingRequest(previewRequest, captureCallback, backgroundHandler);

            isRunning = true;
            Log.d(TAG, "handleSessionConfigured: Camera preview started successfully");
            if (listener != null) {
                listener.onCameraStarted();
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "handleSessionConfigured: Error starting preview", e);
            if (listener != null) {
                listener.onCameraStartError("Error starting preview: " + e.getMessage());
            }
        }
    }

    private void handleSessionConfigureFailed(CameraCaptureSession session) {
        Log.e(TAG, "handleSessionConfigureFailed: Camera session configuration failed");
        if (listener != null) {
            listener.onCameraStartError("Camera configuration failed");
        }
    }

    private final CameraCaptureSession.CaptureCallback captureCallback = new CameraCaptureSession.CaptureCallback() {
        @Override
        public void onCaptureCompleted(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, @NonNull TotalCaptureResult result) {
            // Handle capture completion if needed
        }
    };

    public void closeCamera() {
        try {
            cameraOpenCloseLock.acquire();
            if (captureSession != null) {
                captureSession.close();
                captureSession = null;
            }
            if (cameraDevice != null) {
                cameraDevice.close();
                cameraDevice = null;
            }
            if (imageReader != null) {
                imageReader.close();
                imageReader = null;
            }
            if (sampleImageReader != null) {
                sampleImageReader.close();
                sampleImageReader = null;
            }
        } catch (InterruptedException e) {
            Log.e(TAG, "Interrupted while trying to lock camera closing.", e);
        } finally {
            cameraOpenCloseLock.release();
        }
    }

    public void capturePhoto(int quality) {
        if (cameraDevice == null || captureSession == null) {
            if (listener != null) {
                listener.onPictureTakenError("Camera not ready");
            }
            return;
        }

        try {
            Log.d(TAG, "capturePhoto: Creating capture session with image reader");
            // Create a new session with both preview and image reader surfaces for capture
            cameraDevice.createCaptureSession(
                Arrays.asList(previewSurface, imageReader.getSurface()),
                new CameraCaptureSession.StateCallback() {
                    @Override
                    public void onConfigured(@NonNull CameraCaptureSession session) {
                        try {
                            Log.d(TAG, "capturePhoto: Capture session configured, taking photo");
                            CaptureRequest.Builder captureBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
                            captureBuilder.addTarget(imageReader.getSurface());

                            // Set auto-focus
                            captureBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);

                            // Set AE pre-capture trigger
                            captureBuilder.set(CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER,
                                CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER_START);
                            // Set flash
                            captureBuilder.set(CaptureRequest.CONTROL_AE_MODE, currentFlashMode);

                            // Set zoom
                            if (previewRequestBuilder.get(CaptureRequest.SCALER_CROP_REGION) != null) {
                                captureBuilder.set(CaptureRequest.SCALER_CROP_REGION, previewRequestBuilder.get(CaptureRequest.SCALER_CROP_REGION));
                            }

                            // capture photo
                            session.capture(captureBuilder.build(), new CameraCaptureSession.CaptureCallback() {
                                @Override
                                public void onCaptureCompleted(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, @NonNull TotalCaptureResult result) {
                                    Log.d(TAG, "capturePhoto: Photo capture completed, restoring preview session");
                                    // Restore preview-only session
                                    createCameraPreviewSession();
                                }
                            }, backgroundHandler);
                        } catch (CameraAccessException e) {
                            Log.e(TAG, "capturePhoto: Error during capture", e);
                            if (listener != null) {
                                listener.onPictureTakenError("Error capturing photo: " + e.getMessage());
                            }
                        }
                    }

                    @Override
                    public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                        Log.e(TAG, "capturePhoto: Failed to configure capture session");
                        if (listener != null) {
                            listener.onPictureTakenError("Failed to configure capture session");
                        }
                    }
                },
                backgroundHandler
            );
        } catch (CameraAccessException e) {
            Log.e(TAG, "capturePhoto: Error creating capture session", e);
            if (listener != null) {
                listener.onPictureTakenError("Error creating capture session: " + e.getMessage());
            }
        }
    }

    public void captureSample(int quality) {
        if (cameraDevice == null || captureSession == null) {
            if (listener != null) {
                listener.onSampleTakenError("Camera not ready");
            }
            return;
        }

        try {
            Log.d(TAG, "captureSample: Creating capture session with sample image reader");
            // Create a new session with both preview and sample image reader surfaces for capture
            cameraDevice.createCaptureSession(
                Arrays.asList(previewSurface, sampleImageReader.getSurface()),
                new CameraCaptureSession.StateCallback() {
                    @Override
                    public void onConfigured(@NonNull CameraCaptureSession session) {
                        try {
                            Log.d(TAG, "captureSample: Capture session configured, taking sample");
                            CaptureRequest.Builder captureBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
                            captureBuilder.addTarget(sampleImageReader.getSurface());

                            // Set auto-focus
                            captureBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);

                             // Set AE pre-capture trigger
                            captureBuilder.set(CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER,
                                CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER_START);

                            // Set flash
                            captureBuilder.set(CaptureRequest.CONTROL_AE_MODE, currentFlashMode);

                            // Set zoom if available
                            if (previewRequestBuilder.get(CaptureRequest.SCALER_CROP_REGION) != null) {
                                captureBuilder.set(CaptureRequest.SCALER_CROP_REGION, previewRequestBuilder.get(CaptureRequest.SCALER_CROP_REGION));
                            }

                            // capture photo
                            session.capture(captureBuilder.build(), new CameraCaptureSession.CaptureCallback() {
                                @Override
                                public void onCaptureCompleted(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, @NonNull TotalCaptureResult result) {
                                    Log.d(TAG, "captureSample: Sample capture completed, restoring preview session");
                                    // Restore preview-only session
                                    createCameraPreviewSession();
                                }
                            }, backgroundHandler);
                        } catch (CameraAccessException e) {
                            Log.e(TAG, "captureSample: Error during capture", e);
                            if (listener != null) {
                                listener.onSampleTakenError("Error capturing sample: " + e.getMessage());
                            }
                        }
                    }

                    @Override
                    public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                        Log.e(TAG, "captureSample: Failed to configure capture session");
                        if (listener != null) {
                            listener.onSampleTakenError("Failed to configure capture session");
                        }
                    }
                },
                backgroundHandler
            );
        } catch (CameraAccessException e) {
            Log.e(TAG, "captureSample: Error creating capture session", e);
            if (listener != null) {
                listener.onSampleTakenError("Error creating capture session: " + e.getMessage());
            }
        }
    }

    private final ImageReader.OnImageAvailableListener onImageAvailableListener = new ImageReader.OnImageAvailableListener() {
        @Override
        public void onImageAvailable(ImageReader reader) {
            Image image = null;
            try {
                image = reader.acquireLatestImage();
                if (image != null) {
                    ByteBuffer buffer = image.getPlanes()[0].getBuffer();
                    byte[] bytes = new byte[buffer.remaining()];
                    buffer.get(bytes);

                    // Apply rotation correction
                    bytes = correctImageRotation(bytes);

                    String base64 = Base64.encodeToString(bytes, Base64.NO_WRAP);
                    if (listener != null) {
                        listener.onPictureTaken(base64);
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "Error processing captured image", e);
                if (listener != null) {
                    listener.onPictureTakenError("Error processing image: " + e.getMessage());
                }
            } finally {
                if (image != null) {
                    image.close();
                }
            }
        }
    };

    private final ImageReader.OnImageAvailableListener onSampleImageAvailableListener = new ImageReader.OnImageAvailableListener() {
        @Override
        public void onImageAvailable(ImageReader reader) {
            Image image = null;
            try {
                image = reader.acquireLatestImage();
                if (image != null) {
                    ByteBuffer buffer = image.getPlanes()[0].getBuffer();
                    byte[] bytes = new byte[buffer.remaining()];
                    buffer.get(bytes);

                    // Apply rotation correction
                    bytes = correctImageRotation(bytes);

                    String base64 = Base64.encodeToString(bytes, Base64.NO_WRAP);
                    if (listener != null) {
                        listener.onSampleTaken(base64);
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "Error processing sample image", e);
                if (listener != null) {
                    listener.onSampleTakenError("Error processing sample: " + e.getMessage());
                }
            } finally {
                if (image != null) {
                    image.close();
                }
            }
        }
    };

    public List<com.ahm.capacitor.camera.preview.model.CameraDevice> getAvailableDevices() {
        Log.d(TAG, "getAvailableDevices: Starting camera enumeration");
        try {
            if (cameraManager == null) {
                Log.e(TAG, "getAvailableDevices: CameraManager is null");
                return Collections.emptyList();
            }

            String[] cameraIdList = cameraManager.getCameraIdList();
            Log.d(TAG, "getAvailableDevices: Found " + cameraIdList.length + " camera IDs");
            Log.d(TAG, "getAvailableDevices: Camera IDs: " + Arrays.toString(cameraIdList));
            Log.d(TAG, "getAvailableDevices: Current active camera: " + currentCameraId +
                      ", isRunning: " + isRunning + ", cameraDevice: " + (cameraDevice != null));

            java.util.List<com.ahm.capacitor.camera.preview.model.CameraDevice> devices = new java.util.ArrayList<>();

            for (String cameraId : cameraIdList) {
                Log.d(TAG, "getAvailableDevices: Processing camera ID: " + cameraId);

                try {
                    CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraId);
                    Integer lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);

                    String position = "rear";
                    String deviceType = "wideAngle";
                    String label = "Camera " + cameraId;

                    Log.d(TAG, "getAvailableDevices: Camera " + cameraId + " lens facing: " + lensFacing);

                    if (lensFacing != null) {
                        switch (lensFacing) {
                            case CameraCharacteristics.LENS_FACING_FRONT:
                                position = "front";
                                label = "Front Camera " + cameraId;
                                break;
                            case CameraCharacteristics.LENS_FACING_BACK:
                                position = "rear";
                                label = "Rear Camera " + cameraId;
                                break;
                            case CameraCharacteristics.LENS_FACING_EXTERNAL:
                                position = "external";
                                label = "External Camera " + cameraId;
                                break;
                        }
                    }

                    // Enhanced device type detection
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                        int[] capabilities = characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES);
                        Log.d(TAG, "getAvailableDevices: Camera " + cameraId + " characteristics: " + characteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM));

                        if (capabilities != null) {;
                            boolean isLogicalMultiCamera = false;
                            for (int capability : capabilities) {
                                if (capability == CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA) {
                                    isLogicalMultiCamera = true;
                                    Log.d(TAG, "getAvailableDevices: Camera " + cameraId + " is logical multi-camera");
                                    break;
                                }
                            }

                            // For logical multi-cameras, also add their physical cameras
                            if (isLogicalMultiCamera && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                /*
                                java.util.Set<String> physicalCameraIds = characteristics.getPhysicalCameraIds();
                                Log.d(TAG, "getAvailableDevices: Logical camera " + cameraId + " has " + physicalCameraIds.size() + " physical cameras");
                                Log.d(TAG, "getAvailableDevices: Physical camera IDs: " + physicalCameraIds.toString());

                                for (String physicalId : physicalCameraIds) {
                                    try {
                                        CameraCharacteristics physicalCharacteristics = cameraManager.getCameraCharacteristics(physicalId);
                                        String physicalDeviceType = detectDeviceType(physicalCharacteristics, physicalId);
                                        String physicalLabel = createLabel(physicalId, position, physicalDeviceType);

                                        Log.d(TAG, "getAvailableDevices: Adding physical camera - ID: " + physicalId +
                                                 ", Label: " + physicalLabel + ", Type: " + physicalDeviceType);

                                        devices.add(new com.ahm.capacitor.camera.preview.model.CameraDevice(physicalId, physicalLabel, position, physicalDeviceType));
                                    } catch (Exception e) {
                                        Log.e(TAG, "getAvailableDevices: Error processing physical camera " + physicalId, e);
                                    }
                                }
                                */

                                // Also add the logical camera itself
                                deviceType = "multi";
                                label = createLabel(cameraId, position, deviceType);
                            }
                        }
                    }

                    // Detect device type for regular cameras
                    if (!deviceType.equals("multi")) {
                        deviceType = detectDeviceType(characteristics, cameraId);
                        label = createLabel(cameraId, position, deviceType);
                    }

                    Log.d(TAG, "getAvailableDevices: Adding device - ID: " + cameraId +
                             ", Label: " + label + ", Position: " + position + ", Type: " + deviceType);

                    devices.add(new com.ahm.capacitor.camera.preview.model.CameraDevice(cameraId, label, position, deviceType));
                } catch (Exception e) {
                    Log.e(TAG, "getAvailableDevices: Error processing camera " + cameraId, e);
                    // Continue with next camera instead of failing completely
                }
            }

            Log.d(TAG, "getAvailableDevices: Successfully enumerated " + devices.size() + " total camera devices");
            Log.d(TAG, "getAvailableDevices: Final device list summary:");
            for (com.ahm.capacitor.camera.preview.model.CameraDevice device : devices) {
                Log.d(TAG, "  - Device ID: " + device.getDeviceId() + ", Position: " + device.getPosition() + ", Type: " + device.getDeviceType());
            }
            return devices;
        } catch (CameraAccessException e) {
            Log.e(TAG, "getAvailableDevices: Error getting camera list", e);
            return Collections.emptyList();
        } catch (Exception e) {
            Log.e(TAG, "getAvailableDevices: Unexpected error", e);
            return Collections.emptyList();
        }
    }

    private String detectDeviceType(CameraCharacteristics characteristics, String cameraId) {
        // Try to detect camera types based on focal length
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            float[] focalLengths = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);
            Log.d(TAG, "detectDeviceType: Camera " + cameraId + " zoom: " + characteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE));
            if (focalLengths != null && focalLengths.length > 0) {
                float focalLength = focalLengths[0];
                Log.d(TAG, "detectDeviceType: Camera " + cameraId + " focal length: " + focalLength);

                // Typical focal lengths (in mm equivalent):
                // Ultra-wide: ~13-16mm (smartphone equivalent ~2.2-2.6mm)
                // Wide: ~24-28mm (smartphone equivalent ~4-5mm)
                // Telephoto: ~52-85mm (smartphone equivalent ~8.5-14mm)
                if (focalLength < 2.0f) {
                    return "ultraWide";
                } else if (focalLength > 5.0f) {
                    return "telephoto";
                } else {
                    return "wideAngle";
                }
            }
        }
        return "wideAngle";
    }

    private String createLabel(String cameraId, String position, String deviceType) {
        String baseLabel = position.equals("front") ? "Front Camera" : "Rear Camera";
        String typeLabel = "";

        switch (deviceType) {
            case "ultraWide":
                typeLabel = " (Ultra-wide)";
                break;
            case "telephoto":
                typeLabel = " (Telephoto)";
                break;
            case "wideAngle":
                typeLabel = " (Wide)";
                break;
            case "multi":
                typeLabel = " (Multi)";
                break;
        }

        return baseLabel + " " + cameraId + typeLabel;
    }

    private Size getOptimalPreviewSize() {
        if (cameraCharacteristics == null) {
            return null;
        }

        try {
            StreamConfigurationMap map = cameraCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            if (map == null) {
                return null;
            }

            Size[] previewSizes = map.getOutputSizes(SurfaceHolder.class);
            if (previewSizes == null || previewSizes.length == 0) {
                return null;
            }

            // Get target dimensions
            int targetWidth = sessionConfig.getWidth();
            int targetHeight = sessionConfig.getHeight() - sessionConfig.getPaddingBottom();

            Log.d(TAG, "getOptimalPreviewSize: Target dimensions: " + targetWidth + "x" + targetHeight);

            // Find the best size that fits our requirements
            Size optimalSize = null;
            int minDiff = Integer.MAX_VALUE;

            for (Size size : previewSizes) {
                Log.d(TAG, "getOptimalPreviewSize: Available size: " + size.getWidth() + "x" + size.getHeight());

                // Calculate how well this size fits our target
                int diff = Math.abs(size.getWidth() - targetWidth) + Math.abs(size.getHeight() - targetHeight);

                // Prefer sizes that don't exceed our target by too much
                if (size.getWidth() <= targetWidth * 1.2 && size.getHeight() <= targetHeight * 1.2) {
                    if (diff < minDiff) {
                        minDiff = diff;
                        optimalSize = size;
                    }
                }
            }

            // If no good fit found, use the first available size
            if (optimalSize == null && previewSizes.length > 0) {
                optimalSize = previewSizes[0];
                Log.d(TAG, "getOptimalPreviewSize: No good fit found, using first available: " +
                      optimalSize.getWidth() + "x" + optimalSize.getHeight());
            }

            return optimalSize;
        } catch (Exception e) {
            Log.e(TAG, "getOptimalPreviewSize: Error getting optimal preview size", e);
            return null;
        }
    }

    public ZoomFactors getZoomFactors() {
        if (sortedLenses != null && !sortedLenses.isEmpty()) {
            float minZoom = sortedLenses.get(0).getBaseZoomRatio();
            CameraLens maxLens = sortedLenses.get(sortedLenses.size() - 1);
            float maxZoom = Math.round(maxLens.getBaseZoomRatio() * maxLens.getMaxZoom());
            return new ZoomFactors(minZoom, maxZoom, currentZoomRatio);
        }

        // Fallback for single-lens cameras or older APIs
        if (cameraCharacteristics != null) {
            Range<Float> zoomRange = cameraCharacteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);
            // Float maxZoom = cameraCharacteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
            // if (maxZoom == null) {
            //     maxZoom = 1.0f;
            // }
            return new ZoomFactors(zoomRange.getLower(), zoomRange.getUpper(), currentZoomRatio);
        }

        // If no active session, check first available camera
        try {
            String[] cameraIdList = cameraManager.getCameraIdList();
            if (cameraIdList.length > 0) {
                CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraIdList[0]);
                Range<Float> zoomRange = characteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);
                // Float maxZoom = characteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
                // if (maxZoom == null) {
                //     maxZoom = 1.0f;
                // }
                return new ZoomFactors(zoomRange.getLower(), zoomRange.getUpper(), 1.0f); // Default current zoom to 1.0
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "getZoomFactors: Error checking zoom capabilities", e);
        }

        return new ZoomFactors(1.0f, 1.0f, 1.0f);
    }

    public List<CameraLens> getAvailableLenses() {
        Log.d(TAG, "getAvailableLenses: Getting available lenses for current camera");
        List<CameraLens> lenses = new ArrayList<>();

        if (sortedLenses == null || sortedLenses.isEmpty()) {
            Log.w(TAG, "getAvailableLenses: No lenses available - single lens camera or not initialized");
            return lenses;
        }

        String currentPosition = getCurrentPosition();
        if (currentPosition == null) {
            currentPosition = "rear";
        }

        for (CameraLens internalLens : sortedLenses) {
            String deviceType = determineDeviceTypeFromLens(internalLens);
            String label = createLensLabel(deviceType, internalLens.getBaseZoomRatio());
            boolean isActive = internalLens.getId().equals(currentCameraId);

            com.ahm.capacitor.camera.preview.model.CameraLens lens =
                new com.ahm.capacitor.camera.preview.model.CameraLens(
                    internalLens.getId(),
                    label,
                    currentPosition,
                    deviceType,
                    internalLens.getFocalLength(),
                    internalLens.getMinZoom(),
                    internalLens.getMaxZoom(),
                    internalLens.getBaseZoomRatio(),
                    isActive
                );

            lenses.add(lens);
            Log.d(TAG, "getAvailableLenses: Lens - " + label + " (baseZoom: " + internalLens.getBaseZoomRatio() + ", active: " + isActive + ")");
        }

        return lenses;
    }

    public CameraLens getCurrentLens() {
        Log.d(TAG, "getCurrentLens: Getting current lens based on zoom ratio: " + currentZoomRatio);

        if (sortedLenses == null || sortedLenses.isEmpty()) {
            Log.w(TAG, "getCurrentLens: No lenses available");
            return null;
        }

        // Find the lens that would be used for the current zoom ratio (same logic as setZoom)
        CameraLens targetLens = sortedLenses.get(0);
        for (CameraLens lens : sortedLenses) {
            if (currentZoomRatio >= lens.getBaseZoomRatio()) {
                targetLens = lens;
            } else {
                break;
            }
        }

        String currentPosition = getCurrentPosition();
        if (currentPosition == null) {
            currentPosition = "rear";
        }

        String deviceType = determineDeviceTypeFromLens(targetLens);
        String label = targetLens.getLabel();

        Log.d(TAG, "getCurrentLens: Current lens for zoom " + currentZoomRatio + " is " + label);

        return new com.ahm.capacitor.camera.preview.model.CameraLens(
            targetLens.getId(),
            label,
            currentPosition,
            deviceType,
            targetLens.getFocalLength(),
            targetLens.getMinZoom(),
            targetLens.getMaxZoom(),
            targetLens.getBaseZoomRatio(),
            true // This is the current/active lens
        );
    }

    private String determineDeviceTypeFromLens(CameraLens lens) {
        if (lens.getBaseZoomRatio() <= 1.0f) {
            return "ultraWide";
        } else if (lens.getBaseZoomRatio() >= 2.0f) {
            return "telephoto";
        } else {
            // Determine by focal length if base zoom ratio is inconclusive
            if (lens.getFocalLength() < 2.0f) {
                return "ultraWide";
            } else if (lens.getFocalLength() > 5.0f) {
                return "telephoto";
            } else {
                return "wideAngle";
            }
        }
    }

    private String createLensLabel(String deviceType, float baseZoomRatio) {
        switch (deviceType) {
            case "ultraWide":
                return String.format("%.1fx Ultra Wide", baseZoomRatio);
            case "wideAngle":
                return String.format("%.1fx Wide", baseZoomRatio);
            case "telephoto":
                return String.format("%.1fx Telephoto", baseZoomRatio);
            default:
                return String.format("%.1fx", baseZoomRatio);
        }
    }

    public void setZoom(float zoomRatio) throws Exception {
        if (cameraCharacteristics == null || sortedLenses == null || sortedLenses.isEmpty()) {
            throw new Exception("Camera not initialized or does not support zoom");
        }

        Range<Float> zoomRange = cameraCharacteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);
        Log.d(TAG, "setZoom: Zoom range: " + zoomRange.getLower() + " - " + zoomRange.getUpper());

        if (zoomRatio < zoomRange.getLower()) {
            zoomRatio = zoomRange.getLower();
        } else if (zoomRatio > zoomRange.getUpper()) {
            zoomRatio = zoomRange.getUpper();
        }

        Float mappedZoomRatio = zoomRatio;

        if (zoomRatio < 1.0f) {
            Log.d(TAG, "setZoom: Zoom ratio is less than 1.0");
            String ultraWideId = findUltraWideCamera();

            if (ultraWideId != null && !ultraWideId.equals(currentCameraId)) {
                Log.d(TAG, "setZoom: Switching to ultra-wide camera: " + ultraWideId);
                switchToDevice(ultraWideId);
            }
            mappedZoomRatio = mapToUltraWideZoom(zoomRatio, ultraWideId);
        } else if (zoomRatio >= 3.0f) {
            String telephotoId = findTelephotoCamera();

            if (telephotoId != null && !telephotoId.equals(currentCameraId)) {
                 switchToDevice(telephotoId);
             }
             mappedZoomRatio = mapToTelephotoZoom(zoomRatio, telephotoId);
        } else {
            String wideAngleId = findLogicalCamera();
            if (wideAngleId != null && !wideAngleId.equals(currentCameraId)) {
                Log.d(TAG, "setZoom: Switching to wide-angle camera: " + wideAngleId);
                switchToDevice(wideAngleId);
            }
            mappedZoomRatio = mappedZoomRatio;
        }

        setZoomInternal(mappedZoomRatio);
        currentZoomRatio = zoomRatio;
    }

    private float mapToTelephotoZoom(float requestedZoomRatio, String telephotoCameraId) {
        try {
            CameraCharacteristics telephotoChars = cameraManager.getCameraCharacteristics(telephotoCameraId);
            Range<Float> telephotoNativeZoomRange = telephotoChars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);
            Range<Float> logicalZoomRange = cameraCharacteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);

            if (telephotoNativeZoomRange == null || logicalZoomRange == null) return requestedZoomRatio;

            CameraLens telephotoLens = null;
            for (CameraLens lens : sortedLenses) {
                if (lens.getId().equals(telephotoCameraId)) {
                    telephotoLens = lens;
                    break;
                }
            }

            if (telephotoLens == null) return requestedZoomRatio;

            // Define the ranges for mapping
            float logicalMin = telephotoLens.getBaseZoomRatio();
            float logicalMax = logicalZoomRange.getUpper();

            float nativeMin = telephotoNativeZoomRange.getLower();
            float nativeMax = telephotoNativeZoomRange.getUpper();

            // Perform the linear mapping
            float mappedZoom = nativeMin + (requestedZoomRatio - logicalMin) * (nativeMax - nativeMin) / (logicalMax - logicalMin) + 0.5f;

            Log.d(TAG, "mapToTelephotoZoom: Requested " + requestedZoomRatio + " -> Mapped to " + mappedZoom);
            Log.d(TAG, "mapToTelephotoZoom: Logical Range [" + logicalMin + ", " + logicalMax + "], Native Range [" + nativeMin + ", " + nativeMax + "]");

            return Math.max(nativeMin, Math.min(nativeMax, mappedZoom));
        } catch (CameraAccessException e) {
            Log.e(TAG, "mapToTelephotoZoom: Could not access telephoto camera characteristics. Falling back to digital zoom.", e);
            return requestedZoomRatio;
        }
    }

    private float mapToUltraWideZoom(float requestedZoomRatio, String ultraWideCameraId) {
        try {
            CameraCharacteristics ultraWideChars = cameraManager.getCameraCharacteristics(ultraWideCameraId);
            Range<Float> ultraWideNativeZoomRange = ultraWideChars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);

            if (ultraWideNativeZoomRange == null) return requestedZoomRatio;

            CameraLens ultraWideLens = null;
            CameraLens wideAngleLens = null;
            for (int i = 0; i < sortedLenses.size(); i++) {
                if (sortedLenses.get(i).getId().equals(ultraWideCameraId)) {
                    ultraWideLens = sortedLenses.get(i);
                    if (i + 1 < sortedLenses.size()) {
                        wideAngleLens = sortedLenses.get(i + 1);
                    }
                    break;
                }
            }

            if (ultraWideLens == null || wideAngleLens == null) {
                return requestedZoomRatio / (ultraWideLens != null ? ultraWideLens.getBaseZoomRatio() : 1.0f);
            }

            // Define the ranges for mapping. Note the inverted logical range.
            float logicalMin = wideAngleLens.getBaseZoomRatio(); // e.g., 1.0
            float logicalMax = ultraWideLens.getBaseZoomRatio(); // e.g., 0.5

            float nativeMin = ultraWideNativeZoomRange.getLower(); // e.g., 1.0
            float nativeMax = ultraWideNativeZoomRange.getUpper(); // e.g., 3.0

            // Perform the inverse linear mapping
            // As logical zoom goes from 1.0 down to 0.5, native zoom goes from max down to min.
            float mappedZoom = nativeMax - (logicalMin - requestedZoomRatio) * (nativeMax - nativeMin) / (logicalMin - logicalMax);

            Log.d(TAG, "mapToUltraWideZoom: Requested " + requestedZoomRatio + " -> Mapped to " + mappedZoom);
            Log.d(TAG, "mapToUltraWideZoom: Logical Range [" + logicalMin + ", " + logicalMax + "], Native Range [" + nativeMin + ", " + nativeMax + "]");

            return Math.max(nativeMin, Math.min(nativeMax, mappedZoom));
        } catch (CameraAccessException e) {
            Log.e(TAG, "mapToUltraWideZoom: Could not access ultra-wide camera characteristics. Falling back to digital zoom.", e);
            return requestedZoomRatio;
        }
    }

    /**
     * Find ultra-wide camera ID if available.
     *
     * @return Ultra-wide camera ID or null if not found
     */
    private String findUltraWideCamera() {
        if (sortedLenses == null || sortedLenses.isEmpty()) {
            Log.d(TAG, "findUltraWideCamera: No sorted lenses available.");
            return null;
        }
        for (CameraLens lens : sortedLenses) {
            if ("ultraWide".equals(determineDeviceTypeFromLens(lens))) {
                Log.d(TAG, "findUltraWideCamera: Found ultra-wide camera: " + lens.getId());
                return lens.getId();
            }
        }
        Log.d(TAG, "findUltraWideCamera: No ultra-wide camera found in sorted lenses.");
        return null;
    }

    /**
     * Find logical camera ID if available.
     *
     * @return logical camera ID or null if not found
     */
    private String findLogicalCamera() {
        return this.currentLogicalCameraId;
    }

    /**
     * Find telephoto camera ID if available.
     *
     * @return Telephoto camera ID or null if not found
     */
    private String findTelephotoCamera() {
        if (sortedLenses == null || sortedLenses.isEmpty()) {
            Log.d(TAG, "findTelephotoCamera: No sorted lenses available.");
            return null;
        }
        for (CameraLens lens : sortedLenses) {
            if ("telephoto".equals(determineDeviceTypeFromLens(lens))) {
                Log.d(TAG, "findTelephotoCamera: Found telephoto camera: " + lens.getId());
                return lens.getId();
            }
        }
        Log.d(TAG, "findTelephotoCamera: No telephoto camera found in sorted lenses.");
        return null;
    }

    private void setZoomInternal(float zoomRatio) {
        if (previewRequestBuilder == null || captureSession == null || cameraCharacteristics == null) {
            return;
        }

        try {
            android.graphics.Rect activeArraySize = cameraCharacteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
            if (activeArraySize != null) {
                int cropW = Math.round((float) activeArraySize.width() / zoomRatio);
                int cropH = Math.round((float) activeArraySize.height() / zoomRatio);
                int cropX = (activeArraySize.width() - cropW) / 2;
                int cropY = (activeArraySize.height() - cropH) / 2;

                android.graphics.Rect cropRegion = new android.graphics.Rect(cropX, cropY, cropX + cropW, cropY + cropH);
                previewRequestBuilder.set(CaptureRequest.SCALER_CROP_REGION, cropRegion);

                previewRequest = previewRequestBuilder.build();
                captureSession.setRepeatingRequest(previewRequest, captureCallback, backgroundHandler);

                currentZoomRatio = zoomRatio;
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "Error setting zoom", e);
        }
    }

    public List<String> getSupportedFlashModes() {
        // Try to use current camera characteristics if available
        if (cameraCharacteristics != null) {
            Boolean flashAvailable = cameraCharacteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
            if (flashAvailable != null && flashAvailable) {
                return Arrays.asList("off", "on", "auto");
            } else {
                return Arrays.asList("off");
            }
        }

        // If no active session, check first available camera
        try {
            String[] cameraIdList = cameraManager.getCameraIdList();
            if (cameraIdList.length > 0) {
                CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraIdList[0]);
                Boolean flashAvailable = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                if (flashAvailable != null && flashAvailable) {
                    String[] flashModes = new String[] { "off", "on", "auto" };
                    Log.d(TAG, "getSupportedFlashModes: Flash modes: " + Arrays.toString(flashModes));
                    return Arrays.asList(flashModes);
                }
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "getSupportedFlashModes: Error checking flash availability", e);
        }

        return Arrays.asList("off");
    }

    // Helper to check if a specific AE mode is supported
    private boolean isAeModeSupported(int mode) {
        if (cameraCharacteristics == null) return false;
        int[] availableAeModes = cameraCharacteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_MODES);
        if (availableAeModes == null) return false;
        for (int aeMode : availableAeModes) {
            if (aeMode == mode) return true;
        }
        return false;
    }

    public String getFlashMode() {
        switch (currentFlashMode) {
            case CameraMetadata.CONTROL_AE_MODE_ON_ALWAYS_FLASH:
            case CameraMetadata.FLASH_MODE_SINGLE:
                return "on";
            case CameraMetadata.CONTROL_AE_MODE_ON_AUTO_FLASH:
                return "auto";
            default:
                return "off";
        }
    }

    public void setFlashMode(String mode) throws Exception {
        int requestedAeMode;

        switch (mode) {
            case "on":
                requestedAeMode = CameraMetadata.CONTROL_AE_MODE_ON_ALWAYS_FLASH;
                break;
            case "auto":
                requestedAeMode = CameraMetadata.CONTROL_AE_MODE_ON_AUTO_FLASH;
                break;
            default:
                requestedAeMode = CameraMetadata.CONTROL_AE_MODE_ON;
                break;
        }

        if (isAeModeSupported(requestedAeMode)) {
            currentFlashMode = requestedAeMode;
        }

        int[] availableAeModes = cameraCharacteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_MODES);
        Log.d(TAG, "Available AE modes: " + Arrays.toString(availableAeModes));

        Boolean flashAvailable = cameraCharacteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
        Log.d(TAG, "Flash available: " + flashAvailable);
    }

    public String getCurrentDeviceId() {
        return currentCameraId;
    }

    public void switchToDevice(String deviceId) throws Exception {
        if (deviceId == null || deviceId.equals(currentCameraId)) {
            return;
        }

        // Log current camera state before switch
        Log.d(TAG, "switchToDevice: Current camera ID: " + currentCameraId + ", Target ID: " + deviceId);
        Log.d(TAG, "switchToDevice: Camera running: " + isRunning + ", Camera device: " + (cameraDevice != null));

        // Verify the device exists (checking both logical and physical cameras)
        String targetLogicalCameraId = null;
        boolean isPhysicalCamera = false;

        try {
            String[] cameraIds = cameraManager.getCameraIdList();
            Log.d(TAG, "switchToDevice: Total logical cameras available: " + cameraIds.length);
            Log.d(TAG, "switchToDevice: Logical camera IDs: " + Arrays.toString(cameraIds));

            // First check if it's a logical camera
            for (String id : cameraIds) {
                if (id.equals(deviceId)) {
                    targetLogicalCameraId = deviceId;
                    Log.d(TAG, "switchToDevice: Target is logical camera: " + deviceId);
                    break;
                }
            }

            // If not found as logical camera, check if it's a physical camera
            if (targetLogicalCameraId == null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                Log.d(TAG, "switchToDevice: Target not found as logical camera, checking physical cameras");

                for (String logicalId : cameraIds) {
                    try {
                        CameraCharacteristics chars = cameraManager.getCameraCharacteristics(logicalId);

                        // Check if this logical camera has the requested physical camera
                        java.util.Set<String> physicalCameraIds = chars.getPhysicalCameraIds();
                        Log.d(TAG, "switchToDevice: Logical camera " + logicalId + " physical cameras: " + physicalCameraIds.toString());

                        if (physicalCameraIds.contains(deviceId)) {
                            targetLogicalCameraId = logicalId;
                            isPhysicalCamera = true;
                            Log.d(TAG, "switchToDevice: Found target " + deviceId + " as physical camera in logical camera " + logicalId);
                            break;
                        }
                    } catch (Exception e) {
                        Log.w(TAG, "switchToDevice: Error checking physical cameras for " + logicalId + ": " + e.getMessage());
                    }
                }
            }

        } catch (CameraAccessException e) {
            Log.e(TAG, "switchToDevice: Error getting camera ID list: " + e.getMessage());
            throw new Exception("Error checking device existence: " + e.getMessage());
        }

        if (targetLogicalCameraId == null) {
            Log.e(TAG, "switchToDevice: Device not found: " + deviceId);
            throw new Exception("Device not found: " + deviceId);
        }

        Log.d(TAG, "switchToDevice: Using logical camera " + targetLogicalCameraId +
                   (isPhysicalCamera ? " with physical camera " + deviceId : ""));

        Log.d(TAG, "switchToDevice: Switching from " + currentCameraId + " to " + deviceId);

        // Store the current running state - we want to maintain it during the switch
        boolean wasRunning = isRunning;

        // Close current camera but keep session alive
        closeCamera();

        // Log camera state after closing
        try {
            String[] cameraIdsAfterClose = cameraManager.getCameraIdList();
            Log.d(TAG, "switchToDevice: After closeCamera - Total cameras available: " + cameraIdsAfterClose.length);
            Log.d(TAG, "switchToDevice: After closeCamera - Camera IDs: " + Arrays.toString(cameraIdsAfterClose));
        } catch (CameraAccessException e) {
            Log.e(TAG, "switchToDevice: Error getting camera ID list after close: " + e.getMessage());
        }

                // Update camera state
        currentCameraId = deviceId;
        currentLogicalCameraId = targetLogicalCameraId;
        isCurrentCameraPhysical = isPhysicalCamera;

        Log.d(TAG, "switchToDevice: Camera state updated - currentCameraId: " + currentCameraId +
                   ", currentLogicalCameraId: " + currentLogicalCameraId +
                   ", isPhysical: " + isCurrentCameraPhysical);

        // If camera was running, restore running state and reopen camera
        if (wasRunning) {
            // Keep isRunning true during the switch to avoid showing "stopped" status
            isRunning = true;
            openCamera();
        }
    }

    public void flipCamera() throws Exception {
        Log.d(TAG, "flipCamera: Starting camera flip");
        String currentPosition = getCurrentPosition();
        if (currentPosition == null) {
            throw new Exception("Could not determine current camera position to flip.");
        }

        String targetPosition = "front".equals(currentPosition) ? "rear" : "front";

        Log.d(TAG, "flipCamera: Current position: " + currentPosition + ", target: " + targetPosition);

        String newCameraId = getCameraIdByPosition(targetPosition);
        if (newCameraId == null) {
            Log.e(TAG, "flipCamera: No camera found for position: " + targetPosition);
            throw new Exception("No camera found for position: " + targetPosition);
        }

        Log.d(TAG, "flipCamera: Found target camera ID: " + newCameraId + ". Switching device.");

        // Use switchToDevice for a more efficient switch that preserves the session config
        switchToDevice(newCameraId);
    }

    private String getCurrentPosition() {
        if (cameraCharacteristics == null) {
            Log.w(TAG, "getCurrentPosition: cameraCharacteristics is null, cannot determine position.");
            return null;
        }

        Integer lensFacing = cameraCharacteristics.get(CameraCharacteristics.LENS_FACING);
        if (lensFacing != null) {
            switch (lensFacing) {
                case CameraCharacteristics.LENS_FACING_FRONT:
                    return "front";
                case CameraCharacteristics.LENS_FACING_BACK:
                    return "rear";
                default:
                    return "external";
            }
        }

        Log.w(TAG, "getCurrentPosition: Lens facing is null, cannot determine position.");
        return null;
    }

    private byte[] correctImageRotation(byte[] imageBytes) {
        try {
            if (cameraCharacteristics == null) {
                return imageBytes;
            }

            // Get sensor orientation
            Integer sensorOrientation = cameraCharacteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
            if (sensorOrientation == null) {
                return imageBytes;
            }

            // Decode bitmap
            Bitmap bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.length);
            if (bitmap == null) {
                return imageBytes;
            }

            // Calculate rotation needed
            int rotation = 0;
            boolean isFrontCamera = false;
            Integer lensFacing = cameraCharacteristics.get(CameraCharacteristics.LENS_FACING);

            if (lensFacing != null && lensFacing == CameraCharacteristics.LENS_FACING_FRONT) {
                isFrontCamera = true;
                // Front camera rotation calculation
                // For most devices, front camera needs: (360 - sensorOrientation) % 360
                // But some devices need different calculations
                rotation = (360 - sensorOrientation) % 360;

                // Common adjustments for front cameras
                if (rotation == 270) {
                    rotation = 90;  // Fix common upside-down issue
                } else if (rotation == 90) {
                    rotation = 270;
                }
            } else {
                // Back camera: use sensor orientation directly
                rotation = sensorOrientation;
            }

            Log.d(TAG, "correctImageRotation: Sensor orientation=" + sensorOrientation +
                  ", front camera=" + isFrontCamera + ", calculated rotation=" + rotation);

            // Apply transformations
            Matrix matrix = new Matrix();

            // For front camera, mirror first, then rotate
            if (isFrontCamera) {
                matrix.postScale(-1, 1);  // Mirror horizontally
            }

            // Apply rotation
            if (rotation != 0) {
                matrix.postRotate(rotation);
            }

            // Apply transformations
            if (!matrix.isIdentity()) {
                bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
            }

            // Convert back to byte array
            ByteArrayOutputStream stream = new ByteArrayOutputStream();
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream);
            return stream.toByteArray();

        } catch (Exception e) {
            Log.e(TAG, "correctImageRotation: Error correcting rotation", e);
            return imageBytes; // Return original if correction fails
        }
    }
}

