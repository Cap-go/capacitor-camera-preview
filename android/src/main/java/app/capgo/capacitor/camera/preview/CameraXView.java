package app.capgo.capacitor.camera.preview;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.location.Location;
import android.media.MediaScannerConnection;
import android.os.Build;
import android.os.Environment;
import android.util.Base64;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.Range;
import android.util.Rational;
import android.util.Size;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.WindowMetrics;
import android.webkit.WebView;
import android.widget.FrameLayout;
import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.camera.camera2.interop.Camera2CameraControl;
import androidx.camera.camera2.interop.Camera2CameraInfo;
import androidx.camera.camera2.interop.CaptureRequestOptions;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.core.AspectRatio;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraInfo;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExposureState;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.FocusMeteringResult;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.MeteringPointFactory;
import androidx.camera.core.Preview;
import androidx.camera.core.ResolutionInfo;
import androidx.camera.core.TorchState;
import androidx.camera.core.ZoomState;
import androidx.camera.core.resolutionselector.AspectRatioStrategy;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import androidx.camera.core.resolutionselector.ResolutionStrategy;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.video.FallbackStrategy;
import androidx.camera.video.FileOutputOptions;
import androidx.camera.video.Quality;
import androidx.camera.video.QualitySelector;
import androidx.camera.video.Recorder;
import androidx.camera.video.Recording;
import androidx.camera.video.VideoCapture;
import androidx.camera.video.VideoRecordEvent;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.exifinterface.media.ExifInterface;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleObserver;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;
import app.capgo.capacitor.camera.preview.model.CameraSessionConfiguration;
import app.capgo.capacitor.camera.preview.model.LensInfo;
import app.capgo.capacitor.camera.preview.model.ZoomFactors;
import com.google.common.util.concurrent.ListenableFuture;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONObject;

public class CameraXView implements LifecycleOwner, LifecycleObserver {

    private static final String TAG = "CameraPreview CameraXView";
    private static final String FOCUS_INDICATOR_TAG = "cpcp_focus_indicator";

    public interface CameraXViewListener {
        void onPictureTaken(String base64, JSONObject exif);
        void onPictureTakenError(String message);
        void onSampleTaken(String result);
        void onSampleTakenError(String message);
        void onCameraStarted(int width, int height, int x, int y);
        void onCameraStartError(String message);
        void onCameraStopped(CameraXView source);
    }

    public interface VideoRecordingCallback {
        void onSuccess(String filePath);
        void onError(String message);
    }

    private ProcessCameraProvider cameraProvider;
    private Camera camera;
    private ImageCapture imageCapture;
    private ImageCapture sampleImageCapture;
    private VideoCapture<Recorder> videoCapture;
    private Recording currentRecording;
    private File currentVideoFile;
    private VideoRecordingCallback currentVideoCallback;
    private PreviewView previewView;
    private GridOverlayView gridOverlayView;
    private FrameLayout previewContainer;
    private View focusIndicatorView;
    private long focusIndicatorAnimationId = 0; // Incrementing token to invalidate previous animations
    private CameraSelector currentCameraSelector;
    private String currentDeviceId;
    private int currentFlashMode = ImageCapture.FLASH_MODE_OFF;
    private CameraSessionConfiguration sessionConfig;
    private CameraXViewListener listener;
    private final Context context;
    private final WebView webView;
    private final LifecycleRegistry lifecycleRegistry;
    private final Executor mainExecutor;
    private ExecutorService cameraExecutor;
    private boolean isRunning = false;
    private Size currentPreviewResolution = null;
    private ListenableFuture<FocusMeteringResult> currentFocusFuture = null; // Track current focus operation
    private String currentExposureMode = "CONTINUOUS"; // Default behavior
    // Face Detection
    private FaceDetectionManager faceDetectionManager;
    private androidx.camera.core.ImageAnalysis imageAnalysis;
    // Capture/stop coordination
    private final Object captureLock = new Object();
    private volatile boolean isCapturingPhoto = false;
    private volatile boolean stopRequested = false;
    private volatile boolean previewDetachedOnDeferredStop = false;

    // Operation coordination (acts like a semaphore to prevent stop during active ops)
    private final Object operationLock = new Object();
    private int activeOperations = 0;
    private boolean stopPending = false;

    private boolean IsOperationRunning(String name) {
        synchronized (operationLock) {
            if (stopPending) {
                Log.d(TAG, "beginOperation: blocked '" + name + "' due to stopPending");
                return true;
            }
            activeOperations++;
            Log.v(TAG, "beginOperation: '" + name + "' (active=" + activeOperations + ")");
            return false;
        }
    }

    private void endOperation(String name) {
        boolean shouldStop = false;
        synchronized (operationLock) {
            if (activeOperations > 0) activeOperations--;
            Log.v(TAG, "endOperation: '" + name + "' (active=" + activeOperations + ")");
            if (activeOperations == 0 && stopPending) {
                shouldStop = true;
            }
        }
        if (shouldStop) {
            Log.d(TAG, "endOperation: all operations complete; performing deferred stop");
            performImmediateStop();
        }
    }

    public boolean isCapturing() {
        return isCapturingPhoto;
    }

    public boolean isBusy() {
        synchronized (captureLock) {
            return isCapturingPhoto || stopRequested;
        }
    }

    public boolean isStopDeferred() {
        synchronized (operationLock) {
            return stopPending && activeOperations > 0;
        }
    }

    public boolean isStopping() {
        synchronized (operationLock) {
            return stopPending;
        }
    }

    public CameraXView(Context context, WebView webView) {
        this.context = context;
        this.webView = webView;
        this.lifecycleRegistry = new LifecycleRegistry(this);
        this.mainExecutor = ContextCompat.getMainExecutor(context);

        mainExecutor.execute(() -> lifecycleRegistry.setCurrentState(Lifecycle.State.CREATED));
    }

    @NonNull
    @Override
    public Lifecycle getLifecycle() {
        return lifecycleRegistry;
    }

    public CameraSessionConfiguration getSessionConfig() {
        return sessionConfig;
    }

    public void setListener(CameraXViewListener listener) {
        this.listener = listener;
    }

    public boolean isRunning() {
        return isRunning;
    }

    public View getPreviewContainer() {
        return previewContainer;
    }

    private void saveImageToGallery(byte[] data) {
        try {
            // Detect image format from byte array header
            String extension = ".jpg";
            String mimeType = "image/jpeg";

            if (data.length >= 8) {
                // Check for PNG signature (89 50 4E 47 0D 0A 1A 0A)
                if (data[0] == (byte) 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
                    extension = ".png";
                    mimeType = "image/png";
                }
                // Check for JPEG signature (FF D8 FF)
                else if (data[0] == (byte) 0xFF && data[1] == (byte) 0xD8 && data[2] == (byte) 0xFF) {
                    extension = ".jpg";
                    mimeType = "image/jpeg";
                }
                // Check for WebP signature (RIFF ... WEBP)
                else if (
                    data[0] == 0x52 &&
                    data[1] == 0x49 &&
                    data[2] == 0x46 &&
                    data[3] == 0x46 &&
                    data.length >= 12 &&
                    data[8] == 0x57 &&
                    data[9] == 0x45 &&
                    data[10] == 0x42 &&
                    data[11] == 0x50
                ) {
                    extension = ".webp";
                    mimeType = "image/webp";
                }
            }

            File photo = new File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "IMG_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new java.util.Date()) + extension
            );
            FileOutputStream fos = new FileOutputStream(photo);
            fos.write(data);
            fos.close();

            // Notify the gallery of the new image
            MediaScannerConnection.scanFile(this.context, new String[] { photo.getAbsolutePath() }, new String[] { mimeType }, null);
        } catch (IOException e) {
            Log.e(TAG, "Error saving image to gallery", e);
        }
    }

    private void saveImageToGallery(byte[] data, ExifInterface sourceExif, Integer finalWidth, Integer finalHeight) {
        try {
            // First, write the bytes to a file
            String extension = ".jpg";
            String mimeType = "image/jpeg";
            if (data.length >= 8) {
                if (data[0] == (byte) 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
                    extension = ".png";
                    mimeType = "image/png";
                } else if (data[0] == (byte) 0xFF && data[1] == (byte) 0xD8 && data[2] == (byte) 0xFF) {
                    extension = ".jpg";
                    mimeType = "image/jpeg";
                } else if (
                    data[0] == 0x52 &&
                    data[1] == 0x49 &&
                    data[2] == 0x46 &&
                    data[3] == 0x46 &&
                    data.length >= 12 &&
                    data[8] == 0x57 &&
                    data[9] == 0x45 &&
                    data[10] == 0x42 &&
                    data[11] == 0x50
                ) {
                    extension = ".webp";
                    mimeType = "image/webp";
                }
            }

            File photo = new File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "IMG_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new java.util.Date()) + extension
            );

            FileOutputStream fos = new FileOutputStream(photo);
            fos.write(data);
            fos.flush();
            fos.close();

            // No EXIF rewrite here; bytes already contain EXIF when needed

            // Notify the gallery of the new image
            MediaScannerConnection.scanFile(this.context, new String[] { photo.getAbsolutePath() }, new String[] { mimeType }, null);
        } catch (IOException e) {
            Log.e(TAG, "Error saving image to gallery (with exif)", e);
        }
    }

    public void startSession(CameraSessionConfiguration config) {
        this.sessionConfig = config;
        cameraExecutor = Executors.newSingleThreadExecutor();
        synchronized (operationLock) {
            activeOperations = 0;
            stopPending = false;
        }
        mainExecutor.execute(() -> {
            lifecycleRegistry.setCurrentState(Lifecycle.State.STARTED);
            setupCamera();
        });
    }

    public void stopSession() {
        // Mark stop pending; reject new operations and wait for active ones to finish
        synchronized (operationLock) {
            stopPending = true;
        }
        stopRequested = true;

        boolean hasOps;
        synchronized (operationLock) {
            hasOps = activeOperations > 0;
        }
        if (hasOps) {
            // Detach preview so UI can close
            if (!previewDetachedOnDeferredStop) {
                mainExecutor.execute(() -> {
                    try {
                        if (previewContainer != null) {
                            ViewGroup parent = (ViewGroup) previewContainer.getParent();
                            if (parent != null) {
                                parent.removeView(previewContainer);
                            }
                        }
                        previewDetachedOnDeferredStop = true;
                    } catch (Exception ignored) {}
                });
            }
            // Cancel focus to hasten completion
            if (currentFocusFuture != null && !currentFocusFuture.isDone()) {
                try {
                    currentFocusFuture.cancel(true);
                } catch (Exception ignored) {}
            }
            return;
        }

        performImmediateStop();
    }

    private void performImmediateStop() {
        isRunning = false;
        // Cancel any ongoing focus operation when stopping session
        if (currentFocusFuture != null && !currentFocusFuture.isDone()) {
            currentFocusFuture.cancel(true);
        }
        currentFocusFuture = null;

        mainExecutor.execute(() -> {
            try {
                lifecycleRegistry.setCurrentState(Lifecycle.State.DESTROYED);
                if (cameraProvider != null) {
                    cameraProvider.unbindAll();
                }
                lifecycleRegistry.setCurrentState(Lifecycle.State.DESTROYED);
                if (cameraExecutor != null) {
                    cameraExecutor.shutdown();
                }
                removePreviewView();
            } catch (Exception e) {
                Log.w(TAG, "performImmediateStop: error during stop", e);
            } finally {
                stopRequested = false;
                previewDetachedOnDeferredStop = false;
                synchronized (operationLock) {
                    activeOperations = 0;
                    stopPending = false;
                }
                if (listener != null) {
                    try {
                        listener.onCameraStopped(this);
                    } catch (Exception ignored) {}
                }
            }
        });
    }

    private void setupCamera() {
        ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(context);
        cameraProviderFuture.addListener(
            () -> {
                try {
                    cameraProvider = cameraProviderFuture.get();
                    setupPreviewView();
                    bindCameraUseCases();
                } catch (Exception e) {
                    if (listener != null) {
                        listener.onCameraStartError("Error initializing camera: " + e.getMessage());
                    }
                }
            },
            mainExecutor
        );
    }

    private void setupPreviewView() {
        if (previewView != null) {
            removePreviewView();
        }
        if (sessionConfig.isToBack()) {
            webView.setBackgroundColor(android.graphics.Color.TRANSPARENT);
        }

        // Create a container to hold both the preview and grid overlay
        previewContainer = new FrameLayout(context);
        // Ensure container can receive touch events
        previewContainer.setClickable(true);
        previewContainer.setFocusable(true);

        // Disable any potential drawing artifacts that might cause 1px offset
        previewContainer.setLayerType(View.LAYER_TYPE_HARDWARE, null);

        // Ensure no clip bounds that might cause visual offset
        previewContainer.setClipChildren(false);
        previewContainer.setClipToPadding(false);

        // Create and setup the preview view
        previewView = new PreviewView(context);
        // Use TextureView-backed implementation for broader device compatibility when overlaying with WebView
        // This avoids SurfaceView z-order issues seen on some MIUI/EMUI devices.
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        // Match iOS behavior: FIT when no aspect ratio, FILL when aspect ratio is set
        String initialAspectRatio = sessionConfig != null ? sessionConfig.getAspectRatio() : null;
        previewView.setScaleType(
            (initialAspectRatio == null || initialAspectRatio.isEmpty())
                ? PreviewView.ScaleType.FIT_CENTER
                : PreviewView.ScaleType.FILL_CENTER
        );
        // Also make preview view touchable as backup
        previewView.setClickable(true);
        previewView.setFocusable(true);

        // Intentionally no native gesture handling (tap-to-focus, pinch-to-zoom)
        // Focus and zoom are controlled exclusively via JS API calls for parity with iOS.

        previewContainer.addView(
            previewView,
            new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        );

        // Create and setup the grid overlay
        gridOverlayView = new GridOverlayView(context);
        // Make grid overlay not intercept touch events
        gridOverlayView.setClickable(false);
        gridOverlayView.setFocusable(false);
        previewContainer.addView(
            gridOverlayView,
            new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        );
        // Set grid mode after adding to container to ensure proper layout
        gridOverlayView.post(() -> {
            String currentGridMode = sessionConfig.getGridMode();
            Log.d(TAG, "setupPreviewView: Setting grid mode to: " + currentGridMode);
            gridOverlayView.setGridMode(currentGridMode);
        });

        // Add a layout listener to update grid bounds when preview view changes size
        previewView.addOnLayoutChangeListener((v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
            if (left != oldLeft || top != oldTop || right != oldRight || bottom != oldBottom) {
                Log.d(TAG, "PreviewView layout changed, updating grid bounds");
                updateGridOverlayBounds();
            }
        });

        ViewGroup parent = (ViewGroup) webView.getParent();
        if (parent != null) {
            FrameLayout.LayoutParams layoutParams = calculatePreviewLayoutParams();
            parent.addView(previewContainer, layoutParams);
            if (sessionConfig.isToBack()) webView.bringToFront();

            // Log the actual position after layout
            previewContainer.post(() -> {
                Log.d(TAG, "========================");
                Log.d(TAG, "ACTUAL CAMERA VIEW POSITION (after layout):");
                Log.d(
                    TAG,
                    "Container position - Left: " +
                        previewContainer.getLeft() +
                        ", Top: " +
                        previewContainer.getTop() +
                        ", Right: " +
                        previewContainer.getRight() +
                        ", Bottom: " +
                        previewContainer.getBottom()
                );
                Log.d(TAG, "Container size - Width: " + previewContainer.getWidth() + ", Height: " + previewContainer.getHeight());

                // Get parent info
                ViewGroup containerParent = (ViewGroup) previewContainer.getParent();
                if (containerParent != null) {
                    Log.d(TAG, "Parent class: " + containerParent.getClass().getSimpleName());
                    Log.d(TAG, "Parent size - Width: " + containerParent.getWidth() + ", Height: " + containerParent.getHeight());
                }
                Log.d(TAG, "========================");
            });
        }
    }

    private FrameLayout.LayoutParams calculatePreviewLayoutParams() {
        // sessionConfig already contains pixel-converted coordinates with webview offsets applied
        int x = sessionConfig.getX();
        int y = sessionConfig.getY();
        int width = sessionConfig.getWidth();
        int height = sessionConfig.getHeight();
        String aspectRatio = sessionConfig.getAspectRatio();

        // Get comprehensive display information
        int screenWidthPx, screenHeightPx;
        float density;

        // Get density using DisplayMetrics (available on all API levels)
        WindowManager windowManager = (WindowManager) this.context.getSystemService(Context.WINDOW_SERVICE);
        DisplayMetrics displayMetrics = new DisplayMetrics();
        windowManager.getDefaultDisplay().getMetrics(displayMetrics);
        density = displayMetrics.density;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+ (Android 11+) - use WindowMetrics for screen dimensions
            WindowMetrics metrics = windowManager.getCurrentWindowMetrics();
            Rect bounds = metrics.getBounds();
            screenWidthPx = bounds.width();
            screenHeightPx = bounds.height();
        } else {
            // API < 30 - use legacy DisplayMetrics for screen dimensions
            screenWidthPx = displayMetrics.widthPixels;
            screenHeightPx = displayMetrics.heightPixels;
        }

        int screenWidthDp = (int) (screenWidthPx / density);
        int screenHeightDp = (int) (screenHeightPx / density);

        // Get WebView dimensions
        int webViewWidth = webView != null ? webView.getWidth() : 0;
        int webViewHeight = webView != null ? webView.getHeight() : 0;

        // Get parent dimensions
        assert webView != null;
        ViewGroup parent = (ViewGroup) webView.getParent();
        int parentWidth = parent != null ? parent.getWidth() : 0;
        int parentHeight = parent != null ? parent.getHeight() : 0;

        Log.d(TAG, "======================== CALCULATE PREVIEW LAYOUT PARAMS ========================");
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
        Log.d(TAG, "WebView dimensions: " + webViewWidth + "x" + webViewHeight);
        Log.d(TAG, "Parent dimensions: " + parentWidth + "x" + parentHeight);
        Log.d(
            TAG,
            "SessionConfig values - x:" +
                x +
                " y:" +
                y +
                " width:" +
                width +
                " height:" +
                height +
                " aspectRatio:" +
                aspectRatio +
                " isCentered:" +
                sessionConfig.isCentered()
        );

        // Apply aspect ratio if specified
        if (aspectRatio != null && !aspectRatio.isEmpty() && sessionConfig.isCentered()) {
            String[] ratios = aspectRatio.split(":");
            if (ratios.length == 2) {
                try {
                    // Match iOS logic exactly
                    double ratioWidth = Double.parseDouble(ratios[0]);
                    double ratioHeight = Double.parseDouble(ratios[1]);
                    boolean isPortrait = context.getResources().getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;

                    Log.d(
                        TAG,
                        "Aspect ratio parsing - Original: " + aspectRatio + " (width=" + ratioWidth + ", height=" + ratioHeight + ")"
                    );
                    Log.d(TAG, "Device orientation: " + (isPortrait ? "PORTRAIT" : "LANDSCAPE"));

                    // iOS: let ratio = !isPortrait ? ratioParts[0] / ratioParts[1] : ratioParts[1] / ratioParts[0]
                    double ratio = !isPortrait ? (ratioWidth / ratioHeight) : (ratioHeight / ratioWidth);

                    Log.d(TAG, "Computed ratio: " + ratio + " (iOS formula: " + (!isPortrait ? "width/height" : "height/width") + ")");

                    // For centered mode with aspect ratio, calculate maximum size that fits

                    Log.d(TAG, "Available space for preview: " + screenWidthPx + "x" + screenHeightPx);

                    // Calculate maximum size that fits the aspect ratio in available space
                    double maxWidthByHeight = screenHeightPx * ratio;
                    double maxHeightByWidth = screenWidthPx / ratio;

                    Log.d(
                        TAG,
                        "Aspect ratio calculations - maxWidthByHeight: " + maxWidthByHeight + ", maxHeightByWidth: " + maxHeightByWidth
                    );

                    if (maxWidthByHeight <= screenWidthPx) {
                        // Height is the limiting factor
                        width = (int) maxWidthByHeight;
                        height = screenHeightPx;
                        Log.d(TAG, "Height-limited sizing: " + width + "x" + height);
                    } else {
                        // Width is the limiting factor
                        width = screenWidthPx;
                        height = (int) maxHeightByWidth;
                        Log.d(TAG, "Width-limited sizing: " + width + "x" + height);
                    }

                    // Center the preview
                    x = (screenWidthPx - width) / 2;
                    y = (screenHeightPx - height) / 2;

                    Log.d(TAG, "Auto-centered position: x=" + x + ", y=" + y);
                } catch (NumberFormatException e) {
                    Log.e(TAG, "Invalid aspect ratio format: " + aspectRatio, e);
                }
            }
        }

        FrameLayout.LayoutParams layoutParams = new FrameLayout.LayoutParams(width, height);

        // The X and Y positions passed from CameraPreview already include webView insets
        // when edge-to-edge is active, so we don't need to add them again here
        layoutParams.leftMargin = x;
        layoutParams.topMargin = y;

        Log.d(
            TAG,
            "Final layout params - Margins: left=" +
                layoutParams.leftMargin +
                ", top=" +
                layoutParams.topMargin +
                ", Size: " +
                width +
                "x" +
                height
        );
        Log.d(TAG, "================================================================================");

        return layoutParams;
    }

    private void removePreviewView() {
        if (previewContainer != null) {
            ViewGroup parent = (ViewGroup) previewContainer.getParent();
            if (parent != null) {
                parent.removeView(previewContainer);
            }
            previewContainer = null;
        }
        if (previewView != null) {
            previewView = null;
        }
        if (gridOverlayView != null) {
            gridOverlayView = null;
        }
        if (focusIndicatorView != null) {
            focusIndicatorView = null;
        }
        webView.setBackgroundColor(android.graphics.Color.WHITE);
    }

    @OptIn(markerClass = ExperimentalCamera2Interop.class)
    private void bindCameraUseCases() {
        if (cameraProvider == null) return;
        mainExecutor.execute(() -> {
            try {
                Log.d(
                    TAG,
                    "Building camera selector with deviceId: " +
                        sessionConfig.getDeviceId() +
                        " and position: " +
                        sessionConfig.getPosition()
                );
                currentCameraSelector = buildCameraSelector();

                ResolutionSelector.Builder resolutionSelectorBuilder = new ResolutionSelector.Builder().setResolutionStrategy(
                    // For face detection, use 720p (1280x720) as optimal balance
                    // Higher resolutions slow down ML Kit processing without improving accuracy
                    new ResolutionStrategy(
                        new Size(1280, 720), // Target 720p
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                    )
                );

                if (sessionConfig.getAspectRatio() != null) {
                    int aspectRatio;
                    if ("16:9".equals(sessionConfig.getAspectRatio())) {
                        aspectRatio = AspectRatio.RATIO_16_9;
                    } else {
                        // "4:3"
                        aspectRatio = AspectRatio.RATIO_4_3;
                    }
                    resolutionSelectorBuilder.setAspectRatioStrategy(
                        new AspectRatioStrategy(aspectRatio, AspectRatioStrategy.FALLBACK_RULE_AUTO)
                    );
                }

                ResolutionSelector resolutionSelector = resolutionSelectorBuilder.build();

                int rotation = previewView != null && previewView.getDisplay() != null
                    ? previewView.getDisplay().getRotation()
                    : android.view.Surface.ROTATION_0;

                // Configure preview with optimized frame rate for face detection (20-25 FPS)
                Preview preview = new Preview.Builder()
                    .setResolutionSelector(resolutionSelector)
                    .setTargetRotation(rotation)
                    .setTargetFrameRate(new Range<>(20, 25)) // 20-25 FPS for balanced performance
                    .build();
                // Keep reference to preview use case for later re-binding (e.g., when enabling video)
                imageCapture = new ImageCapture.Builder()
                    .setResolutionSelector(resolutionSelector)
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setFlashMode(currentFlashMode)
                    .setTargetRotation(rotation)
                    .build();
                sampleImageCapture = imageCapture;

                // Only setup VideoCapture if enableVideoMode is true
                if (sessionConfig.isVideoModeEnabled()) {
                    QualitySelector qualitySelector = QualitySelector.fromOrderedList(
                        Arrays.asList(Quality.FHD, Quality.HD, Quality.SD),
                        FallbackStrategy.higherQualityOrLowerThan(Quality.FHD)
                    );
                    Recorder recorder = new Recorder.Builder().setQualitySelector(qualitySelector).build();
                    videoCapture = VideoCapture.withOutput(recorder);
                }

                // Unbind any existing use cases and bind new ones
                cameraProvider.unbindAll();

                // Re-set the surface provider after unbinding to ensure the preview
                // is connected and video frames are captured correctly
                preview.setSurfaceProvider(previewView.getSurfaceProvider());

                // Bind with or without video capture based on enableVideoMode
                if (sessionConfig.isVideoModeEnabled() && videoCapture != null) {
                    camera = cameraProvider.bindToLifecycle(this, currentCameraSelector, preview, imageCapture, videoCapture);
                } else {
                    camera = cameraProvider.bindToLifecycle(this, currentCameraSelector, preview, imageCapture);
                }

                resetExposureCompensationToDefault();

                // Log details about the active camera
                Log.d(TAG, "Use cases bound. Inspecting active camera and use cases.");
                CameraInfo cameraInfo = camera.getCameraInfo();
                Log.d(TAG, "Bound Camera ID: " + Camera2CameraInfo.from(cameraInfo).getCameraId());

                // Log zoom state
                ZoomState zoomState = cameraInfo.getZoomState().getValue();
                if (zoomState != null) {
                    Log.d(
                        TAG,
                        "Active Zoom State: " +
                            "min=" +
                            zoomState.getMinZoomRatio() +
                            ", " +
                            "max=" +
                            zoomState.getMaxZoomRatio() +
                            ", " +
                            "current=" +
                            zoomState.getZoomRatio()
                    );
                }

                // Log physical cameras of the active camera
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    Set<CameraInfo> physicalCameras = cameraInfo.getPhysicalCameraInfos();
                    Log.d(TAG, "Active camera has " + physicalCameras.size() + " physical cameras.");
                    for (CameraInfo physical : physicalCameras) {
                        Log.d(TAG, "  - Physical camera ID: " + Camera2CameraInfo.from(physical).getCameraId());
                    }
                }

                // Log resolution info
                ResolutionInfo previewResolution = preview.getResolutionInfo();
                if (previewResolution != null) {
                    currentPreviewResolution = previewResolution.getResolution();
                    Log.d(TAG, "Preview resolution: " + currentPreviewResolution);

                    // Log the actual aspect ratio of the selected resolution
                    if (currentPreviewResolution != null) {
                        double actualRatio = (double) currentPreviewResolution.getWidth() / (double) currentPreviewResolution.getHeight();
                        Log.d(
                            TAG,
                            "Actual preview aspect ratio: " +
                                actualRatio +
                                " (width=" +
                                currentPreviewResolution.getWidth() +
                                ", height=" +
                                currentPreviewResolution.getHeight() +
                                ")"
                        );

                        // Compare with requested ratio
                        if ("4:3".equals(sessionConfig.getAspectRatio())) {
                            double expectedRatio = 4.0 / 3.0;
                            double difference = Math.abs(actualRatio - expectedRatio);
                            Log.d(
                                TAG,
                                "4:3 ratio check - Expected: " + expectedRatio + ", Actual: " + actualRatio + ", Difference: " + difference
                            );
                        } else if ("16:9".equals(sessionConfig.getAspectRatio())) {
                            double expectedRatio = 16.0 / 9.0;
                            double difference = Math.abs(actualRatio - expectedRatio);
                            Log.d(
                                TAG,
                                "16:9 ratio check - Expected: " + expectedRatio + ", Actual: " + actualRatio + ", Difference: " + difference
                            );
                        }
                    }
                }
                ResolutionInfo imageCaptureResolution = imageCapture.getResolutionInfo();
                if (imageCaptureResolution != null) {
                    Log.d(TAG, "Image capture resolution: " + imageCaptureResolution.getResolution());
                }

                // Update scale type based on aspect ratio whenever (re)binding
                String ar = sessionConfig != null ? sessionConfig.getAspectRatio() : null;
                previewView.setScaleType(
                    (ar == null || ar.isEmpty()) ? PreviewView.ScaleType.FIT_CENTER : PreviewView.ScaleType.FILL_CENTER
                );

                // Set initial zoom if specified, prioritizing targetZoom over default zoomFactor
                float initialZoom = sessionConfig.getTargetZoom() != 1.0f ? sessionConfig.getTargetZoom() : sessionConfig.getZoomFactor();
                if (initialZoom != 1.0f) {
                    Log.d(TAG, "Applying initial zoom of " + initialZoom);

                    // Validate zoom is within bounds
                    if (zoomState != null) {
                        float minZoom = zoomState.getMinZoomRatio();
                        float maxZoom = zoomState.getMaxZoomRatio();

                        if (initialZoom < minZoom || initialZoom > maxZoom) {
                            if (listener != null) {
                                listener.onCameraStartError(
                                    "Initial zoom level " +
                                        initialZoom +
                                        " is not available. " +
                                        "Valid range is " +
                                        minZoom +
                                        " to " +
                                        maxZoom
                                );
                                return;
                            }
                        }
                    }

                    setZoom(initialZoom);
                }

                isRunning = true;
                Log.d(TAG, "bindCameraUseCases: Camera bound successfully");
                if (listener != null) {
                    // Post the callback to ensure layout is complete
                    previewContainer.post(() -> {
                        // Return actual preview container dimensions instead of requested dimensions
                        // Get the actual camera dimensions and position
                        int actualWidth = getPreviewWidth();
                        int actualHeight = getPreviewHeight();
                        int actualX = getPreviewX();
                        int actualY = getPreviewY();

                        Log.d(
                            TAG,
                            "onCameraStarted callback - actualX=" +
                                actualX +
                                ", actualY=" +
                                actualY +
                                ", actualWidth=" +
                                actualWidth +
                                ", actualHeight=" +
                                actualHeight
                        );

                        // Update grid overlay bounds after camera is started
                        updateGridOverlayBounds();

                        listener.onCameraStarted(actualWidth, actualHeight, actualX, actualY);
                    });
                }
            } catch (Exception e) {
                if (listener != null) listener.onCameraStartError("Error binding camera: " + e.getMessage());
            }
        });
    }

    @OptIn(markerClass = ExperimentalCamera2Interop.class)
    private CameraSelector buildCameraSelector() {
        CameraSelector.Builder builder = new CameraSelector.Builder();
        final String deviceId = sessionConfig.getDeviceId();

        if (deviceId != null && !deviceId.isEmpty()) {
            builder.addCameraFilter((cameraInfos) -> {
                for (CameraInfo cameraInfo : cameraInfos) {
                    if (deviceId.equals(Camera2CameraInfo.from(cameraInfo).getCameraId())) {
                        return Collections.singletonList(cameraInfo);
                    }
                }
                return Collections.emptyList();
            });
        } else {
            String position = sessionConfig.getPosition();
            int requiredFacing = "front".equals(position) ? CameraSelector.LENS_FACING_FRONT : CameraSelector.LENS_FACING_BACK;
            builder.requireLensFacing(requiredFacing);
        }
        return builder.build();
    }

    private static boolean isBackCamera(androidx.camera.core.CameraInfo cameraInfo) {
        try {
            // Check if this camera matches the back camera selector
            CameraSelector backSelector = new CameraSelector.Builder().requireLensFacing(CameraSelector.LENS_FACING_BACK).build();

            // Try to filter cameras with back selector - if this camera is included, it's a back camera
            List<androidx.camera.core.CameraInfo> backCameras = backSelector.filter(Collections.singletonList(cameraInfo));
            return !backCameras.isEmpty();
        } catch (Exception e) {
            Log.w(TAG, "Error determining camera direction, assuming back camera", e);
            return true; // Default to back camera
        }
    }

    public void capturePhoto(
        int quality,
        final boolean saveToGallery,
        Integer width,
        Integer height,
        Location location,
        final boolean embedTimestamp,
        final boolean embedLocation
    ) {
        if (imageCapture == null) {
            if (listener != null) {
                listener.onPictureTakenError("Camera not ready");
            }
            return;
        }

        // Prevent capture if a stop is pending
        if (IsOperationRunning("capturePhoto")) {
            Log.d(TAG, "capturePhoto: Ignored because stop is pending");
            return;
        }

        Log.d(
            TAG,
            "capturePhoto: Starting photo capture with: " +
                quality +
                ", width: " +
                width +
                ", height: " +
                height +
                ", saveToGallery: " +
                saveToGallery +
                ", embedTimestamp: " +
                embedTimestamp +
                ", embedLocation: " +
                embedLocation
        );

        boolean dispatched = false;
        try {
            synchronized (captureLock) {
                isCapturingPhoto = true;
            }

            final ByteArrayOutputStream imageStream = new ByteArrayOutputStream();
            ImageCapture.Metadata metadata = new ImageCapture.Metadata();
            if (location != null) {
                metadata.setLocation(location);
            }
            ImageCapture.OutputFileOptions outputFileOptions = new ImageCapture.OutputFileOptions.Builder(imageStream)
                .setMetadata(metadata)
                .build();

            imageCapture.takePicture(
                outputFileOptions,
                cameraExecutor,
                new ImageCapture.OnImageSavedCallback() {
                    @Override
                    public void onError(@NonNull ImageCaptureException exception) {
                        Log.e(TAG, "capturePhoto: Photo capture failed", exception);
                        if (listener != null) {
                            listener.onPictureTakenError("Photo capture failed: " + exception.getMessage());
                        }
                        // End of capture lifecycle
                        synchronized (captureLock) {
                            isCapturingPhoto = false;
                            if (stopRequested) {
                                performImmediateStop();
                            }
                        }
                        endOperation("capturePhoto");
                    }

                    @Override
                    public void onImageSaved(@NonNull ImageCapture.OutputFileResults output) {
                        try {
                            byte[] originalCaptureBytes = imageStream.toByteArray();
                            byte[] bytes = originalCaptureBytes; // will be replaced if we transform
                            int finalWidthOut = -1;
                            int finalHeightOut = -1;
                            boolean transformedPixels = false;

                            ExifInterface exifInterface = new ExifInterface(new ByteArrayInputStream(originalCaptureBytes));
                            // Build EXIF JSON from captured bytes (location applied by metadata if provided)
                            JSONObject exifData = getExifData(exifInterface);

                            if (width != null || height != null) {
                                Bitmap bitmap = BitmapFactory.decodeByteArray(originalCaptureBytes, 0, originalCaptureBytes.length);
                                bitmap = applyExifOrientation(bitmap, exifInterface);
                                Bitmap resizedBitmap = resizeBitmapToMaxDimensions(bitmap, width, height);
                                if (embedTimestamp || embedLocation) {
                                    resizedBitmap = drawTimestampAndLocationOntoBitmap(
                                        resizedBitmap,
                                        exifInterface,
                                        embedTimestamp,
                                        embedLocation
                                    );
                                }
                                ByteArrayOutputStream stream = new ByteArrayOutputStream();
                                resizedBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream);
                                bytes = stream.toByteArray();
                                transformedPixels = true;

                                // Update EXIF JSON to reflect new dimensions; no in-place EXIF write to bytes
                                try {
                                    exifData.put("PixelXDimension", resizedBitmap.getWidth());
                                    exifData.put("PixelYDimension", resizedBitmap.getHeight());
                                    exifData.put("ImageWidth", resizedBitmap.getWidth());
                                    exifData.put("ImageLength", resizedBitmap.getHeight());
                                    exifData.put("Orientation", Integer.toString(ExifInterface.ORIENTATION_NORMAL));
                                } catch (Exception ignore) {}
                                finalWidthOut = resizedBitmap.getWidth();
                                finalHeightOut = resizedBitmap.getHeight();
                            } else {
                                // No explicit size/ratio: crop to match current preview content
                                Bitmap originalBitmap = BitmapFactory.decodeByteArray(originalCaptureBytes, 0, originalCaptureBytes.length);
                                originalBitmap = applyExifOrientation(originalBitmap, exifInterface);
                                Bitmap previewCropped = cropBitmapToMatchPreview(originalBitmap);
                                if (embedTimestamp || embedLocation) {
                                    previewCropped = drawTimestampAndLocationOntoBitmap(
                                        previewCropped,
                                        exifInterface,
                                        embedTimestamp,
                                        embedLocation
                                    );
                                }
                                ByteArrayOutputStream stream = new ByteArrayOutputStream();
                                previewCropped.compress(Bitmap.CompressFormat.JPEG, quality, stream);
                                bytes = stream.toByteArray();
                                transformedPixels = true;
                                // Update EXIF JSON to reflect cropped dimensions; no in-place EXIF write to bytes
                                try {
                                    exifData.put("PixelXDimension", previewCropped.getWidth());
                                    exifData.put("PixelYDimension", previewCropped.getHeight());
                                    exifData.put("ImageWidth", previewCropped.getWidth());
                                    exifData.put("ImageLength", previewCropped.getHeight());
                                    exifData.put("Orientation", Integer.toString(ExifInterface.ORIENTATION_NORMAL));
                                } catch (Exception ignore) {}
                                finalWidthOut = previewCropped.getWidth();
                                finalHeightOut = previewCropped.getHeight();
                            }

                            // After any transform, inject EXIF back into the in-memory JPEG bytes (no temp file)
                            if (transformedPixels) {
                                Integer fW = (finalWidthOut > 0) ? finalWidthOut : null;
                                Integer fH = (finalHeightOut > 0) ? finalHeightOut : null;
                                bytes = injectExifInMemory(bytes, originalCaptureBytes, fW, fH);
                            }

                            // Save to gallery asynchronously if requested, copy EXIF to file
                            if (saveToGallery) {
                                final byte[] finalBytes = bytes;
                                final ExifInterface exifForFile = exifInterface;
                                final Integer fW = (finalWidthOut > 0) ? finalWidthOut : null;
                                final Integer fH = (finalHeightOut > 0) ? finalHeightOut : null;
                                new Thread(() -> saveImageToGallery(finalBytes, exifForFile, fW, fH)).start();
                            }

                            String resultValue;
                            boolean returnFileUri = sessionConfig != null && sessionConfig.isStoreToFile();
                            if (returnFileUri) {
                                // Persist processed image to a file and return its URI to avoid heavy base64 bridging
                                try {
                                    String fileName =
                                        "cpcp_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new java.util.Date()) + ".jpg";
                                    File outDir = context.getCacheDir();
                                    File outFile = new File(outDir, fileName);
                                    FileOutputStream outFos = new FileOutputStream(outFile);
                                    outFos.write(bytes);
                                    outFos.close();

                                    // No EXIF rewrite here; bytes already contain EXIF when needed

                                    // Return a file path; apps can convert via Capacitor.convertFileSrc on JS side
                                    resultValue = outFile.getAbsolutePath();
                                } catch (IOException ioEx) {
                                    Log.e(TAG, "capturePhoto: Failed to write image file", ioEx);
                                    // Fallback to base64 if file write fails
                                    resultValue = Base64.encodeToString(bytes, Base64.NO_WRAP);
                                }
                            } else {
                                // Backward-compatible behavior
                                resultValue = Base64.encodeToString(bytes, Base64.NO_WRAP);
                            }

                            if (listener != null) {
                                listener.onPictureTaken(resultValue, exifData);
                            }
                        } catch (Exception e) {
                            Log.e(TAG, "capturePhoto: Error processing image", e);
                            if (listener != null) {
                                listener.onPictureTakenError("Error processing image: " + e.getMessage());
                            }
                        } finally {
                            // End of capture lifecycle
                            synchronized (captureLock) {
                                isCapturingPhoto = false;
                                if (stopRequested) {
                                    performImmediateStop();
                                }
                            }
                            endOperation("capturePhoto");
                        }
                    }
                }
            );

            dispatched = true;
        } catch (Exception e) {
            Log.e(TAG, "capturePhoto: Failed to start photo capture", e);
            if (listener != null) {
                listener.onPictureTakenError("Photo capture failed: " + e.getMessage());
            }
        } finally {
            if (!dispatched) {
                synchronized (captureLock) {
                    isCapturingPhoto = false;
                    if (stopRequested) {
                        performImmediateStop();
                    }
                }
                endOperation("capturePhoto");
            }
        }
    }

    private Bitmap drawTimestampAndLocationOntoBitmap(Bitmap src, ExifInterface exif, boolean embedTimestamp, boolean embedLocation) {
        if (src == null) return null;

        // Build strings (null-safe)
        final String when = embedTimestamp ? buildTimestampStringFromExif(exif) : null;
        final String where = (embedLocation ? buildLocationStringFromExif(exif) : null);

        // Nothing to draw?
        if ((when == null || when.isEmpty()) && (where == null || where.isEmpty())) {
            Log.d(TAG, "capturePhoto:... embedTimestamp: " + embedTimestamp + ", embedLocation: " + embedLocation);
            Log.d(TAG, "capturePhoto: nothing to draw");
            return src;
        }

        final Bitmap bmp = src.isMutable() ? src : src.copy(Bitmap.Config.ARGB_8888, true);
        final Canvas canvas = new Canvas(bmp);

        // ---- Visual constants (match timestamp style) ----
        final float fontPx = Math.max(10f, bmp.getWidth() * 0.035f); // ~3.5% of width
        final float paddingH = 16f; // horizontal inner padding
        final float paddingV = 10f; // vertical inner padding
        final float margin = 12f; // margin from image edges
        final float gap = 8f; // vertical gap between stacked pills
        final float corner = 10f; // corner radius
        final int bgColor = Color.argb(56, 31, 31, 31); // ~iOS gray at ~22% alpha

        // Text paint
        final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG | Paint.LINEAR_TEXT_FLAG);
        text.setColor(Color.WHITE);
        text.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        text.setTextSize(fontPx);
        text.setTextAlign(Paint.Align.LEFT);
        text.setDither(true);
        text.setFilterBitmap(true);
        text.setHinting(Paint.HINTING_ON);
        final Paint.FontMetrics fm = text.getFontMetrics();
        final float lineHeight = fm.descent - fm.ascent;

        // Background paint
        final Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG);
        bg.setColor(bgColor);
        bg.setStyle(Paint.Style.FILL);
        bg.setShadowLayer(6f, 0f, 2f, Color.argb(64, 0, 0, 0));

        float nextTop = margin;

        // Helper to draw a pill aligned to the top-right, returns the bottom Y used
        java.util.function.BiFunction<String, Float, Float> drawPill = (label, top) -> {
            if (label == null || label.isEmpty()) return top;
            float textW = text.measureText(label);
            float bgW = textW + paddingH * 2f;
            float bgH = lineHeight + paddingV * 2f;

            float left = Math.max(0, bmp.getWidth() - bgW - margin);
            float right = left + bgW;
            float bottom = top + bgH;

            // Background
            canvas.drawRoundRect(left, top, right, bottom, corner, corner, bg);

            // Text baseline
            float textX = left + paddingH;
            float textY = top + paddingV - fm.ascent; // convert top-left to baseline
            canvas.drawText(label, textX, textY, text);

            return bottom;
        };

        // 1) Timestamp (if any)
        if (when != null && !when.isEmpty()) {
            nextTop = drawPill.apply(when, nextTop);
            // add gap below
            nextTop += gap;
        }

        // 2) Location (if any)
        if (where != null && !where.isEmpty()) {
            // If there was no timestamp drawn, we still start at top margin.
            // If there was, we use the accumulated nextTop (= bottom + gap).
            drawPill.apply(where, (when != null && !when.isEmpty()) ? nextTop : margin);
        }

        return bmp;
    }

    /** Build "yyyy-MM-dd HH:mm:ss" from EXIF, fallback to now. */
    private String buildTimestampStringFromExif(ExifInterface exif) {
        final String out = "yyyy-MM-dd HH:mm:ss";
        try {
            if (exif != null) {
                String exifDate = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL);
                if (exifDate == null || exifDate.trim().isEmpty()) {
                    exifDate = exif.getAttribute(ExifInterface.TAG_DATETIME);
                }
                if (exifDate != null && !exifDate.trim().isEmpty()) {
                    java.text.SimpleDateFormat in = new java.text.SimpleDateFormat("yyyy:MM:dd HH:mm:ss", java.util.Locale.US);
                    java.util.Date d = in.parse(exifDate);
                    if (d != null) {
                        return new java.text.SimpleDateFormat(out, java.util.Locale.getDefault()).format(d);
                    }
                }
            }
        } catch (Throwable ignored) {}
        // Fallback to "now" if EXIF missing/invalid
        return new java.text.SimpleDateFormat(out, java.util.Locale.getDefault()).format(new java.util.Date());
    }

    /** Build "lat, lon" from EXIF GPS. Returns null if absent (so caller can skip). */
    private String buildLocationStringFromExif(ExifInterface exif) {
        if (exif == null) return null;
        try {
            float[] latLong = new float[2];
            if (exif.getLatLong(latLong)) {
                // Keep a compact but readable precision (5 decimals ≈ ~1 m–10 m)
                String lat = String.format(java.util.Locale.US, "%.5f", latLong[0]);
                String lon = String.format(java.util.Locale.US, "%.5f", latLong[1]);
                return lat + ", " + lon;
            }
        } catch (Throwable ignored) {}
        return null; // No EXIF GPS → skip
    }

    private int exifToDegrees(int exifOrientation) {
        switch (exifOrientation) {
            case ExifInterface.ORIENTATION_ROTATE_90:
            case ExifInterface.ORIENTATION_TRANSPOSE:
                return 90;
            case ExifInterface.ORIENTATION_ROTATE_180:
                return 180;
            case ExifInterface.ORIENTATION_ROTATE_270:
            case ExifInterface.ORIENTATION_TRANSVERSE:
                return 270;
            default:
                return 0;
        }
    }

    private Bitmap applyExifOrientation(Bitmap bitmap, ExifInterface exif) {
        try {
            int orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED);
            int rotation = exifToDegrees(orientation);
            if (rotation == 0) return bitmap;
            Matrix m = new Matrix();
            m.postRotate(rotation);
            Bitmap rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), m, true);
            if (rotated != bitmap) {
                try {
                    bitmap.recycle();
                } catch (Exception ignore) {}
            }
            return rotated;
        } catch (Exception e) {
            return bitmap;
        }
    }

    private Bitmap resizeBitmapToMaxDimensions(Bitmap bitmap, Integer maxWidth, Integer maxHeight) {
        int originalWidth = bitmap.getWidth();
        int originalHeight = bitmap.getHeight();
        float originalAspectRatio = (float) originalWidth / originalHeight;

        int targetWidth;
        int targetHeight = originalHeight;

        if (maxWidth != null && maxHeight != null) {
            // Both dimensions specified - fit within both maximums
            float maxAspectRatio = (float) maxWidth / maxHeight;
            if (originalAspectRatio > maxAspectRatio) {
                // Original is wider - fit by width
                targetWidth = maxWidth;
                targetHeight = (int) (maxWidth / originalAspectRatio);
            } else {
                // Original is taller - fit by height
                targetWidth = (int) (maxHeight * originalAspectRatio);
                targetHeight = maxHeight;
            }
        } else if (maxWidth != null) {
            // Only width specified - maintain aspect ratio
            targetWidth = maxWidth;
            targetHeight = (int) (maxWidth / originalAspectRatio);
        } else {
            // Only height specified - maintain aspect ratio
            targetWidth = (int) (maxHeight * originalAspectRatio);
            targetHeight = maxHeight;
        }

        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true);
    }

    private JSONObject getExifData(ExifInterface exifInterface) {
        JSONObject exifData = new JSONObject();
        try {
            // Add all available exif tags to a JSON object
            for (String[] tag : EXIF_TAGS) {
                String value = exifInterface.getAttribute(tag[0]);
                if (value != null) {
                    exifData.put(tag[1], value);
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "getExifData: Error reading exif data", e);
        }
        return exifData;
    }

    // Inject EXIF into a JPEG byte[] fully in-memory using Apache Commons Imaging (no temp files)
    // Copies EXIF from sourceJpeg (original capture) and updates orientation/dimensions if provided.
    private byte[] injectExifInMemory(byte[] targetJpeg, byte[] sourceJpegWithExif, Integer finalWidth, Integer finalHeight) {
        try {
            // Quick signature check for JPEG (FF D8 FF)
            if (
                targetJpeg == null ||
                targetJpeg.length < 3 ||
                (targetJpeg[0] & 0xFF) != 0xFF ||
                (targetJpeg[1] & 0xFF) != 0xD8 ||
                (targetJpeg[2] & 0xFF) != 0xFF
            ) {
                return targetJpeg; // Not a JPEG; nothing to do
            }

            // Use Commons Imaging to read EXIF from the original capture bytes
            org.apache.commons.imaging.formats.jpeg.JpegImageMetadata jpegMetadata =
                (org.apache.commons.imaging.formats.jpeg.JpegImageMetadata) org.apache.commons.imaging.Imaging.getMetadata(
                    sourceJpegWithExif
                );
            org.apache.commons.imaging.formats.tiff.TiffImageMetadata exif = jpegMetadata != null ? jpegMetadata.getExif() : null;

            org.apache.commons.imaging.formats.tiff.write.TiffOutputSet outputSet = exif != null
                ? exif.getOutputSet()
                : new org.apache.commons.imaging.formats.tiff.write.TiffOutputSet();

            // Update orientation if requested (normalize to 1)
            org.apache.commons.imaging.formats.tiff.write.TiffOutputDirectory rootDir = outputSet.getOrCreateRootDirectory();
            rootDir.removeField(org.apache.commons.imaging.formats.tiff.constants.TiffTagConstants.TIFF_TAG_ORIENTATION);
            rootDir.add(org.apache.commons.imaging.formats.tiff.constants.TiffTagConstants.TIFF_TAG_ORIENTATION, (short) 1);

            if (finalWidth != null || finalHeight != null) {
                try {
                    updateResizedDimensions(outputSet, finalWidth, finalHeight);
                } catch (Exception dimensionUpdateError) {
                    Log.w(TAG, "injectExifInMemory: Failed to update resized dimensions", dimensionUpdateError);
                }
            }

            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            new org.apache.commons.imaging.formats.jpeg.exif.ExifRewriter().updateExifMetadataLossless(
                new java.io.ByteArrayInputStream(targetJpeg),
                out,
                outputSet
            );
            return out.toByteArray();
        } catch (Throwable t) {
            Log.w(TAG, "injectExifInMemory: Failed to write EXIF in memory", t);
            return targetJpeg; // Fallback: return original bytes
        }
    }

    private void updateResizedDimensions(
        org.apache.commons.imaging.formats.tiff.write.TiffOutputSet outputSet,
        Integer finalWidth,
        Integer finalHeight
    ) throws org.apache.commons.imaging.ImagingException {
        org.apache.commons.imaging.formats.tiff.write.TiffOutputDirectory rootDir = outputSet.getOrCreateRootDirectory();
        if (finalWidth != null) {
            replaceShortOrLongTag(
                rootDir,
                org.apache.commons.imaging.formats.tiff.constants.TiffTagConstants.TIFF_TAG_IMAGE_WIDTH,
                finalWidth
            );
        }
        if (finalHeight != null) {
            replaceShortOrLongTag(
                rootDir,
                org.apache.commons.imaging.formats.tiff.constants.TiffTagConstants.TIFF_TAG_IMAGE_LENGTH,
                finalHeight
            );
        }

        org.apache.commons.imaging.formats.tiff.write.TiffOutputDirectory exifDir = outputSet.getOrCreateExifDirectory();
        if (finalWidth != null) {
            replaceShortTag(
                exifDir,
                org.apache.commons.imaging.formats.tiff.constants.ExifTagConstants.EXIF_TAG_EXIF_IMAGE_WIDTH,
                finalWidth
            );
        }
        if (finalHeight != null) {
            replaceShortTag(
                exifDir,
                org.apache.commons.imaging.formats.tiff.constants.ExifTagConstants.EXIF_TAG_EXIF_IMAGE_LENGTH,
                finalHeight
            );
        }
    }

    private void replaceShortOrLongTag(
        org.apache.commons.imaging.formats.tiff.write.TiffOutputDirectory directory,
        org.apache.commons.imaging.formats.tiff.taginfos.TagInfoShortOrLong tagInfo,
        int value
    ) throws org.apache.commons.imaging.ImagingException {
        directory.removeField(tagInfo);
        directory.add(tagInfo, value);
    }

    private void replaceShortTag(
        org.apache.commons.imaging.formats.tiff.write.TiffOutputDirectory directory,
        org.apache.commons.imaging.formats.tiff.taginfos.TagInfoShort tagInfo,
        int value
    ) throws org.apache.commons.imaging.ImagingException {
        int sanitizedValue = Math.max(0, Math.min(value, 0xFFFF));
        directory.removeField(tagInfo);
        directory.add(tagInfo, (short) sanitizedValue);
    }

    private static final String[][] EXIF_TAGS = new String[][] {
        { ExifInterface.TAG_APERTURE_VALUE, "ApertureValue" },
        { ExifInterface.TAG_ARTIST, "Artist" },
        { ExifInterface.TAG_BITS_PER_SAMPLE, "BitsPerSample" },
        { ExifInterface.TAG_BRIGHTNESS_VALUE, "BrightnessValue" },
        { ExifInterface.TAG_CFA_PATTERN, "CFAPattern" },
        { ExifInterface.TAG_COLOR_SPACE, "ColorSpace" },
        { ExifInterface.TAG_COMPONENTS_CONFIGURATION, "ComponentsConfiguration" },
        { ExifInterface.TAG_COMPRESSED_BITS_PER_PIXEL, "CompressedBitsPerPixel" },
        { ExifInterface.TAG_COMPRESSION, "Compression" },
        { ExifInterface.TAG_CONTRAST, "Contrast" },
        { ExifInterface.TAG_COPYRIGHT, "Copyright" },
        { ExifInterface.TAG_CUSTOM_RENDERED, "CustomRendered" },
        { ExifInterface.TAG_DATETIME, "DateTime" },
        { ExifInterface.TAG_DATETIME_DIGITIZED, "DateTimeDigitized" },
        { ExifInterface.TAG_DATETIME_ORIGINAL, "DateTimeOriginal" },
        { ExifInterface.TAG_DEVICE_SETTING_DESCRIPTION, "DeviceSettingDescription" },
        { ExifInterface.TAG_DIGITAL_ZOOM_RATIO, "DigitalZoomRatio" },
        { ExifInterface.TAG_DNG_VERSION, "DNGVersion" },
        { ExifInterface.TAG_EXIF_VERSION, "ExifVersion" },
        { ExifInterface.TAG_EXPOSURE_BIAS_VALUE, "ExposureBiasValue" },
        { ExifInterface.TAG_EXPOSURE_INDEX, "ExposureIndex" },
        { ExifInterface.TAG_EXPOSURE_MODE, "ExposureMode" },
        { ExifInterface.TAG_EXPOSURE_PROGRAM, "ExposureProgram" },
        { ExifInterface.TAG_EXPOSURE_TIME, "ExposureTime" },
        { ExifInterface.TAG_FILE_SOURCE, "FileSource" },
        { ExifInterface.TAG_FLASH, "Flash" },
        { ExifInterface.TAG_FLASHPIX_VERSION, "FlashpixVersion" },
        { ExifInterface.TAG_FLASH_ENERGY, "FlashEnergy" },
        { ExifInterface.TAG_FOCAL_LENGTH, "FocalLength" },
        { ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM, "FocalLengthIn35mmFilm" },
        { ExifInterface.TAG_FOCAL_PLANE_RESOLUTION_UNIT, "FocalPlaneResolutionUnit" },
        { ExifInterface.TAG_FOCAL_PLANE_X_RESOLUTION, "FocalPlaneXResolution" },
        { ExifInterface.TAG_FOCAL_PLANE_Y_RESOLUTION, "FocalPlaneYResolution" },
        { ExifInterface.TAG_F_NUMBER, "FNumber" },
        { ExifInterface.TAG_GAIN_CONTROL, "GainControl" },
        { ExifInterface.TAG_GPS_ALTITUDE, "GPSAltitude" },
        { ExifInterface.TAG_GPS_ALTITUDE_REF, "GPSAltitudeRef" },
        { ExifInterface.TAG_GPS_AREA_INFORMATION, "GPSAreaInformation" },
        { ExifInterface.TAG_GPS_DATESTAMP, "GPSDateStamp" },
        { ExifInterface.TAG_GPS_DEST_BEARING, "GPSDestBearing" },
        { ExifInterface.TAG_GPS_DEST_BEARING_REF, "GPSDestBearingRef" },
        { ExifInterface.TAG_GPS_DEST_DISTANCE, "GPSDestDistance" },
        { ExifInterface.TAG_GPS_DEST_DISTANCE_REF, "GPSDestDistanceRef" },
        { ExifInterface.TAG_GPS_DEST_LATITUDE, "GPSDestLatitude" },
        { ExifInterface.TAG_GPS_DEST_LATITUDE_REF, "GPSDestLatitudeRef" },
        { ExifInterface.TAG_GPS_DEST_LONGITUDE, "GPSDestLongitude" },
        { ExifInterface.TAG_GPS_DEST_LONGITUDE_REF, "GPSDestLongitudeRef" },
        { ExifInterface.TAG_GPS_DIFFERENTIAL, "GPSDifferential" },
        { ExifInterface.TAG_GPS_DOP, "GPSDOP" },
        { ExifInterface.TAG_GPS_IMG_DIRECTION, "GPSImgDirection" },
        { ExifInterface.TAG_GPS_IMG_DIRECTION_REF, "GPSImgDirectionRef" },
        { ExifInterface.TAG_GPS_LATITUDE, "GPSLatitude" },
        { ExifInterface.TAG_GPS_LATITUDE_REF, "GPSLatitudeRef" },
        { ExifInterface.TAG_GPS_LONGITUDE, "GPSLongitude" },
        { ExifInterface.TAG_GPS_LONGITUDE_REF, "GPSLongitudeRef" },
        { ExifInterface.TAG_GPS_MAP_DATUM, "GPSMapDatum" },
        { ExifInterface.TAG_GPS_MEASURE_MODE, "GPSMeasureMode" },
        { ExifInterface.TAG_GPS_PROCESSING_METHOD, "GPSProcessingMethod" },
        { ExifInterface.TAG_GPS_SATELLITES, "GPSSatellites" },
        { ExifInterface.TAG_GPS_SPEED, "GPSSpeed" },
        { ExifInterface.TAG_GPS_SPEED_REF, "GPSSpeedRef" },
        { ExifInterface.TAG_GPS_STATUS, "GPSStatus" },
        { ExifInterface.TAG_GPS_TIMESTAMP, "GPSTimeStamp" },
        { ExifInterface.TAG_GPS_TRACK, "GPSTrack" },
        { ExifInterface.TAG_GPS_TRACK_REF, "GPSTrackRef" },
        { ExifInterface.TAG_GPS_VERSION_ID, "GPSVersionID" },
        { ExifInterface.TAG_IMAGE_DESCRIPTION, "ImageDescription" },
        { ExifInterface.TAG_IMAGE_LENGTH, "ImageLength" },
        { ExifInterface.TAG_IMAGE_UNIQUE_ID, "ImageUniqueID" },
        { ExifInterface.TAG_IMAGE_WIDTH, "ImageWidth" },
        { ExifInterface.TAG_INTEROPERABILITY_INDEX, "InteroperabilityIndex" },
        { ExifInterface.TAG_ISO_SPEED, "ISOSpeed" },
        { ExifInterface.TAG_ISO_SPEED_LATITUDE_YYY, "ISOSpeedLatitudeyyy" },
        { ExifInterface.TAG_ISO_SPEED_LATITUDE_ZZZ, "ISOSpeedLatitudezzz" },
        { ExifInterface.TAG_JPEG_INTERCHANGE_FORMAT, "JPEGInterchangeFormat" },
        { ExifInterface.TAG_JPEG_INTERCHANGE_FORMAT_LENGTH, "JPEGInterchangeFormatLength" },
        { ExifInterface.TAG_LIGHT_SOURCE, "LightSource" },
        { ExifInterface.TAG_MAKE, "Make" },
        { ExifInterface.TAG_MAKER_NOTE, "MakerNote" },
        { ExifInterface.TAG_MAX_APERTURE_VALUE, "MaxApertureValue" },
        { ExifInterface.TAG_METERING_MODE, "MeteringMode" },
        { ExifInterface.TAG_MODEL, "Model" },
        { ExifInterface.TAG_NEW_SUBFILE_TYPE, "NewSubfileType" },
        { ExifInterface.TAG_OECF, "OECF" },
        { ExifInterface.TAG_OFFSET_TIME, "OffsetTime" },
        { ExifInterface.TAG_OFFSET_TIME_DIGITIZED, "OffsetTimeDigitized" },
        { ExifInterface.TAG_OFFSET_TIME_ORIGINAL, "OffsetTimeOriginal" },
        { ExifInterface.TAG_ORF_ASPECT_FRAME, "ORFAspectFrame" },
        { ExifInterface.TAG_ORF_PREVIEW_IMAGE_LENGTH, "ORFPreviewImageLength" },
        { ExifInterface.TAG_ORF_PREVIEW_IMAGE_START, "ORFPreviewImageStart" },
        { ExifInterface.TAG_ORF_THUMBNAIL_IMAGE, "ORFThumbnailImage" },
        { ExifInterface.TAG_ORIENTATION, "Orientation" },
        { ExifInterface.TAG_PHOTOMETRIC_INTERPRETATION, "PhotometricInterpretation" },
        { ExifInterface.TAG_PIXEL_X_DIMENSION, "PixelXDimension" },
        { ExifInterface.TAG_PIXEL_Y_DIMENSION, "PixelYDimension" },
        { ExifInterface.TAG_PLANAR_CONFIGURATION, "PlanarConfiguration" },
        { ExifInterface.TAG_PRIMARY_CHROMATICITIES, "PrimaryChromaticities" },
        { ExifInterface.TAG_RECOMMENDED_EXPOSURE_INDEX, "RecommendedExposureIndex" },
        { ExifInterface.TAG_REFERENCE_BLACK_WHITE, "ReferenceBlackWhite" },
        { ExifInterface.TAG_RELATED_SOUND_FILE, "RelatedSoundFile" },
        { ExifInterface.TAG_RESOLUTION_UNIT, "ResolutionUnit" },
        { ExifInterface.TAG_ROWS_PER_STRIP, "RowsPerStrip" },
        { ExifInterface.TAG_RW2_ISO, "RW2ISO" },
        { ExifInterface.TAG_RW2_JPG_FROM_RAW, "RW2JpgFromRaw" },
        { ExifInterface.TAG_RW2_SENSOR_BOTTOM_BORDER, "RW2SensorBottomBorder" },
        { ExifInterface.TAG_RW2_SENSOR_LEFT_BORDER, "RW2SensorLeftBorder" },
        { ExifInterface.TAG_RW2_SENSOR_RIGHT_BORDER, "RW2SensorRightBorder" },
        { ExifInterface.TAG_RW2_SENSOR_TOP_BORDER, "RW2SensorTopBorder" },
        { ExifInterface.TAG_SAMPLES_PER_PIXEL, "SamplesPerPixel" },
        { ExifInterface.TAG_SATURATION, "Saturation" },
        { ExifInterface.TAG_SCENE_CAPTURE_TYPE, "SceneCaptureType" },
        { ExifInterface.TAG_SCENE_TYPE, "SceneType" },
        { ExifInterface.TAG_SENSING_METHOD, "SensingMethod" },
        { ExifInterface.TAG_SENSITIVITY_TYPE, "SensitivityType" },
        { ExifInterface.TAG_SHARPNESS, "Sharpness" },
        { ExifInterface.TAG_SHUTTER_SPEED_VALUE, "ShutterSpeedValue" },
        { ExifInterface.TAG_SOFTWARE, "Software" },
        { ExifInterface.TAG_SPATIAL_FREQUENCY_RESPONSE, "SpatialFrequencyResponse" },
        { ExifInterface.TAG_SPECTRAL_SENSITIVITY, "SpectralSensitivity" },
        { ExifInterface.TAG_STANDARD_OUTPUT_SENSITIVITY, "StandardOutputSensitivity" },
        { ExifInterface.TAG_STRIP_BYTE_COUNTS, "StripByteCounts" },
        { ExifInterface.TAG_STRIP_OFFSETS, "StripOffsets" },
        { ExifInterface.TAG_SUBFILE_TYPE, "SubfileType" },
        { ExifInterface.TAG_SUBJECT_AREA, "SubjectArea" },
        { ExifInterface.TAG_SUBJECT_DISTANCE, "SubjectDistance" },
        { ExifInterface.TAG_SUBJECT_DISTANCE_RANGE, "SubjectDistanceRange" },
        { ExifInterface.TAG_SUBJECT_LOCATION, "SubjectLocation" },
        { ExifInterface.TAG_SUBSEC_TIME, "SubSecTime" },
        { ExifInterface.TAG_SUBSEC_TIME_DIGITIZED, "SubSecTimeDigitized" },
        { ExifInterface.TAG_SUBSEC_TIME_ORIGINAL, "SubSecTimeOriginal" },
        { ExifInterface.TAG_THUMBNAIL_IMAGE_LENGTH, "ThumbnailImageLength" },
        { ExifInterface.TAG_THUMBNAIL_IMAGE_WIDTH, "ThumbnailImageWidth" },
        { ExifInterface.TAG_TRANSFER_FUNCTION, "TransferFunction" },
        { ExifInterface.TAG_USER_COMMENT, "UserComment" },
        { ExifInterface.TAG_WHITE_BALANCE, "WhiteBalance" },
        { ExifInterface.TAG_WHITE_POINT, "WhitePoint" },
        { ExifInterface.TAG_X_RESOLUTION, "XResolution" },
        { ExifInterface.TAG_Y_CB_CR_COEFFICIENTS, "YCbCrCoefficients" },
        { ExifInterface.TAG_Y_CB_CR_POSITIONING, "YCbCrPositioning" },
        { ExifInterface.TAG_Y_CB_CR_SUB_SAMPLING, "YCbCrSubSampling" },
        { ExifInterface.TAG_Y_RESOLUTION, "YResolution" }
    };

    // Note: We avoid temporary files for EXIF writes. When we transform pixels (resize/crop),
    // we recompress JPEG in-memory and update EXIF info only in the returned JSON, not in the bytes.

    public void captureSample(int quality) {
        if (sampleImageCapture == null) {
            if (listener != null) {
                listener.onSampleTakenError("Camera not ready");
            }
            return;
        }

        if (IsOperationRunning("captureSample")) {
            Log.d(TAG, "captureSample: Ignored because stop is pending");
            return;
        }
        Log.d(TAG, "captureSample: Starting sample capture with quality: " + quality);

        boolean dispatched = false;
        try {
            sampleImageCapture.takePicture(
                cameraExecutor,
                new ImageCapture.OnImageCapturedCallback() {
                    @Override
                    public void onError(@NonNull ImageCaptureException exception) {
                        Log.e(TAG, "captureSample: Sample capture failed", exception);
                        if (listener != null) {
                            listener.onSampleTakenError("Sample capture failed: " + exception.getMessage());
                        }
                        endOperation("captureSample");
                    }

                    @Override
                    public void onCaptureSuccess(@NonNull ImageProxy image) {
                        //noinspection TryFinallyCanBeTryWithResources
                        try {
                            // Convert ImageProxy to byte array
                            byte[] bytes = imageProxyToByteArray(image);
                            String base64 = Base64.encodeToString(bytes, Base64.NO_WRAP);

                            if (listener != null) {
                                listener.onSampleTaken(base64);
                            }
                        } catch (Exception e) {
                            Log.e(TAG, "captureSample: Error processing sample", e);
                            if (listener != null) {
                                listener.onSampleTakenError("Error processing sample: " + e.getMessage());
                            }
                        } finally {
                            image.close();
                            endOperation("captureSample");
                        }
                    }
                }
            );

            dispatched = true;
        } catch (Exception e) {
            Log.e(TAG, "captureSample: Failed to start sample capture", e);
            if (listener != null) {
                listener.onSampleTakenError("Sample capture failed: " + e.getMessage());
            }
        } finally {
            if (!dispatched) {
                endOperation("captureSample");
            }
        }
    }

    private byte[] imageProxyToByteArray(ImageProxy image) {
        ImageProxy.PlaneProxy[] planes = image.getPlanes();
        ByteBuffer buffer = planes[0].getBuffer();
        byte[] bytes = new byte[buffer.remaining()];
        buffer.get(bytes);
        return bytes;
    }

    private Bitmap cropBitmapToMatchPreview(Bitmap image) {
        if (previewContainer == null || previewView == null) {
            return image;
        }
        int containerWidth = previewContainer.getWidth();
        int containerHeight = previewContainer.getHeight();
        if (containerWidth == 0 || containerHeight == 0) {
            return image;
        }
        // Compute preview aspect based on actual camera content bounds
        Rect bounds = getActualCameraBounds();
        int previewW = Math.max(1, bounds.width());
        int previewH = Math.max(1, bounds.height());
        float previewRatio = (float) previewW / (float) previewH;

        int imgW = image.getWidth();
        int imgH = image.getHeight();
        float imgRatio = (float) imgW / (float) imgH;

        int targetW = imgW;
        int targetH = imgH;
        if (imgRatio > previewRatio) {
            // Image wider than preview: crop width
            targetW = Math.round(imgH * previewRatio);
        } else if (imgRatio < previewRatio) {
            // Image taller than preview: crop height
            targetH = Math.round(imgW / previewRatio);
        }
        int x = Math.max(0, (imgW - targetW) / 2);
        int y = Math.max(0, (imgH - targetH) / 2);
        try {
            return Bitmap.createBitmap(image, x, y, Math.min(targetW, imgW - x), Math.min(targetH, imgH - y));
        } catch (Exception ignore) {
            return image;
        }
    }

    // not working for xiaomi https://xiaomi.eu/community/threads/mi-11-ultra-unable-to-access-camera-lenses-in-apps-camera2-api.61456/
    @OptIn(markerClass = ExperimentalCamera2Interop.class)
    public static List<app.capgo.capacitor.camera.preview.model.CameraDevice> getAvailableDevicesStatic(Context context) {
        Log.d(TAG, "getAvailableDevicesStatic: Starting CameraX device enumeration with getPhysicalCameraInfos.");
        List<app.capgo.capacitor.camera.preview.model.CameraDevice> devices = new ArrayList<>();
        try {
            ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(context);
            ProcessCameraProvider cameraProvider = cameraProviderFuture.get();
            CameraManager cameraManager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);

            for (CameraInfo cameraInfo : cameraProvider.getAvailableCameraInfos()) {
                String logicalCameraId = Camera2CameraInfo.from(cameraInfo).getCameraId();
                String position = isBackCamera(cameraInfo) ? "rear" : "front";

                // Add logical camera
                float minZoom = Objects.requireNonNull(cameraInfo.getZoomState().getValue()).getMinZoomRatio();
                float maxZoom = cameraInfo.getZoomState().getValue().getMaxZoomRatio();
                List<LensInfo> logicalLenses = new ArrayList<>();
                logicalLenses.add(new LensInfo(4.25f, "wideAngle", 1.0f, maxZoom));
                devices.add(
                    new app.capgo.capacitor.camera.preview.model.CameraDevice(
                        logicalCameraId,
                        "Logical Camera (" + position + ")",
                        position,
                        logicalLenses,
                        minZoom,
                        maxZoom,
                        true
                    )
                );
                Log.d(TAG, "Found logical camera: " + logicalCameraId + " (" + position + ") with zoom " + minZoom + "-" + maxZoom);

                // Get and add physical cameras
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    Set<CameraInfo> physicalCameraInfos = cameraInfo.getPhysicalCameraInfos();
                    if (physicalCameraInfos.isEmpty()) continue;

                    Log.d(TAG, "Logical camera " + logicalCameraId + " has " + physicalCameraInfos.size() + " physical cameras.");

                    for (CameraInfo physicalCameraInfo : physicalCameraInfos) {
                        String physicalId = Camera2CameraInfo.from(physicalCameraInfo).getCameraId();
                        if (physicalId.equals(logicalCameraId)) continue; // Already added as logical

                        try {
                            CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(physicalId);
                            String deviceType = "wideAngle";
                            float[] focalLengths = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);
                            android.util.SizeF sensorSize = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE);

                            if (focalLengths != null && focalLengths.length > 0 && sensorSize != null && sensorSize.getWidth() > 0) {
                                double fov = 2 * Math.toDegrees(Math.atan(sensorSize.getWidth() / (2 * focalLengths[0])));
                                if (fov > 90) deviceType = "ultraWide";
                                else if (fov < 40) deviceType = "telephoto";
                            } else if (focalLengths != null && focalLengths.length > 0) {
                                if (focalLengths[0] < 3.0f) deviceType = "ultraWide";
                                else if (focalLengths[0] > 5.0f) deviceType = "telephoto";
                            }

                            float physicalMinZoom = 1.0f;
                            float physicalMaxZoom = 1.0f;
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                android.util.Range<Float> zoomRange = characteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE);
                                if (zoomRange != null) {
                                    physicalMinZoom = zoomRange.getLower();
                                    physicalMaxZoom = zoomRange.getUpper();
                                }
                            }

                            String label = "Physical " + deviceType + " (" + position + ")";
                            List<LensInfo> physicalLenses = new ArrayList<>();
                            physicalLenses.add(
                                new LensInfo(focalLengths != null ? focalLengths[0] : 4.25f, deviceType, 1.0f, physicalMaxZoom)
                            );

                            devices.add(
                                new app.capgo.capacitor.camera.preview.model.CameraDevice(
                                    physicalId,
                                    label,
                                    position,
                                    physicalLenses,
                                    physicalMinZoom,
                                    physicalMaxZoom,
                                    false
                                )
                            );
                            Log.d(TAG, "Found physical camera: " + physicalId + " (" + label + ")");
                        } catch (CameraAccessException e) {
                            Log.e(TAG, "Failed to access characteristics for physical camera " + physicalId, e);
                        }
                    }
                }
            }
            return devices;
        } catch (Exception e) {
            Log.e(TAG, "getAvailableDevicesStatic: Error getting devices", e);
            return Collections.emptyList();
        }
    }

    public static ZoomFactors getZoomFactorsStatic() {
        try {
            // For static method, return default zoom factors
            // We can try to detect if ultra-wide is available by checking device list

            float minZoom = 1.0f;
            float maxZoom = 10.0f;

            Log.d(TAG, "getZoomFactorsStatic: Final range - minZoom: " + minZoom + ", maxZoom: " + maxZoom);
            LensInfo defaultLens = new LensInfo(4.25f, "wideAngle", 1.0f, 1.0f);
            return new ZoomFactors(minZoom, maxZoom, 1.0f, defaultLens);
        } catch (Exception e) {
            Log.e(TAG, "getZoomFactorsStatic: Error getting zoom factors", e);
            LensInfo defaultLens = new LensInfo(4.25f, "wideAngle", 1.0f, 1.0f);
            return new ZoomFactors(1.0f, 10.0f, 1.0f, defaultLens);
        }
    }

    public ZoomFactors getZoomFactors() {
        if (camera == null) {
            return getZoomFactorsStatic();
        }

        try {
            // Get the current zoom from active camera
            float currentZoom = Objects.requireNonNull(camera.getCameraInfo().getZoomState().getValue()).getZoomRatio();
            float minZoom = camera.getCameraInfo().getZoomState().getValue().getMinZoomRatio();
            float maxZoom = camera.getCameraInfo().getZoomState().getValue().getMaxZoomRatio();

            Log.d(TAG, "getZoomFactors: Combined range - minZoom: " + minZoom + ", maxZoom: " + maxZoom + ", currentZoom: " + currentZoom);

            return new ZoomFactors(minZoom, maxZoom, currentZoom, getCurrentLensInfo());
        } catch (Exception e) {
            Log.e(TAG, "getZoomFactors: Error getting zoom factors", e);
            return new ZoomFactors(1.0f, 1.0f, 1.0f, getCurrentLensInfo());
        }
    }

    private LensInfo getCurrentLensInfo() {
        if (camera == null) {
            return new LensInfo(4.25f, "wideAngle", 1.0f, 1.0f);
        }

        try {
            float currentZoom = Objects.requireNonNull(camera.getCameraInfo().getZoomState().getValue()).getZoomRatio();

            // Determine device type based on zoom capabilities
            String deviceType = "wideAngle";
            float baseZoomRatio = 1.0f;

            float digitalZoom = currentZoom / baseZoomRatio;

            return new LensInfo(4.25f, deviceType, baseZoomRatio, digitalZoom);
        } catch (Exception e) {
            Log.e(TAG, "getCurrentLensInfo: Error getting lens info", e);
            return new LensInfo(4.25f, "wideAngle", 1.0f, 1.0f);
        }
    }

    public void setZoom(float zoomRatio) throws Exception {
        if (camera == null) {
            throw new Exception("Camera not initialized");
        }

        Log.d(TAG, "setZoom: Requested zoom ratio: " + zoomRatio);

        // Just let CameraX handle everything - it should automatically switch lenses
        try {
            ZoomFactors zoomFactors = getZoomFactors();

            if (zoomRatio < zoomFactors.getMin()) {
                zoomRatio = zoomFactors.getMin();
            } else if (zoomRatio > zoomFactors.getMax()) {
                zoomRatio = zoomFactors.getMax();
            }

            camera.getCameraControl().setZoomRatio(zoomRatio);
            // Note: autofocus is intentionally not triggered on zoom because it's done by CameraX
        } catch (Exception e) {
            Log.e(TAG, "Failed to set zoom: " + e.getMessage());
            throw e;
        }
    }

    public void setFocus(float x, float y) throws Exception {
        // Ignore focus if capture/stop is in progress or view is gone
        synchronized (captureLock) {
            if (isCapturingPhoto || stopRequested) {
                Log.d(TAG, "setFocus: Ignored because capture/stop in progress");
                return;
            }
        }
        if (!isRunning || camera == null || previewView == null || previewContainer == null) {
            Log.d(TAG, "setFocus: Ignored because camera/view not ready or not running");
            return;
        }
        // Validate that coordinates are within bounds (0-1 range)
        if (x < 0f || x > 1f || y < 0f || y > 1f) {
            Log.w(TAG, "setFocus: Coordinates out of bounds - x: " + x + ", y: " + y);
            throw new Exception("Focus coordinates must be between 0 and 1");
        }

        // Cancel any ongoing focus operation
        if (currentFocusFuture != null && !currentFocusFuture.isDone()) {
            Log.d(TAG, "setFocus: Cancelling previous focus operation");
            currentFocusFuture.cancel(true);
        }

        // Reset exposure compensation to 0 on tap-to-focus
        try {
            ExposureState state = camera.getCameraInfo().getExposureState();
            Range<Integer> range = state.getExposureCompensationRange();
            int zeroIdx = 0;
            if (!range.contains(0)) {
                // Choose the closest index to 0 if 0 is not available
                zeroIdx = Math.abs(range.getLower()) < Math.abs(range.getUpper()) ? range.getLower() : range.getUpper();
            }
            camera.getCameraControl().setExposureCompensationIndex(zeroIdx);
        } catch (Exception e) {
            Log.w(TAG, "setFocus: Failed to reset exposure compensation to 0", e);
        }

        int viewWidth = previewView.getWidth();
        int viewHeight = previewView.getHeight();

        if (viewWidth <= 0 || viewHeight <= 0) {
            throw new Exception("Preview view has invalid dimensions: " + viewWidth + "x" + viewHeight);
        }

        MeteringPointFactory factory = previewView.getMeteringPointFactory();
        MeteringPoint point = factory.createPoint(x * viewWidth, y * viewHeight);

        // Create focus and metering action (persistent, no auto-cancel) to match iOS behavior
        FocusMeteringAction action = new FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF | FocusMeteringAction.FLAG_AE)
            .disableAutoCancel()
            .build();

        if (IsOperationRunning("setFocus")) {
            Log.d(TAG, "setFocus: Ignored because stop is pending");
            return;
        }

        // Only show focus indicator after validation passes and operation is accepted
        float indicatorX = x * viewWidth;
        float indicatorY = y * viewHeight;
        long indicatorToken = focusIndicatorAnimationId;
        try {
            indicatorToken = showFocusIndicator(indicatorX, indicatorY);
        } catch (Exception ignore) {
            // If we can't show the indicator (e.g., view is gone), still proceed with metering
        }

        ListenableFuture<FocusMeteringResult> future = null;
        boolean dispatched = false;
        try {
            future = camera.getCameraControl().startFocusAndMetering(action);
            currentFocusFuture = future;
            dispatched = true;

            final ListenableFuture<FocusMeteringResult> capturedFuture = future;
            final long tokenForListener = indicatorToken;
            future.addListener(
                () -> {
                    try {
                        FocusMeteringResult result = capturedFuture.get();
                    } catch (Exception e) {
                        // Handle cancellation gracefully - this is expected when rapid taps occur
                        if (
                            e.getMessage() != null &&
                            (e.getMessage().contains("Cancelled by another startFocusAndMetering") ||
                                e.getMessage().contains("OperationCanceledException") ||
                                e.getClass().getSimpleName().contains("OperationCanceledException"))
                        ) {
                            Log.d(TAG, "Focus operation was cancelled by a newer focus request");
                        } else {
                            Log.e(TAG, "Error during focus: " + e.getMessage());
                        }
                    } finally {
                        if (currentFocusFuture == capturedFuture && currentFocusFuture.isDone()) {
                            currentFocusFuture = null;
                        }
                        hideFocusIndicator(tokenForListener);
                        endOperation("setFocus");
                    }
                },
                ContextCompat.getMainExecutor(context)
            );
        } catch (Exception e) {
            currentFocusFuture = null;
            Log.e(TAG, "Failed to set focus: " + e.getMessage());
            throw e;
        } finally {
            if (!dispatched) {
                if (currentFocusFuture == future) {
                    currentFocusFuture = null;
                }
                hideFocusIndicator(indicatorToken);
                endOperation("setFocus");
            }
        }
    }

    // ===================== Exposure APIs =====================
    public java.util.List<String> getExposureModes() {
        return Arrays.asList("LOCK", "CONTINUOUS");
    }

    public String getExposureMode() {
        return currentExposureMode;
    }

    @OptIn(markerClass = ExperimentalCamera2Interop.class)
    public void setExposureMode(String mode) throws Exception {
        if (camera == null) {
            throw new Exception("Camera not initialized");
        }
        if (mode == null) {
            throw new Exception("mode is required");
        }
        String normalized = mode.toUpperCase(Locale.US);

        Camera2CameraControl c2 = Camera2CameraControl.from(camera.getCameraControl());
        switch (normalized) {
            case "LOCK": {
                CaptureRequestOptions opts = new CaptureRequestOptions.Builder()
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, true)
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                    .build();
                mainExecutor.execute(() -> c2.setCaptureRequestOptions(opts));
                currentExposureMode = "LOCK";
                break;
            }
            case "CONTINUOUS": {
                CaptureRequestOptions opts = new CaptureRequestOptions.Builder()
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, false)
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                    .build();
                mainExecutor.execute(() -> c2.setCaptureRequestOptions(opts));
                currentExposureMode = "CONTINUOUS";
                break;
            }
            default:
                throw new Exception("Unsupported exposure mode: " + mode);
        }
    }

    public float[] getExposureCompensationRange() throws Exception {
        if (camera == null) {
            throw new Exception("Camera not initialized");
        }
        ExposureState state = camera.getCameraInfo().getExposureState();
        Range<Integer> idxRange = state.getExposureCompensationRange();
        Rational step = state.getExposureCompensationStep();
        float evStep = (float) step.getNumerator() / (float) step.getDenominator();
        float min = idxRange.getLower() * evStep;
        float max = idxRange.getUpper() * evStep;
        return new float[] { min, max, evStep };
    }

    public float getExposureCompensation() throws Exception {
        if (camera == null) {
            throw new Exception("Camera not initialized");
        }
        ExposureState state = camera.getCameraInfo().getExposureState();
        int idx = state.getExposureCompensationIndex();
        Rational step = state.getExposureCompensationStep();
        float evStep = (float) step.getNumerator() / (float) step.getDenominator();
        return idx * evStep;
    }

    public void setExposureCompensation(float ev) throws Exception {
        if (camera == null) {
            throw new Exception("Camera not initialized");
        }
        ExposureState state = camera.getCameraInfo().getExposureState();
        Range<Integer> idxRange = state.getExposureCompensationRange();
        Rational step = state.getExposureCompensationStep();
        float evStep = (float) step.getNumerator() / (float) step.getDenominator();
        if (evStep <= 0f) evStep = 1.0f;
        int idx = Math.round(ev / evStep);
        // clamp
        if (idx < idxRange.getLower()) idx = idxRange.getLower();
        if (idx > idxRange.getUpper()) idx = idxRange.getUpper();
        camera.getCameraControl().setExposureCompensationIndex(idx);
    }

    private void resetExposureCompensationToDefault() {
        if (camera == null) {
            return;
        }
        try {
            ExposureState state = camera.getCameraInfo().getExposureState();
            Range<Integer> range = state.getExposureCompensationRange();
            int neutralIdx = 0;
            if (!range.contains(0)) {
                int lower = range.getLower();
                int upper = range.getUpper();
                neutralIdx = Math.abs(lower) <= Math.abs(upper) ? lower : upper;
            }
            camera.getCameraControl().setExposureCompensationIndex(neutralIdx);
        } catch (Exception e) {
            Log.w(TAG, "resetExposureCompensationToDefault: Failed to reset exposure compensation", e);
        }
    }

    private long showFocusIndicator(float x, float y) {
        // If preview is gone (e.g., stopping/closing), bail out safely
        if (previewContainer == null) {
            Log.w(TAG, "showFocusIndicator: previewContainer is null");
            return focusIndicatorAnimationId;
        }
        if (sessionConfig.getDisableFocusIndicator()) {
            return focusIndicatorAnimationId;
        }

        // Check if container has been laid out
        if (previewContainer.getWidth() == 0 || previewContainer.getHeight() == 0) {
            Log.w(TAG, "showFocusIndicator: previewContainer not laid out yet, posting to run after layout");
            previewContainer.post(() -> showFocusIndicator(x, y));
            return focusIndicatorAnimationId;
        }

        // Remove any existing focus indicators (ensure only one is visible)
        try {
            for (int i = previewContainer.getChildCount() - 1; i >= 0; i--) {
                View child = previewContainer.getChildAt(i);
                CharSequence desc = child.getContentDescription();
                if (desc != null && FOCUS_INDICATOR_TAG.contentEquals(desc)) {
                    previewContainer.removeViewAt(i);
                }
            }
            if (focusIndicatorView != null) {
                ViewGroup parent = (ViewGroup) focusIndicatorView.getParent();
                if (parent != null) parent.removeView(focusIndicatorView);
                focusIndicatorView = null;
            }
        } catch (Exception ignore) {}

        // Create an elegant focus indicator
        FrameLayout container = new FrameLayout(context);
        int size = (int) (80 * context.getResources().getDisplayMetrics().density); // match iOS size
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(size, size);

        // Center the indicator on the touch point with bounds checking
        int containerWidth = previewContainer.getWidth();
        int containerHeight = previewContainer.getHeight();

        params.leftMargin = Math.max(0, Math.min((int) (x - (float) size / 2), containerWidth - size));
        params.topMargin = Math.max(0, Math.min((int) (y - (float) size / 2), containerHeight - size));

        // iOS Camera style: square with mid-edge ticks
        GradientDrawable border = new GradientDrawable();
        border.setShape(GradientDrawable.RECTANGLE);
        int stroke = (int) (2 * context.getResources().getDisplayMetrics().density);
        border.setStroke(stroke, Color.YELLOW);
        border.setCornerRadius(0);
        border.setColor(Color.TRANSPARENT);
        container.setBackground(border);

        // Add 4 tiny mid-edge ticks inside the square
        int tickLen = (int) (12 * context.getResources().getDisplayMetrics().density);
        // ticks should touch the sides
        // Top tick (perpendicular): vertical inward from top edge
        View topTick = new View(context);
        FrameLayout.LayoutParams topParams = new FrameLayout.LayoutParams(stroke, tickLen);
        topParams.leftMargin = (size - stroke) / 2;
        topParams.topMargin = stroke;
        topTick.setLayoutParams(topParams);
        topTick.setBackgroundColor(Color.YELLOW);
        container.addView(topTick);
        // Bottom tick (perpendicular): vertical inward from bottom edge
        View bottomTick = new View(context);
        FrameLayout.LayoutParams bottomParams = new FrameLayout.LayoutParams(stroke, tickLen);
        bottomParams.leftMargin = (size - stroke) / 2;
        bottomParams.topMargin = size - stroke - tickLen;
        bottomTick.setLayoutParams(bottomParams);
        bottomTick.setBackgroundColor(Color.YELLOW);
        container.addView(bottomTick);
        // Left tick (perpendicular): horizontal inward from left edge
        View leftTick = new View(context);
        FrameLayout.LayoutParams leftParams = new FrameLayout.LayoutParams(tickLen, stroke);
        leftParams.leftMargin = stroke;
        leftParams.topMargin = (size - stroke) / 2;
        leftTick.setLayoutParams(leftParams);
        leftTick.setBackgroundColor(Color.YELLOW);
        container.addView(leftTick);
        // Right tick (perpendicular): horizontal inward from right edge
        View rightTick = new View(context);
        FrameLayout.LayoutParams rightParams = new FrameLayout.LayoutParams(tickLen, stroke);
        rightParams.leftMargin = size - stroke - tickLen;
        rightParams.topMargin = (size - stroke) / 2;
        rightTick.setLayoutParams(rightParams);
        rightTick.setBackgroundColor(Color.YELLOW);
        container.addView(rightTick);

        container.setContentDescription(FOCUS_INDICATOR_TAG);
        focusIndicatorView = container;
        // Bump animation token; everything after this must validate against this token
        final long thisAnimationId = ++focusIndicatorAnimationId;
        final View thisIndicatorView = focusIndicatorView;

        // Show immediately (avoid complex animations that can race with teardown)
        focusIndicatorView.setAlpha(1f);
        focusIndicatorView.setScaleX(1f);
        focusIndicatorView.setScaleY(1f);
        focusIndicatorView.setVisibility(View.VISIBLE);

        // Ensure container doesn't intercept touch events
        container.setClickable(false);
        container.setFocusable(false);

        // Ensure the focus indicator has a high elevation for visibility
        focusIndicatorView.setElevation(10f);

        // Add to container first
        previewContainer.addView(focusIndicatorView, params);

        // Fix z-ordering: ensure focus indicator is always on top
        focusIndicatorView.bringToFront();

        // Force a layout pass to ensure the view is properly positioned
        previewContainer.requestLayout();

        // Do not schedule delayed cleanup; indicator will be removed when focus completes
        return thisAnimationId;
    }

    private void hideFocusIndicator(long token) {
        // If we're stopping or not running anymore, don't attempt to touch the view tree
        if (stopRequested || !isRunning) {
            focusIndicatorView = null;
            return;
        }
        try {
            mainExecutor.execute(() -> {
                try {
                    if (focusIndicatorView == null || previewContainer == null || token != focusIndicatorAnimationId) {
                        return;
                    }
                    // If the view hierarchy is already being torn down, skip safely
                    if (!previewContainer.isAttachedToWindow()) {
                        focusIndicatorView = null;
                        return;
                    }
                    ViewGroup parent = (ViewGroup) focusIndicatorView.getParent();
                    if (parent != null) {
                        parent.removeView(focusIndicatorView);
                    }
                } catch (Exception ignore) {} finally {
                    focusIndicatorView = null;
                }
            });
        } catch (Exception ignore) {
            // Executor or Looper not available; just null out the reference
            focusIndicatorView = null;
        }
    }

    public static List<Size> getSupportedPictureSizes(String facing) {
        List<Size> sizes = new ArrayList<>();
        try {
            CameraSelector.Builder builder = new CameraSelector.Builder();
            if ("front".equals(facing)) {
                builder.requireLensFacing(CameraSelector.LENS_FACING_FRONT);
            } else {
                builder.requireLensFacing(CameraSelector.LENS_FACING_BACK);
            }

            // This part is complex because we need characteristics, which are not directly on CameraInfo.
            // For now, returning a static list of common sizes.
            // A more advanced implementation would use Camera2interop to get StreamConfigurationMap.
            sizes.add(new Size(4032, 3024));
            sizes.add(new Size(1920, 1080));
            sizes.add(new Size(1280, 720));
            sizes.add(new Size(640, 480));
        } catch (Exception e) {
            Log.e(TAG, "Error getting supported picture sizes", e);
        }
        return sizes;
    }

    public static List<String> getSupportedFlashModesStatic() {
        try {
            // For static method, we can return common flash modes
            // Most modern cameras support these modes
            return Arrays.asList("off", "on", "auto", "torch");
        } catch (Exception e) {
            Log.e(TAG, "getSupportedFlashModesStatic: Error getting flash modes", e);
            return Collections.singletonList("off");
        }
    }

    public List<String> getSupportedFlashModes() {
        if (camera == null) {
            return getSupportedFlashModesStatic();
        }

        try {
            boolean hasFlash = camera.getCameraInfo().hasFlashUnit();
            if (hasFlash) {
                // Include torch for devices with a flash unit
                return Arrays.asList("off", "on", "auto", "torch");
            } else {
                return Collections.singletonList("off");
            }
        } catch (Exception e) {
            Log.e(TAG, "getSupportedFlashModes: Error getting flash modes", e);
            return Collections.singletonList("off");
        }
    }

    public String getFlashMode() {
        // If torch is enabled, report torch regardless of ImageCapture flash mode
        try {
            if (camera != null) {
                Integer torch = camera.getCameraInfo().getTorchState().getValue();
                if (torch != null && torch == TorchState.ON) {
                    return "torch";
                }
            }
        } catch (Exception ignore) {}

        switch (currentFlashMode) {
            case ImageCapture.FLASH_MODE_ON:
                return "on";
            case ImageCapture.FLASH_MODE_AUTO:
                return "auto";
            default:
                return "off";
        }
    }

    public void setFlashMode(String mode) {
        // Handle torch separately via CameraControl
        if ("torch".equals(mode)) {
            try {
                if (camera != null) {
                    camera.getCameraControl().enableTorch(true);
                }
            } catch (Exception e) {
                Log.e(TAG, "setFlashMode: Failed to enable torch", e);
            }
            // Keep ImageCapture flash mode OFF to avoid conflicts with torch
            currentFlashMode = ImageCapture.FLASH_MODE_OFF;
            if (imageCapture != null) {
                imageCapture.setFlashMode(ImageCapture.FLASH_MODE_OFF);
            }
            if (sampleImageCapture != null) {
                sampleImageCapture.setFlashMode(ImageCapture.FLASH_MODE_OFF);
            }
            return;
        }

        // For non-torch modes, ensure torch is disabled
        try {
            if (camera != null) {
                camera.getCameraControl().enableTorch(false);
            }
        } catch (Exception e) {
            Log.w(TAG, "setFlashMode: Failed to disable torch", e);
        }

        int flashMode;
        switch (mode) {
            case "on":
                flashMode = ImageCapture.FLASH_MODE_ON;
                break;
            case "auto":
                flashMode = ImageCapture.FLASH_MODE_AUTO;
                break;
            default:
                flashMode = ImageCapture.FLASH_MODE_OFF;
                break;
        }

        currentFlashMode = flashMode;

        if (imageCapture != null) {
            imageCapture.setFlashMode(flashMode);
        }
        if (sampleImageCapture != null) {
            sampleImageCapture.setFlashMode(flashMode);
        }
    }

    public String getCurrentDeviceId() {
        return currentDeviceId != null ? currentDeviceId : "unknown";
    }

    @OptIn(markerClass = ExperimentalCamera2Interop.class)
    public void switchToDevice(String deviceId) {
        Log.d(TAG, "switchToDevice: Attempting to switch to device " + deviceId);

        mainExecutor.execute(() -> {
            try {
                // Standard physical device selection logic...
                List<CameraInfo> cameraInfos = cameraProvider.getAvailableCameraInfos();
                CameraInfo targetCameraInfo = null;
                for (CameraInfo cameraInfo : cameraInfos) {
                    if (deviceId.equals(Camera2CameraInfo.from(cameraInfo).getCameraId())) {
                        targetCameraInfo = cameraInfo;
                        break;
                    }
                }

                if (targetCameraInfo != null) {
                    Log.d(TAG, "switchToDevice: Found matching CameraInfo for deviceId: " + deviceId);
                    final CameraInfo finalTarget = targetCameraInfo;

                    // This filter will receive a list of all cameras and must return the one we want.

                    currentCameraSelector = new CameraSelector.Builder()
                        .addCameraFilter((cameras) -> {
                            // This filter will receive a list of all cameras and must return the one we want.
                            return Collections.singletonList(finalTarget);
                        })
                        .build();
                    currentDeviceId = deviceId;
                    bindCameraUseCases(); // Rebind with the new, highly specific selector
                } else {
                    Log.e(TAG, "switchToDevice: Could not find any CameraInfo matching deviceId: " + deviceId);
                }
            } catch (Exception e) {
                Log.e(TAG, "switchToDevice: Error switching camera", e);
            }
        });
    }

    public void flipCamera() {
        Log.d(TAG, "flipCamera: Flipping camera");

        // Determine current position based on session config and flip it
        String currentPosition = sessionConfig.getPosition();
        String newPosition = "front".equals(currentPosition) ? "rear" : "front";

        Log.d(TAG, "flipCamera: Switching from " + currentPosition + " to " + newPosition);

        sessionConfig = new CameraSessionConfiguration(
            null, // deviceId - clear device ID to force position-based selection
            newPosition, // position
            sessionConfig.getX(), // x
            sessionConfig.getY(), // y
            sessionConfig.getWidth(), // width
            sessionConfig.getHeight(), // height
            sessionConfig.getPaddingBottom(), // paddingBottom
            sessionConfig.isToBack(), // toBack
            sessionConfig.isStoreToFile(), // storeToFile
            sessionConfig.isEnableOpacity(), // enableOpacity
            sessionConfig.isDisableExifHeaderStripping(), // disableExifHeaderStripping
            sessionConfig.isDisableAudio(), // disableAudio
            sessionConfig.getZoomFactor(), // zoomFactor
            sessionConfig.getAspectRatio(), // aspectRatio
            sessionConfig.getGridMode(), // gridMode
            sessionConfig.getDisableFocusIndicator(), // disableFocusIndicator
            sessionConfig.isVideoModeEnabled() // enableVideoMode
        );

        // Clear current device ID to force position-based selection
        currentDeviceId = null;

        // Camera operations must run on main thread
        cameraExecutor.execute(() -> {
            currentCameraSelector = buildCameraSelector();
            bindCameraUseCases();
        });
    }

    public void setOpacity(float opacity) {
        if (previewView != null) {
            previewView.setAlpha(opacity);
        }
    }

    private void updateLayoutParams() {
        if (sessionConfig == null) return;

        FrameLayout.LayoutParams layoutParams = new FrameLayout.LayoutParams(sessionConfig.getWidth(), sessionConfig.getHeight());
        layoutParams.leftMargin = sessionConfig.getX();
        layoutParams.topMargin = sessionConfig.getY();

        if (sessionConfig.getAspectRatio() != null) {
            String[] ratios = sessionConfig.getAspectRatio().split(":");
            // For camera, use portrait orientation: 4:3 becomes 3:4, 16:9 becomes 9:16
            float ratio = Float.parseFloat(ratios[1]) / Float.parseFloat(ratios[0]);
            if (sessionConfig.getWidth() > 0) {
                layoutParams.height = (int) (sessionConfig.getWidth() / ratio);
            } else if (sessionConfig.getHeight() > 0) {
                layoutParams.width = (int) (sessionConfig.getHeight() * ratio);
            }
        }

        previewView.setLayoutParams(layoutParams);

        if (listener != null) {
            listener.onCameraStarted(sessionConfig.getWidth(), sessionConfig.getHeight(), sessionConfig.getX(), sessionConfig.getY());
        }
    }

    public String getAspectRatio() {
        if (sessionConfig != null) {
            return sessionConfig.getAspectRatio();
        }
        return "4:3";
    }

    public String getGridMode() {
        if (sessionConfig != null) {
            return sessionConfig.getGridMode();
        }
        return "none";
    }

    public void setAspectRatio(String aspectRatio) {
        setAspectRatio(aspectRatio, null, null);
    }

    public void setAspectRatio(String aspectRatio, Float x, Float y) {
        setAspectRatio(aspectRatio, x, y, null);
    }

    public void setAspectRatio(String aspectRatio, Float x, Float y, Runnable callback) {
        Log.d(TAG, "======================== SET ASPECT RATIO ========================");
        Log.d(TAG, "Input parameters - aspectRatio: " + aspectRatio + ", x: " + x + ", y: " + y);

        if (sessionConfig == null) {
            Log.d(TAG, "SessionConfig is null, returning");
            if (callback != null) callback.run();
            return;
        }

        String currentAspectRatio = sessionConfig.getAspectRatio();

        // Get current display information
        DisplayMetrics metrics = context.getResources().getDisplayMetrics();
        int screenWidthPx = metrics.widthPixels;
        int screenHeightPx = metrics.heightPixels;
        boolean isPortrait = context.getResources().getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;

        Log.d(TAG, "Current screen: " + screenWidthPx + "x" + screenHeightPx + " (" + (isPortrait ? "PORTRAIT" : "LANDSCAPE") + ")");
        Log.d(TAG, "Current aspect ratio: " + currentAspectRatio);

        // Don't restart camera if aspect ratio hasn't changed and no position specified
        if (aspectRatio != null && aspectRatio.equals(currentAspectRatio) && x == null && y == null) {
            Log.d(TAG, "Aspect ratio unchanged and no position specified, skipping");
            if (callback != null) callback.run();
            return;
        }

        String currentGridMode = sessionConfig.getGridMode();
        Log.d(TAG, "Changing aspect ratio from " + currentAspectRatio + " to " + aspectRatio);
        Log.d(TAG, "Auto-centering will be applied (matching iOS behavior)");

        // Match iOS behavior: when aspect ratio changes, always auto-center
        sessionConfig = new CameraSessionConfiguration(
            sessionConfig.getDeviceId(),
            sessionConfig.getPosition(),
            -1, // Force auto-center X (iOS: self.posX = -1)
            -1, // Force auto-center Y (iOS: self.posY = -1)
            sessionConfig.getWidth(),
            sessionConfig.getHeight(),
            sessionConfig.getPaddingBottom(),
            sessionConfig.getToBack(),
            sessionConfig.getStoreToFile(),
            sessionConfig.getEnableOpacity(),
            sessionConfig.getDisableExifHeaderStripping(),
            sessionConfig.getDisableAudio(),
            sessionConfig.getZoomFactor(),
            aspectRatio,
            currentGridMode,
            sessionConfig.getDisableFocusIndicator(),
            sessionConfig.isVideoModeEnabled()
        );
        sessionConfig.setCentered(true);

        // Update layout and rebind camera with new aspect ratio
        if (isRunning && previewContainer != null) {
            mainExecutor.execute(() -> {
                // First update the UI layout - always pass null for x,y to force auto-centering (matching iOS)
                updatePreviewLayoutForAspectRatio(aspectRatio);

                // Then rebind the camera with new aspect ratio configuration
                Log.d(TAG, "setAspectRatio: Rebinding camera with new aspect ratio: " + aspectRatio);
                bindCameraUseCases();

                // Preserve grid mode and wait for completion
                if (gridOverlayView != null) {
                    gridOverlayView.post(() -> {
                        Log.d(TAG, "setAspectRatio: Re-applying grid mode: " + currentGridMode);
                        gridOverlayView.setGridMode(currentGridMode);

                        // Wait one more frame for grid to be applied, then call callback
                        if (callback != null) {
                            gridOverlayView.post(callback);
                        }
                    });
                } else {
                    // No grid overlay, wait one frame for layout completion then call callback
                    if (callback != null) {
                        previewContainer.post(callback);
                    }
                }

                Log.d(TAG, "==================================================================");
            });
        } else {
            Log.d(TAG, "Camera not running, just saving configuration");
            Log.d(TAG, "==================================================================");
            if (callback != null) callback.run();
        }
    }

    // Force aspect ratio recalculation (used during orientation changes)
    public void forceAspectRatioRecalculation(String aspectRatio, Float x, Float y, Runnable callback) {
        Log.d(TAG, "======================== FORCE ASPECT RATIO RECALCULATION ========================");
        Log.d(TAG, "Input parameters - aspectRatio: " + aspectRatio + ", x: " + x + ", y: " + y);

        if (sessionConfig == null) {
            Log.d(TAG, "SessionConfig is null, returning");
            if (callback != null) callback.run();
            return;
        }

        String currentGridMode = sessionConfig.getGridMode();
        Log.d(TAG, "Forcing aspect ratio recalculation for: " + aspectRatio);
        Log.d(TAG, "Auto-centering will be applied (matching iOS behavior)");

        // Match iOS behavior: when aspect ratio changes, always auto-center
        sessionConfig = new CameraSessionConfiguration(
            sessionConfig.getDeviceId(),
            sessionConfig.getPosition(),
            -1, // Force auto-center X (iOS: self.posX = -1)
            -1, // Force auto-center Y (iOS: self.posY = -1)
            sessionConfig.getWidth(),
            sessionConfig.getHeight(),
            sessionConfig.getPaddingBottom(),
            sessionConfig.getToBack(),
            sessionConfig.getStoreToFile(),
            sessionConfig.getEnableOpacity(),
            sessionConfig.getDisableExifHeaderStripping(),
            sessionConfig.getDisableAudio(),
            sessionConfig.getZoomFactor(),
            aspectRatio,
            currentGridMode,
            sessionConfig.getDisableFocusIndicator(),
            sessionConfig.isVideoModeEnabled()
        );
        sessionConfig.setCentered(true);

        // Update layout and rebind camera with new aspect ratio
        if (isRunning && previewContainer != null) {
            mainExecutor.execute(() -> {
                // First update the UI layout - always pass null for x,y to force auto-centering (matching iOS)
                updatePreviewLayoutForAspectRatio(aspectRatio);

                // Then rebind the camera with new aspect ratio configuration
                Log.d(TAG, "forceAspectRatioRecalculation: Rebinding camera with aspect ratio: " + aspectRatio);
                bindCameraUseCases();

                // Preserve grid mode and wait for completion
                if (gridOverlayView != null) {
                    gridOverlayView.post(() -> {
                        Log.d(TAG, "forceAspectRatioRecalculation: Re-applying grid mode: " + currentGridMode);
                        gridOverlayView.setGridMode(currentGridMode);

                        // Wait one more frame for grid to be applied, then call callback
                        if (callback != null) {
                            gridOverlayView.post(callback);
                        }
                    });
                } else {
                    // No grid overlay, wait one frame for layout completion then call callback
                    if (callback != null) {
                        previewContainer.post(callback);
                    }
                }

                Log.d(TAG, "==================================================================");
            });
        } else {
            Log.d(TAG, "Camera not running, just saving configuration");
            Log.d(TAG, "==================================================================");
            if (callback != null) callback.run();
        }
    }

    public void setGridMode(String gridMode) {
        if (sessionConfig != null) {
            Log.d(TAG, "setGridMode: Changing grid mode to: " + gridMode);
            sessionConfig = new CameraSessionConfiguration(
                sessionConfig.getDeviceId(),
                sessionConfig.getPosition(),
                sessionConfig.getX(),
                sessionConfig.getY(),
                sessionConfig.getWidth(),
                sessionConfig.getHeight(),
                sessionConfig.getPaddingBottom(),
                sessionConfig.getToBack(),
                sessionConfig.getStoreToFile(),
                sessionConfig.getEnableOpacity(),
                sessionConfig.getDisableExifHeaderStripping(),
                sessionConfig.getDisableAudio(),
                sessionConfig.getZoomFactor(),
                sessionConfig.getAspectRatio(),
                gridMode,
                sessionConfig.getDisableFocusIndicator(),
                sessionConfig.isVideoModeEnabled()
            );

            // Update the grid overlay immediately
            if (gridOverlayView != null) {
                gridOverlayView.post(() -> {
                    Log.d(TAG, "setGridMode: Applying grid mode to overlay: " + gridMode);
                    gridOverlayView.setGridMode(gridMode);
                });
            }
        }
    }

    public int getPreviewX() {
        if (previewContainer == null) return 0;

        // Get the container position
        ViewGroup.LayoutParams layoutParams = previewContainer.getLayoutParams();
        if (layoutParams instanceof ViewGroup.MarginLayoutParams) {
            int containerX = ((ViewGroup.MarginLayoutParams) layoutParams).leftMargin;

            // Get the actual camera bounds within the container
            Rect cameraBounds = getActualCameraBounds();
            int actualX = containerX + cameraBounds.left;

            Log.d(TAG, "getPreviewX: containerX=" + containerX + ", cameraBounds.left=" + cameraBounds.left + ", actualX=" + actualX);

            return actualX;
        }
        return previewContainer.getLeft();
    }

    public int getPreviewY() {
        if (previewContainer == null) return 0;

        // Get the container position
        ViewGroup.LayoutParams layoutParams = previewContainer.getLayoutParams();
        if (layoutParams instanceof ViewGroup.MarginLayoutParams) {
            int containerY = ((ViewGroup.MarginLayoutParams) layoutParams).topMargin;

            // Get the actual camera bounds within the container
            Rect cameraBounds = getActualCameraBounds();
            int actualY = containerY + cameraBounds.top;

            Log.d(TAG, "getPreviewY: containerY=" + containerY + ", cameraBounds.top=" + cameraBounds.top + ", actualY=" + actualY);

            return actualY;
        }
        return previewContainer.getTop();
    }

    // Get the actual camera content bounds within the PreviewView
    private Rect getActualCameraBounds() {
        if (previewView == null || previewContainer == null) {
            return new Rect(0, 0, 0, 0);
        }

        // Get the container bounds
        int containerWidth = previewContainer.getWidth();
        int containerHeight = previewContainer.getHeight();

        // Get the preview transformation info to understand how the camera is scaled/positioned
        // For FIT_CENTER, the camera content is scaled to fit within the container
        // This might create letterboxing (black bars) on top/bottom or left/right

        // Get the actual preview resolution
        if (currentPreviewResolution == null) {
            // If we don't have the resolution yet, assume the container is filled
            return new Rect(0, 0, containerWidth, containerHeight);
        }

        // CameraX delivers preview in sensor orientation (always landscape)
        // But PreviewView internally rotates it to match device orientation
        // So we need to swap dimensions in portrait mode
        int cameraWidth = currentPreviewResolution.getWidth();
        int cameraHeight = currentPreviewResolution.getHeight();

        // Check if we're in portrait mode
        boolean isPortrait = context.getResources().getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;

        // Swap dimensions if in portrait mode to match how PreviewView displays it
        if (isPortrait) {
            int temp = cameraWidth;
            //noinspection SuspiciousNameCombination,ReassignedVariable
            cameraWidth = cameraHeight;
            cameraHeight = temp;
        }

        // When we have an aspect ratio set, we use FILL_CENTER which scales to fill
        // the container while maintaining aspect ratio, potentially cropping
        boolean usesFillCenter = sessionConfig != null && sessionConfig.getAspectRatio() != null;

        // For FILL_CENTER with aspect ratio, we need to calculate the actual visible bounds
        // The preview might extend beyond the container bounds and get clipped
        if (usesFillCenter) {
            // Calculate how the camera preview is scaled to fill the container
            float widthScale = (float) containerWidth / cameraWidth;
            float heightScale = (float) containerHeight / cameraHeight;
            float scale = Math.max(widthScale, heightScale); // max for FILL_CENTER

            // Calculate the scaled dimensions
            int scaledWidth = Math.round(cameraWidth * scale);
            int scaledHeight = Math.round(cameraHeight * scale);

            // Calculate how much is clipped on each side
            int excessWidth = Math.max(0, scaledWidth - containerWidth);
            int excessHeight = Math.max(0, scaledHeight - containerHeight);

            // For the actual visible bounds, we need to account for potential
            // internal misalignment of PreviewView's SurfaceView
            int adjustedWidth = containerWidth;
            int adjustedHeight = containerHeight;

            // Apply small adjustments for 4:3 ratio to prevent blue line
            // This compensates for PreviewView's internal SurfaceView misalignment
            String aspectRatio = sessionConfig != null ? sessionConfig.getAspectRatio() : null;
            if ("4:3".equals(aspectRatio)) {
                // For 4:3, reduce the reported width slightly to account for
                // the SurfaceView drawing outside its bounds
                adjustedWidth = containerWidth - 2;
                adjustedHeight = containerHeight - 2;
            }

            Log.d(
                TAG,
                "getActualCameraBounds FILL_CENTER: container=" +
                    containerWidth +
                    "x" +
                    containerHeight +
                    ", camera=" +
                    cameraWidth +
                    "x" +
                    cameraHeight +
                    " (portrait=" +
                    isPortrait +
                    ")" +
                    ", scale=" +
                    scale +
                    ", scaled=" +
                    scaledWidth +
                    "x" +
                    scaledHeight +
                    ", excess=" +
                    excessWidth +
                    "x" +
                    excessHeight +
                    ", adjusted=" +
                    adjustedWidth +
                    "x" +
                    adjustedHeight +
                    ", ratio=" +
                    aspectRatio
            );

            // Return slightly inset bounds for 4:3 to avoid blue line
            if ("4:3".equals(aspectRatio)) {
                return new Rect(1, 1, adjustedWidth + 1, adjustedHeight + 1);
            } else {
                return new Rect(0, 0, containerWidth, containerHeight);
            }
        }

        // For FIT_CENTER (no aspect ratio), calculate letterboxing
        float widthScale = (float) containerWidth / cameraWidth;
        float heightScale = (float) containerHeight / cameraHeight;
        float scale = Math.min(widthScale, heightScale);

        // Calculate the actual size of the camera content after scaling
        int scaledWidth = Math.round(cameraWidth * scale);
        int scaledHeight = Math.round(cameraHeight * scale);

        // Calculate the offset to center the content
        int offsetX = (containerWidth - scaledWidth) / 2;
        int offsetY = (containerHeight - scaledHeight) / 2;

        Log.d(
            TAG,
            "getActualCameraBounds FIT_CENTER: container=" +
                containerWidth +
                "x" +
                containerHeight +
                ", camera=" +
                cameraWidth +
                "x" +
                cameraHeight +
                " (swapped=" +
                isPortrait +
                ")" +
                ", scale=" +
                scale +
                ", scaled=" +
                scaledWidth +
                "x" +
                scaledHeight +
                ", offset=(" +
                offsetX +
                "," +
                offsetY +
                ")"
        );

        // Return the bounds relative to the container
        return new Rect(
            Math.max(0, offsetX),
            Math.max(0, offsetY),
            Math.min(containerWidth, offsetX + scaledWidth),
            Math.min(containerHeight, offsetY + scaledHeight)
        );
    }

    public int getPreviewWidth() {
        if (previewContainer == null) return 0;
        Rect bounds = getActualCameraBounds();
        return bounds.width();
    }

    public int getPreviewHeight() {
        if (previewContainer == null) return 0;
        Rect bounds = getActualCameraBounds();
        return bounds.height();
    }

    public void setPreviewSize(int x, int y, int width, int height) {
        setPreviewSize(x, y, width, height, null);
    }

    public void setPreviewSize(int x, int y, int width, int height, Runnable callback) {
        if (previewContainer == null) {
            if (callback != null) callback.run();
            return;
        }

        // Ensure this runs on the main UI thread
        mainExecutor.execute(() -> {
            ViewGroup.LayoutParams layoutParams = previewContainer.getLayoutParams();
            if (layoutParams instanceof ViewGroup.MarginLayoutParams) {
                ViewGroup.MarginLayoutParams params = (ViewGroup.MarginLayoutParams) layoutParams;

                // Only add insets for positioning coordinates, not for full-screen sizes
                int webViewTopInset = getWebViewTopInset();
                int webViewLeftInset = getWebViewLeftInset();

                // Handle positioning - preserve current values if new values are not specified (negative)
                if (x >= 0) {
                    // Don't add insets if this looks like a calculated full-screen coordinate (x=0, y=0)
                    if (x == 0 && y == 0) {
                        params.leftMargin = x;
                        Log.d(TAG, "setPreviewSize: Full-screen mode - keeping x=0 without insets");
                    } else {
                        params.leftMargin = x + webViewLeftInset;
                        Log.d(
                            TAG,
                            "setPreviewSize: Positioned mode - x=" + x + " + inset=" + webViewLeftInset + " = " + (x + webViewLeftInset)
                        );
                    }
                }
                if (y >= 0) {
                    // Don't add insets if this looks like a calculated full-screen coordinate (x=0, y=0)
                    if (x == 0 && y == 0) {
                        params.topMargin = y;
                        Log.d(TAG, "setPreviewSize: Full-screen mode - keeping y=0 without insets");
                    } else {
                        params.topMargin = y + webViewTopInset;
                        Log.d(
                            TAG,
                            "setPreviewSize: Positioned mode - y=" + y + " + inset=" + webViewTopInset + " = " + (y + webViewTopInset)
                        );
                    }
                }
                if (width > 0) params.width = width;
                if (height > 0) params.height = height;

                previewContainer.setLayoutParams(params);
                previewContainer.requestLayout();

                Log.d(
                    TAG,
                    "setPreviewSize: Updated to " +
                        params.width +
                        "x" +
                        params.height +
                        " at (" +
                        params.leftMargin +
                        "," +
                        params.topMargin +
                        ")"
                );

                // Update session config to reflect actual layout
                if (sessionConfig != null) {
                    String currentAspectRatio = sessionConfig.getAspectRatio();

                    // Calculate aspect ratio from actual dimensions if both width and height are provided
                    String calculatedAspectRatio = currentAspectRatio;
                    if (params.width > 0 && params.height > 0) {
                        // Always use larger dimension / smaller dimension for consistent comparison
                        float ratio = Math.max(params.width, params.height) / (float) Math.min(params.width, params.height);
                        // Standard ratios: 16:9 ≈ 1.778, 4:3 ≈ 1.333
                        float ratio16_9 = 16f / 9f; // 1.778
                        float ratio4_3 = 4f / 3f; // 1.333

                        // Determine closest standard aspect ratio
                        if (Math.abs(ratio - ratio16_9) < Math.abs(ratio - ratio4_3)) {
                            calculatedAspectRatio = "16:9";
                        } else {
                            calculatedAspectRatio = "4:3";
                        }
                        Log.d(
                            TAG,
                            "setPreviewSize: Calculated aspect ratio from " +
                                params.width +
                                "x" +
                                params.height +
                                " = " +
                                calculatedAspectRatio +
                                " (normalized ratio=" +
                                ratio +
                                ")"
                        );
                    }

                    sessionConfig = new CameraSessionConfiguration(
                        sessionConfig.getDeviceId(),
                        sessionConfig.getPosition(),
                        params.leftMargin,
                        params.topMargin,
                        params.width,
                        params.height,
                        sessionConfig.getPaddingBottom(),
                        sessionConfig.getToBack(),
                        sessionConfig.getStoreToFile(),
                        sessionConfig.getEnableOpacity(),
                        sessionConfig.getDisableExifHeaderStripping(),
                        sessionConfig.getDisableAudio(),
                        sessionConfig.getZoomFactor(),
                        calculatedAspectRatio,
                        sessionConfig.getGridMode(),
                        sessionConfig.getDisableFocusIndicator(),
                        sessionConfig.isVideoModeEnabled()
                    );

                    // If aspect ratio changed due to size update, rebind camera
                    if (isRunning && !Objects.equals(currentAspectRatio, calculatedAspectRatio)) {
                        Log.d(
                            TAG,
                            "setPreviewSize: Aspect ratio changed from " +
                                currentAspectRatio +
                                " to " +
                                calculatedAspectRatio +
                                ", rebinding camera"
                        );
                        bindCameraUseCases();

                        // Wait for camera rebinding to complete, then call callback
                        if (callback != null) {
                            previewContainer.post(() -> {
                                updateGridOverlayBounds();
                                previewContainer.post(callback);
                            });
                        } else {
                            previewContainer.post(this::updateGridOverlayBounds);
                        }
                    } else {
                        // No camera rebinding needed, wait for layout to complete then call callback
                        previewContainer.post(() -> {
                            updateGridOverlayBounds();
                            if (callback != null) {
                                callback.run();
                            }
                        });
                    }
                } else {
                    // No sessionConfig, just wait for layout then call callback
                    previewContainer.post(() -> {
                        updateGridOverlayBounds();
                        if (callback != null) {
                            callback.run();
                        }
                    });
                }
            } else {
                Log.w(TAG, "setPreviewSize: Cannot set margins on layout params of type " + layoutParams.getClass().getSimpleName());
                // Fallback: just set width and height if specified
                if (width > 0) layoutParams.width = width;
                if (height > 0) layoutParams.height = height;
                previewContainer.setLayoutParams(layoutParams);
                previewContainer.requestLayout();

                // Wait for layout then call callback
                if (callback != null) {
                    previewContainer.post(callback);
                }
            }
        });
    }

    private void updatePreviewLayoutForAspectRatio(String aspectRatio) {
        if (previewContainer == null || aspectRatio == null) return;

        Log.d(TAG, "======================== UPDATE PREVIEW LAYOUT FOR ASPECT RATIO ========================");
        Log.d(TAG, "Input parameters - aspectRatio: " + aspectRatio);

        // Get comprehensive display information
        WindowManager windowManager = (WindowManager) this.context.getSystemService(Context.WINDOW_SERVICE);
        int screenWidthPx, screenHeightPx;
        float density;

        // Get density using DisplayMetrics (available on all API levels)
        DisplayMetrics displayMetrics = new DisplayMetrics();
        windowManager.getDefaultDisplay().getMetrics(displayMetrics);
        density = displayMetrics.density;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+ (Android 11+) - use WindowMetrics for screen dimensions
            WindowMetrics metrics = windowManager.getCurrentWindowMetrics();
            Rect bounds = metrics.getBounds();
            screenWidthPx = bounds.width();
            screenHeightPx = bounds.height();
        } else {
            // API < 30 - use legacy DisplayMetrics for screen dimensions
            screenWidthPx = displayMetrics.widthPixels;
            screenHeightPx = displayMetrics.heightPixels;
        }

        // Get WebView dimensions
        int webViewWidth = webView.getWidth();
        int webViewHeight = webView.getHeight();

        // Get current preview container info
        ViewGroup.LayoutParams currentParams = previewContainer.getLayoutParams();
        int currentWidth = currentParams != null ? currentParams.width : 0;
        int currentHeight = currentParams != null ? currentParams.height : 0;
        int currentX = 0;
        int currentY = 0;
        if (currentParams instanceof ViewGroup.MarginLayoutParams) {
            ViewGroup.MarginLayoutParams marginParams = (ViewGroup.MarginLayoutParams) currentParams;
            currentX = marginParams.leftMargin;
            currentY = marginParams.topMargin;
        }

        Log.d(TAG, "Screen dimensions: " + screenWidthPx + "x" + screenHeightPx + " pixels, density: " + density);
        Log.d(TAG, "WebView dimensions: " + webViewWidth + "x" + webViewHeight);
        Log.d(TAG, "Current preview position: " + currentX + "," + currentY + " size: " + currentWidth + "x" + currentHeight);

        // Parse aspect ratio as width:height (e.g., 4:3 -> r=4/3)
        String[] ratios = aspectRatio.split(":");
        if (ratios.length != 2) {
            Log.e(TAG, "Invalid aspect ratio format: " + aspectRatio);
            return;
        }

        try {
            // Match iOS logic exactly
            double ratioWidth = Double.parseDouble(ratios[0]);
            double ratioHeight = Double.parseDouble(ratios[1]);
            boolean isPortrait = context.getResources().getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;

            Log.d(TAG, "Aspect ratio parsing - Original: " + aspectRatio + " (width=" + ratioWidth + ", height=" + ratioHeight + ")");
            Log.d(TAG, "Device orientation: " + (isPortrait ? "PORTRAIT" : "LANDSCAPE"));

            // iOS: let ratio = !isPortrait ? ratioParts[0] / ratioParts[1] : ratioParts[1] / ratioParts[0]
            double ratio = !isPortrait ? (ratioWidth / ratioHeight) : (ratioHeight / ratioWidth);

            Log.d(TAG, "Computed ratio: " + ratio + " (iOS formula: " + (!isPortrait ? "width/height" : "height/width") + ")");

            // Get available space from webview dimensions

            Log.d(TAG, "Available space from WebView: " + webViewWidth + "x" + webViewHeight);

            // Calculate position and size
            int finalX, finalY, finalWidth, finalHeight;
            // Auto-center mode - match iOS behavior exactly
            Log.d(TAG, "Auto-center mode");

            // Calculate maximum size that fits the aspect ratio in available space
            double maxWidthByHeight = webViewHeight * ratio;
            double maxHeightByWidth = webViewWidth / ratio;

            Log.d(TAG, "Aspect ratio calculations - maxWidthByHeight: " + maxWidthByHeight + ", maxHeightByWidth: " + maxHeightByWidth);

            if (maxWidthByHeight <= webViewWidth) {
                // Height is the limiting factor
                finalWidth = (int) maxWidthByHeight;
                finalHeight = webViewHeight;
                Log.d(TAG, "Height-limited sizing: " + finalWidth + "x" + finalHeight);
            } else {
                // Width is the limiting factor
                finalWidth = webViewWidth;
                finalHeight = (int) maxHeightByWidth;
                Log.d(TAG, "Width-limited sizing: " + finalWidth + "x" + finalHeight);
            }

            // Center the preview
            finalX = (webViewWidth - finalWidth) / 2;
            finalY = (webViewHeight - finalHeight) / 2;

            Log.d(
                TAG,
                "Auto-center mode: calculated size " + finalWidth + "x" + finalHeight + " at position (" + finalX + ", " + finalY + ")"
            );

            Log.d(TAG, "Final calculated layout - Position: (" + finalX + "," + finalY + "), Size: " + finalWidth + "x" + finalHeight);

            // Calculate and log the actual displayed aspect ratio
            double displayedRatio = (double) finalWidth / (double) finalHeight;
            Log.d(TAG, "Displayed aspect ratio: " + displayedRatio + " (width=" + finalWidth + ", height=" + finalHeight + ")");

            // Compare with expected ratio based on orientation
            String[] parts = aspectRatio.split(":");
            if (parts.length == 2) {
                double expectedDisplayRatio = isPortrait ? (ratioHeight / ratioWidth) : (ratioWidth / ratioHeight);
                double difference = Math.abs(displayedRatio - expectedDisplayRatio);
                Log.d(
                    TAG,
                    "Display ratio check - Expected: " +
                        expectedDisplayRatio +
                        ", Actual: " +
                        displayedRatio +
                        ", Difference: " +
                        difference +
                        " (tolerance should be < 0.01)"
                );
            }

            // Update layout params
            ViewGroup.LayoutParams layoutParams = previewContainer.getLayoutParams();
            if (layoutParams instanceof ViewGroup.MarginLayoutParams) {
                ViewGroup.MarginLayoutParams params = (ViewGroup.MarginLayoutParams) layoutParams;
                params.width = finalWidth;
                params.height = finalHeight;
                params.leftMargin = finalX;
                params.topMargin = finalY;
                previewContainer.setLayoutParams(params);
                previewContainer.requestLayout();

                Log.d(TAG, "Layout params applied successfully");

                // Update grid overlay bounds after aspect ratio change
                previewContainer.post(() -> {
                    Log.d(
                        TAG,
                        "Post-layout verification - Actual position: " +
                            previewContainer.getLeft() +
                            "," +
                            previewContainer.getTop() +
                            ", Actual size: " +
                            previewContainer.getWidth() +
                            "x" +
                            previewContainer.getHeight()
                    );
                    updateGridOverlayBounds();
                });
            }
        } catch (NumberFormatException e) {
            Log.e(TAG, "Invalid aspect ratio format: " + aspectRatio, e);
        }

        Log.d(TAG, "========================================================================================");
    }

    private int getWebViewTopInset() {
        try {
            if (webView != null) {
                // Get the actual WebView position on screen
                int[] location = new int[2];
                webView.getLocationOnScreen(location);
                return location[1]; // Y position is the top inset
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to get WebView top inset", e);
        }
        return 0;
    }

    private int getWebViewLeftInset() {
        try {
            if (webView != null) {
                // Get the actual WebView position on screen for consistency
                int[] location = new int[2];
                webView.getLocationOnScreen(location);
                return location[0]; // X position is the left inset
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to get WebView left inset", e);
        }
        return 0;
    }

    /**
     * Get the current preview position and size in DP units (without insets)
     */
    public int[] getCurrentPreviewBounds() {
        if (previewContainer == null) {
            return new int[] { 0, 0, 0, 0 }; // x, y, width, height
        }

        // Get actual camera preview bounds (accounts for letterboxing/pillarboxing)
        int actualX = getPreviewX();
        int actualY = getPreviewY();
        int actualWidth = getPreviewWidth();
        int actualHeight = getPreviewHeight();

        // Convert to logical pixels for JavaScript
        DisplayMetrics metrics = context.getResources().getDisplayMetrics();
        float pixelRatio = metrics.density;

        // Remove WebView insets from coordinates
        int webViewTopInset = getWebViewTopInset();
        int webViewLeftInset = getWebViewLeftInset();

        // Use proper rounding strategy to avoid gaps:
        // - For positions (x, y): floor to avoid gaps at top/left
        // - For dimensions (width, height): ceil to avoid gaps at bottom/right
        int x = Math.max(0, (int) Math.ceil((actualX - webViewLeftInset) / pixelRatio));
        int y = Math.max(0, (int) Math.ceil((actualY - webViewTopInset) / pixelRatio));
        int width = (int) Math.floor(actualWidth / pixelRatio);
        int height = (int) Math.floor(actualHeight / pixelRatio);

        // Debug logging to understand the blue line issue
        Log.d(
            TAG,
            "getCurrentPreviewBounds DEBUG: " +
                "actualBounds=(" +
                actualX +
                "," +
                actualY +
                "," +
                actualWidth +
                "x" +
                actualHeight +
                "), " +
                "logicalBounds=(" +
                x +
                "," +
                y +
                "," +
                width +
                "x" +
                height +
                "), " +
                "pixelRatio=" +
                pixelRatio +
                ", " +
                "insets=(" +
                webViewLeftInset +
                "," +
                webViewTopInset +
                ")"
        );

        return new int[] { x, y, width, height };
    }

    private void updateGridOverlayBounds() {
        if (gridOverlayView != null && previewView != null) {
            // Get the actual camera bounds
            Rect cameraBounds = getActualCameraBounds();

            // Update the grid overlay with the camera bounds
            gridOverlayView.setCameraBounds(cameraBounds);

            Log.d(TAG, "updateGridOverlayBounds: Updated grid bounds to " + cameraBounds);
        }
    }

    /** @noinspection ResultOfMethodCallIgnored*/
    public void startRecordVideo() throws Exception {
        if (videoCapture == null) {
            throw new Exception("VideoCapture is not initialized");
        }

        if (currentRecording != null) {
            throw new Exception("Video recording is already in progress");
        }

        // Create output file
        String fileName = "video_" + System.currentTimeMillis() + ".mp4";
        File outputDir = new File(context.getExternalFilesDir(Environment.DIRECTORY_MOVIES), "CameraPreview");
        if (!outputDir.exists()) {
            outputDir.mkdirs();
        }
        currentVideoFile = new File(outputDir, fileName);

        FileOutputOptions outputOptions = new FileOutputOptions.Builder(currentVideoFile).build();

        // Create recording event listener
        androidx.core.util.Consumer<VideoRecordEvent> videoRecordEventListener = (videoRecordEvent) -> {
            if (videoRecordEvent instanceof VideoRecordEvent.Start) {
                Log.d(TAG, "Video recording started");
            } else if (videoRecordEvent instanceof VideoRecordEvent.Finalize) {
                VideoRecordEvent.Finalize finalizeEvent = (VideoRecordEvent.Finalize) videoRecordEvent;
                handleRecordingFinalized(finalizeEvent);
            }
        };

        // Start recording
        if (sessionConfig != null && !sessionConfig.isDisableAudio()) {
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                return;
            }
            currentRecording = videoCapture
                .getOutput()
                .prepareRecording(context, outputOptions)
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(context), videoRecordEventListener);
        } else {
            currentRecording = videoCapture
                .getOutput()
                .prepareRecording(context, outputOptions)
                .start(ContextCompat.getMainExecutor(context), videoRecordEventListener);
        }

        Log.d(TAG, "Video recording started to: " + currentVideoFile.getAbsolutePath());
    }

    public void stopRecordVideo(VideoRecordingCallback callback) {
        if (currentRecording == null) {
            callback.onError("No video recording in progress");
            return;
        }

        // Store the callback to use when recording is finalized
        currentVideoCallback = callback;
        currentRecording.stop();

        Log.d(TAG, "Video recording stop requested");
    }

    private void handleRecordingFinalized(VideoRecordEvent.Finalize finalizeEvent) {
        if (!finalizeEvent.hasError()) {
            Log.d(TAG, "Video recording completed successfully");
            if (currentVideoCallback != null) {
                String filePath = "file://" + currentVideoFile.getAbsolutePath();
                currentVideoCallback.onSuccess(filePath);
            }
        } else {
            Log.e(TAG, "Video recording failed: " + finalizeEvent.getError());
            if (currentVideoCallback != null) {
                currentVideoCallback.onError("Video recording failed: " + finalizeEvent.getError());
            }
        }

        // Clean up
        currentRecording = null;
        currentVideoFile = null;
        currentVideoCallback = null;
    }

    // ========================================
    // Face Detection Methods
    // ========================================

    public void enableFaceDetection(FaceDetectionManager manager) {
        this.faceDetectionManager = manager;

        // Create ImageAnalysis use case if not exists
        if (imageAnalysis == null) {
            imageAnalysis = new androidx.camera.core.ImageAnalysis.Builder()
                .setBackpressureStrategy(androidx.camera.core.ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build();

            imageAnalysis.setAnalyzer(cameraExecutor, (imageProxy) -> {
                if (faceDetectionManager != null && faceDetectionManager.isRunning()) {
                    faceDetectionManager.processImageProxy(imageProxy);
                } else {
                    imageProxy.close();
                }
            });
        }

        // Rebind camera with ImageAnalysis
        rebindCameraWithAnalysis();
    }

    public void disableFaceDetection() {
        this.faceDetectionManager = null;
        if (imageAnalysis != null) {
            imageAnalysis.clearAnalyzer();
        }
        // Rebind camera without ImageAnalysis
        rebindCameraWithoutAnalysis();
    }

    /**
     * Helper method to create a Preview with the same configuration as bindCameraUseCases().
     * This ensures consistent preview behavior when rebinding camera with/without face detection.
     */
    private Preview createConfiguredPreview() {
        ResolutionSelector.Builder resolutionSelectorBuilder = new ResolutionSelector.Builder().setResolutionStrategy(
            // For face detection, use 720p (1280x720) as optimal balance
            new ResolutionStrategy(
                new Size(1280, 720), // Target 720p
                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
            )
        );

        if (sessionConfig.getAspectRatio() != null) {
            int aspectRatio;
            if ("16:9".equals(sessionConfig.getAspectRatio())) {
                aspectRatio = AspectRatio.RATIO_16_9;
            } else {
                // "4:3"
                aspectRatio = AspectRatio.RATIO_4_3;
            }
            resolutionSelectorBuilder.setAspectRatioStrategy(new AspectRatioStrategy(aspectRatio, AspectRatioStrategy.FALLBACK_RULE_AUTO));
        }

        ResolutionSelector resolutionSelector = resolutionSelectorBuilder.build();

        int rotation = previewView != null && previewView.getDisplay() != null
            ? previewView.getDisplay().getRotation()
            : android.view.Surface.ROTATION_0;

        // Configure preview with optimized frame rate for face detection (20-25 FPS)
        return new Preview.Builder()
            .setResolutionSelector(resolutionSelector)
            .setTargetRotation(rotation)
            .setTargetFrameRate(new Range<>(20, 25)) // 20-25 FPS for balanced performance
            .build();
    }

    private void rebindCameraWithAnalysis() {
        if (cameraProvider == null || !isRunning) {
            return;
        }

        try {
            // Unbind all
            cameraProvider.unbindAll();

            // Rebuild preview with proper configuration
            Preview preview = createConfiguredPreview();
            preview.setSurfaceProvider(previewView.getSurfaceProvider());

            // Bind with ImageAnalysis
            List<androidx.camera.core.UseCase> useCases = new ArrayList<>();
            useCases.add(preview);
            if (imageCapture != null) {
                useCases.add(imageCapture);
            }
            if (videoCapture != null && sessionConfig.isVideoModeEnabled()) {
                useCases.add(videoCapture);
            }
            if (imageAnalysis != null) {
                useCases.add(imageAnalysis);
            }

            camera = cameraProvider.bindToLifecycle(this, currentCameraSelector, useCases.toArray(new androidx.camera.core.UseCase[0]));

            Log.d(TAG, "Camera rebound with face detection enabled");
        } catch (Exception e) {
            Log.e(TAG, "Failed to rebind camera with analysis", e);
        }
    }

    private void rebindCameraWithoutAnalysis() {
        if (cameraProvider == null || !isRunning) {
            return;
        }

        try {
            // Unbind all
            cameraProvider.unbindAll();

            // Rebuild preview with proper configuration
            Preview preview = createConfiguredPreview();
            preview.setSurfaceProvider(previewView.getSurfaceProvider());

            // Bind without ImageAnalysis
            List<androidx.camera.core.UseCase> useCases = new ArrayList<>();
            useCases.add(preview);
            if (imageCapture != null) {
                useCases.add(imageCapture);
            }
            if (videoCapture != null && sessionConfig.isVideoModeEnabled()) {
                useCases.add(videoCapture);
            }

            camera = cameraProvider.bindToLifecycle(this, currentCameraSelector, useCases.toArray(new androidx.camera.core.UseCase[0]));

            Log.d(TAG, "Camera rebound with face detection disabled");
        } catch (Exception e) {
            Log.e(TAG, "Failed to rebind camera without analysis", e);
        }
    }
}
