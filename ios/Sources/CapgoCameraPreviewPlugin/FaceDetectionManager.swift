import AVFoundation
import Vision
import UIKit

/// Protocol for communicating face detection results back to the plugin
protocol FaceDetectionDelegate: AnyObject {
    func faceDetectionDidUpdate(result: FaceDetectionResult)
    func faceDetectionDidFail(error: Error)
}

/// Manages real-time face detection using Apple's Vision framework
class FaceDetectionManager: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: FaceDetectionDelegate?
    
    private var isDetecting = false
    private var detectionOptions: FaceDetectionOptions
    private var sequenceHandler = VNSequenceRequestHandler()
    private var lastProcessTime: TimeInterval = 0
    private let processingThrottle: TimeInterval = 0.0 // No throttle for real-time tracking
    
    /// Background queue for async face detection processing (high priority for real-time tracking)
    private let detectionQueue = DispatchQueue(label: "com.capgo.camera.facedetection", qos: .userInteractive)
    
    /// Serial queue for result handling to prevent race conditions
    private let resultQueue = DispatchQueue(label: "com.capgo.camera.facedetection.results", qos: .userInteractive)
    
    /// Cancellation flag for stopping detection mid-processing
    private var isCancelled = false
    
    /// Counter for in-flight requests to ensure safe shutdown
    private var processingCount = 0
    private let processingCountLock = NSLock()
    
    // MARK: - Power & Thermal Management
    
    /// Frame skipping for power efficiency (process every Nth frame)
    private var frameSkipCount: Int = 1 // Process every 2nd frame for better real-time tracking
    private var currentFrameCount: Int = 0
    
    /// Motion detection to skip static frames (disabled for face tracking to avoid delays)
    private var motionDetectionEnabled: Bool = false
    private var lastProcessedBuffer: CMSampleBuffer?
    private var lastMotionCheckTime: TimeInterval = 0
    private let motionCheckInterval: TimeInterval = 0.1 // 100ms
    
    /// App lifecycle state
    private var isAppInBackground: Bool = false
    
    /// Thermal throttling state
    private var isThermalThrottling: Bool = false
    
    /// Frame dimensions for coordinate normalization
    private var currentFrameWidth: CGFloat = 0
    private var currentFrameHeight: CGFloat = 0
    
    /// Dictionary to track face IDs across frames
    private var faceTrackingMap: [UUID: Int] = [:]
    private var nextTrackingId: Int = 1
    
    // MARK: - Initialization
    
    init(options: FaceDetectionOptions = FaceDetectionOptions()) {
        self.detectionOptions = options
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start face detection with the given options.
    ///
    /// Begins face detection using the provided configuration.
    /// - Parameter options: Configuration that controls detection behavior (performance mode, tracking, landmarks, max faces, min face size). Marks the manager as active and clears any prior cancellation state.
    func start(options: FaceDetectionOptions) {
        self.detectionOptions = options
        self.isCancelled = false
        self.isDetecting = true
        print("[FaceDetection] Started with options: \(options)")
    }
    
    /// Stop face detection and release resources.
    /// Stops face detection, cancels any ongoing work, and resets tracking state.
    /// 
    /// Sets the manager to not detecting and marks cancellation; waits up to 0.5 seconds for in-flight requests to finish, then clears the face tracking map and resets the next tracking identifier. Logs the number of requests still processing after the wait.
    func stop() {
        self.isDetecting = false
        self.isCancelled = true
        
        // Wait briefly for in-flight requests to complete
        let maxWaitTime = 0.5 // 500ms max wait
        let startTime = CACurrentMediaTime()
        while processingCount > 0 && (CACurrentMediaTime() - startTime) < maxWaitTime {
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        self.faceTrackingMap.removeAll()
        self.nextTrackingId = 1
        print("[FaceDetection] Stopped (\(processingCount) requests still processing)")
    }
    
    /// Check if face detection is currently active.
    ///
    /// Reports whether the face detection manager is currently active.
    /// - Returns: `true` if detection is active, `false` otherwise.
    func isRunning() -> Bool {
        return isDetecting
    }
    
    /// Process a camera frame for face detection.
    /// Applies frame skipping, motion detection, and power/thermal management.
    ///
    /// Processes an incoming video sample buffer and enqueues a Vision face detection request when processing criteria are met.
    /// 
    /// The method applies runtime checks (detection state, app background, thermal throttling), power controls (frame skipping, motion-based skipping) and rate limiting before extracting the pixel buffer and scheduling asynchronous face detection on the internal detection queue. It updates in-flight processing counters and frame dimensions used for coordinate normalization. If face detection fails while not cancelled, the delegate is notified on the main thread.
    /// - Parameter sampleBuffer: A CMSampleBuffer containing the video frame to analyze for faces.
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isDetecting, !isCancelled else { return }
        
        // Skip if app is in background
        guard !isAppInBackground else { return }
        
        // Skip if thermal throttling is active
        guard !isThermalThrottling else { return }
        
        // Frame skipping for power saving (process every Nth frame)
        currentFrameCount += 1
        guard currentFrameCount % (frameSkipCount + 1) == 0 else { return }
        
        // Throttle processing to avoid overwhelming the CPU
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastProcessTime >= processingThrottle else { return }
        
        // Motion detection: skip if no significant change from last frame
        if motionDetectionEnabled && currentTime - lastMotionCheckTime > motionCheckInterval {
            guard hasSignificantMotion(sampleBuffer) else { return }
            lastMotionCheckTime = currentTime
        }
        
        lastProcessTime = currentTime
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[FaceDetection] Failed to get pixel buffer")
            return
        }
        
        // Store frame dimensions
        let frameWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let frameHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        // Increment processing counter
        processingCountLock.lock()
        processingCount += 1
        processingCountLock.unlock()
        
        // Process asynchronously on background queue
        detectionQueue.async { [weak self] in
            guard let self = self, !self.isCancelled else {
                self?.decrementProcessingCount()
                return
            }
            
            // Store frame dimensions for coordinate normalization
            self.currentFrameWidth = frameWidth
            self.currentFrameHeight = frameHeight
            
            // Create face detection request
            let request = self.createFaceDetectionRequest()
            
            // Process the frame
            do {
                try self.sequenceHandler.perform([request], on: pixelBuffer)
            } catch {
                print("[FaceDetection] Failed to perform face detection: \(error)")
                if !self.isCancelled {
                    DispatchQueue.main.async {
                        self.delegate?.faceDetectionDidFail(error: error)
                    }
                }
            }
            
            self.decrementProcessingCount()
        }
    }
    
    // MARK: - Private Methods
    
    /// Create a Vision face detection request configured for real-time performance.
    ///
    /// Creates a VNDetectFaceLandmarksRequest configured for real-time detection and result handling.
    /// 
    /// The request's completion handler forwards any error to the delegate via `faceDetectionDidFail(error:)` and passes successful face observations to `handleDetectionResults(_:)`. The request is tuned for minimal latency and, when available, to prefer GPU acceleration.
    /// - Returns: A configured `VNDetectFaceLandmarksRequest` whose completion handler handles errors and delivers `VNFaceObservation` results.
    private func createFaceDetectionRequest() -> VNDetectFaceLandmarksRequest {
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[FaceDetection] Detection error: \(error)")
                self.delegate?.faceDetectionDidFail(error: error)
                return
            }
            
            self.handleDetectionResults(request.results as? [VNFaceObservation] ?? [])
        }
        
        // Configure request for optimal real-time performance
        if #available(iOS 12.0, *) {
            // Use fastest revision for minimal latency
            request.revision = VNDetectFaceLandmarksRequestRevision2
        }
        
        // Enable tracking for smoother results
        if #available(iOS 14.0, *) {
            request.usesCPUOnly = false // Use GPU acceleration when available
        }
        
        return request
    }
    
    /// Handle Vision face detection results and notify delegate.
    ///
    /// Processes Vision face observations, converts them to `DetectedFace` results, and delivers a `FaceDetectionResult` to the delegate on the main thread.
    /// - Parameters:
    ///   - observations: Array of `VNFaceObservation` produced by a Vision request. The observations are limited to `detectionOptions.maxFaces` and filtered by `detectionOptions.minFaceSize` before conversion.
    ///
    /// This method exits immediately if detection has been cancelled. Results are processed on `resultQueue` to avoid races; the final `FaceDetectionResult` includes the current frame dimensions and a millisecond timestamp and is dispatched to the delegate on the main thread.
    private func handleDetectionResults(_ observations: [VNFaceObservation]) {
        // Check cancellation before processing results
        guard !isCancelled else { return }
        
        // Process results on result queue to prevent race conditions
        resultQueue.async { [weak self] in
            guard let self = self, !self.isCancelled else { return }
            
            // Limit to maxFaces
            let limitedObservations = Array(observations.prefix(self.detectionOptions.maxFaces))
            
            // Filter by minimum face size
            let filteredObservations = limitedObservations.filter { observation in
                let faceWidth = observation.boundingBox.width
                return faceWidth >= self.detectionOptions.minFaceSize
            }
            
            // Convert observations to DetectedFace objects
            let detectedFaces = filteredObservations.map { observation in
                self.convertToDetectedFace(observation)
            }
            
            // Create result
            let result = FaceDetectionResult(
                faces: detectedFaces,
                frameWidth: Int(self.currentFrameWidth),
                frameHeight: Int(self.currentFrameHeight),
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
            
            // Notify delegate on main thread
            if !self.isCancelled {
                DispatchQueue.main.async {
                    self.delegate?.faceDetectionDidUpdate(result: result)
                }
            }
        }
    }
    
    /// Convert a VNFaceObservation to a DetectedFace data model.
    ///
    /// - Parameter observation: VNFaceObservation from Vision.
    /// Converts a `VNFaceObservation` into the module's `DetectedFace` model.
    /// - Parameter observation: The Vision face observation to convert.
    /// - Returns: A `DetectedFace` containing a top-left-origin `bounds`, optional `trackingId` (when tracking is enabled), face rotation angles in degrees (`rollAngle`, `yawAngle`, `pitchAngle`), and optional `landmarks` if landmark detection is enabled. The `pitchAngle` uses `observation.pitch` when available; otherwise it is estimated from landmarks.
    private func convertToDetectedFace(_ observation: VNFaceObservation) -> DetectedFace {
        // Get or create tracking ID
        let trackingId = detectionOptions.trackingEnabled ? getTrackingId(for: observation) : nil
        
        // Convert bounding box from Vision's bottom-left origin to top-left origin
        let bounds = FaceBounds(
            x: observation.boundingBox.origin.x,
            y: 1.0 - observation.boundingBox.origin.y - observation.boundingBox.height,
            width: observation.boundingBox.width,
            height: observation.boundingBox.height
        )
        
        // Extract rotation angles
        let rollAngle = observation.roll?.doubleValue ?? 0.0
        let yawAngle = observation.yaw?.doubleValue ?? 0.0
        let pitchAngle: Double
        if #available(iOS 15.0, *) {
            pitchAngle = observation.pitch?.doubleValue ?? 0.0
        } else {
            // Estimate pitch from facial landmarks for pre-iOS 15
            pitchAngle = estimatePitchFromLandmarks(observation)
        }
        
        // Extract landmarks if requested
        var landmarks: FaceLandmarks? = nil
        if detectionOptions.detectLandmarks, let faceLandmarks = observation.landmarks {
            landmarks = extractLandmarks(faceLandmarks, boundingBox: observation.boundingBox)
        }
        
        return DetectedFace(
            trackingId: trackingId,
            bounds: bounds,
            rollAngle: radiansToDegrees(rollAngle),
            yawAngle: radiansToDegrees(yawAngle),
            pitchAngle: radiansToDegrees(pitchAngle),
            landmarks: landmarks,
            smilingProbability: nil, // Not available on iOS without custom ML model
            leftEyeOpenProbability: nil,
            rightEyeOpenProbability: nil
        )
    }
    
    /// Extract facial landmarks from Vision's VNFaceLandmarks2D as normalized coordinates.
    ///
    /// - Parameters:
    ///   - faceLandmarks: VNFaceLandmarks2D object.
    ///   - boundingBox: Bounding box for normalization.
    /// Converts a VNFaceLandmarks2D into a FaceLandmarks structure with points expressed in normalized image coordinates (origin at the top-left).
    /// - Parameters:
    ///   - faceLandmarks: Vision landmarks for a detected face.
    ///   - boundingBox: The face bounding box (normalized coordinates with origin at bottom-left in Vision) used to map landmark points into image space.
    /// - Returns: A FaceLandmarks object where each point, if present, is normalized to image coordinates (x and y between 0 and 1) with (0,0) at the top-left.
    private func extractLandmarks(_ faceLandmarks: VNFaceLandmarks2D, boundingBox: CGRect) -> FaceLandmarks {
        // Helper to convert landmark point to normalized coordinates
        /// Converts a Vision landmark point (relative to a face bounding box) into normalized image coordinates with a top-left origin.
        /// - Parameters:
        ///   - point: A CGPoint where x and y are relative to the face bounding box (normalized 0–1) as provided by Vision landmarks.
        /// - Returns: A `Point` whose `x` and `y` are normalized image coordinates (0–1) with the origin at the top-left of the image.
        func normalizePoint(_ point: CGPoint) -> Point {
            // Vision landmarks are relative to bounding box
            let x = boundingBox.origin.x + point.x * boundingBox.width
            // Flip Y coordinate (Vision uses bottom-left origin)
            let y = 1.0 - (boundingBox.origin.y + point.y * boundingBox.height)
            return Point(x: x, y: y)
        }
        
        /// Returns the first landmark point from a Vision landmark region converted to image-space normalized coordinates.
        /// - Parameters:
        ///   - region: A `VNFaceLandmarkRegion2D` containing normalized landmark points, or `nil`.
        /// - Returns: The first point converted to `Point`, or `nil` if `region` is `nil` or contains no points.
        func getPoint(from region: VNFaceLandmarkRegion2D?) -> Point? {
            guard let region = region, region.pointCount > 0 else { return nil }
            return normalizePoint(region.normalizedPoints[0])
        }
        
        return FaceLandmarks(
            leftEye: getPoint(from: faceLandmarks.leftEye),
            rightEye: getPoint(from: faceLandmarks.rightEye),
            noseBase: getPoint(from: faceLandmarks.nose),
            mouthLeft: getPoint(from: faceLandmarks.outerLips), // Approximate
            mouthRight: getPoint(from: faceLandmarks.outerLips), // Approximate
            mouthBottom: getPoint(from: faceLandmarks.outerLips), // Approximate
            leftEar: nil, // Not reliably detected by Vision
            rightEar: nil,
            leftCheek: nil, // Not available in Vision
            rightCheek: nil
        )
    }
    
    /// Get or assign a tracking ID for a face observation.
    ///
    /// - Parameter observation: VNFaceObservation to track.
    /// Provide a persistent tracking identifier for a Vision face observation, creating and storing a new ID if the observation is unseen.
    /// - Parameter observation: The `VNFaceObservation` whose `uuid` is used as the tracking key.
    /// - Returns: A unique integer tracking ID associated with the observation.
    private func getTrackingId(for observation: VNFaceObservation) -> Int {
        let uuid = observation.uuid
        if let existingId = faceTrackingMap[uuid] {
            return existingId
        } else {
            let newId = nextTrackingId
            faceTrackingMap[uuid] = newId
            nextTrackingId += 1
            return newId
        }
    }
    
    /// Convert radians to degrees.
    ///
    /// - Parameter radians: Value in radians.
    /// Converts an angle in radians to degrees.
    /// - Parameter radians: Angle in radians.
    /// - Returns: Angle converted to degrees.
    private func radiansToDegrees(_ radians: Double) -> Double {
        return radians * 180.0 / .pi
    }
    
    /// Estimate pitch angle from facial landmarks when observation.pitch is unavailable (iOS < 15).
    ///
    /// - Parameter observation: VNFaceObservation with landmarks.
    /// Estimates the head pitch (rotation around the X-axis) using facial landmarks when Vision's `observation.pitch` is unavailable.
    /// - Parameter observation: A `VNFaceObservation` that contains facial landmarks used for the estimate.
    /// - Returns: The estimated pitch in radians; positive values indicate the face is tilted upward, negative values indicate the face is tilted downward. Returns `0.0` if required landmarks are unavailable.
    private func estimatePitchFromLandmarks(_ observation: VNFaceObservation) -> Double {
        guard let landmarks = observation.landmarks else { return 0.0 }
        
        // Use nose and eye positions to estimate head tilt up/down
        if let nose = landmarks.nose?.normalizedPoints.first,
           let leftEye = landmarks.leftEye?.normalizedPoints.first,
           let rightEye = landmarks.rightEye?.normalizedPoints.first {
            
            // Calculate average eye Y position
            let eyeY = (leftEye.y + rightEye.y) / 2.0
            let noseY = nose.y
            
            // Vertical distance between eyes and nose (relative to face height)
            let verticalDist = noseY - eyeY
            
            // Typical vertical distance when face is straight: ~0.2-0.3
            // When looking down: increases (nose moves down relative to eyes)
            // When looking up: decreases (nose moves up relative to eyes)
            
            // Map to approximate pitch angle in radians
            // Positive pitch = looking up, Negative pitch = looking down
            let estimatedPitch = (0.25 - verticalDist) * 2.0 // Scale factor for sensitivity
            
            return estimatedPitch
        }
        
        return 0.0
    }
    
    /// Decrements the in-flight processing counter in a thread-safe manner.
    /// - Remark: Ensures the counter never becomes negative.
    private func decrementProcessingCount() {
        processingCountLock.lock()
        processingCount = max(0, processingCount - 1)
        processingCountLock.unlock()
    }
    
    // MARK: - Motion Detection
    
    /// Detect if there's significant motion between frames.
    /// Simple implementation using timestamp comparison.
    ///
    /// - Parameter currentBuffer: Current camera frame buffer.
    /// Determines whether the provided sample buffer indicates significant motion compared to the last processed buffer.
    /// - Parameters:
    ///   - currentBuffer: The current CMSampleBuffer to compare against the last processed buffer.
    /// - Returns: `true` if motion is detected or if there is no previous buffer (first frame); `false` if the buffers appear identical based on timestamp comparison (threshold 0.001 seconds).
    private func hasSignificantMotion(_ currentBuffer: CMSampleBuffer) -> Bool {
        defer { lastProcessedBuffer = currentBuffer }
        
        guard let lastBuffer = lastProcessedBuffer else {
            return true // Always process first frame
        }
        
        // Simple motion detection using timestamp comparison
        // More sophisticated: compare pixel data or use optical flow
        let currentTime = CMSampleBufferGetPresentationTimeStamp(currentBuffer)
        let lastTime = CMSampleBufferGetPresentationTimeStamp(lastBuffer)
        
        let timeDiff = CMTimeGetSeconds(CMTimeSubtract(currentTime, lastTime))
        
        // If frames are too close, assume motion (rapid changes)
        // If frames are identical timestamps, no motion
        return timeDiff > 0.001 // Different frames = motion
    }
    
    // MARK: - App Lifecycle Management
    
    /// Marks the manager as backgrounded to pause further frame processing.
    /// Sets the internal `isAppInBackground` flag to `true`, preventing new frames from being processed and logging that detection is paused.
    func onAppBackground() {
        isAppInBackground = true
        print("[FaceDetection] Paused (app backgrounded)")
    }
    
    /// Resume detection when app comes to foreground.
    /// Marks the manager as active when the app returns to the foreground and resets frame counting.
    /// 
    /// Sets the internal `isAppInBackground` flag to `false` and resets `currentFrameCount` to zero to allow immediate processing of incoming frames.
    func onAppForeground() {
        isAppInBackground = false
        currentFrameCount = 0 // Reset frame counter
        print("[FaceDetection] Resumed (app foregrounded)")
    }
    
    // MARK: - Thermal Management
    
    /// Enables thermal throttling for the face detection manager.
    /// 
    /// Sets the internal thermal throttling state so the manager reduces or pauses processing to limit thermal load.
    func enableThermalThrottling() {
        isThermalThrottling = true
        print("[FaceDetection] Thermal throttling enabled")
    }
    
    /// Disables thermal throttling for face detection, allowing normal processing to resume.
    func disableThermalThrottling() {
        isThermalThrottling = false
        print("[FaceDetection] Thermal throttling disabled")
    }
    
    /// Check if thermal throttling is active.
    ///
    /// Indicates whether thermal throttling is currently active.
    /// - Returns: `true` if thermal throttling is active, `false` otherwise.
    func isThermalThrottlingActive() -> Bool {
        return isThermalThrottling
    }
    
    /// Configure power management options for frame skipping and motion detection.
    ///
    /// - Parameters:
    ///   - frameSkip: Number of frames to skip between detections.
    /// Configures power-management settings for frame skipping and motion-based detection.
    /// - Parameters:
    ///   - frameSkip: Number of frames to skip between processing; values less than 0 are clamped to 0.
    ///   - motionDetection: When `true`, enables motion-based skipping to avoid processing static frames.
    func configurePowerManagement(frameSkip: Int = 2, motionDetection: Bool = true) {
        self.frameSkipCount = max(0, frameSkip)
        self.motionDetectionEnabled = motionDetection
        print("[FaceDetection] Power management: frameSkip=\(frameSkipCount), motionDetection=\(motionDetectionEnabled)")
    }
}

// MARK: - Data Models

struct FaceDetectionOptions {
    var performanceMode: String = "fast"
    var trackingEnabled: Bool = true
    var detectLandmarks: Bool = true
    var detectClassifications: Bool = false
    var maxFaces: Int = 3
    var minFaceSize: Double = 0.15
}

struct FaceDetectionResult: Codable {
    let faces: [DetectedFace]
    let frameWidth: Int
    let frameHeight: Int
    let timestamp: Int64
}

struct DetectedFace: Codable {
    let trackingId: Int?
    let bounds: FaceBounds
    let rollAngle: Double?
    let yawAngle: Double?
    let pitchAngle: Double?
    let landmarks: FaceLandmarks?
    let smilingProbability: Double?
    let leftEyeOpenProbability: Double?
    let rightEyeOpenProbability: Double?
}

struct FaceBounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct FaceLandmarks: Codable {
    let leftEye: Point?
    let rightEye: Point?
    let noseBase: Point?
    let mouthLeft: Point?
    let mouthRight: Point?
    let mouthBottom: Point?
    let leftEar: Point?
    let rightEar: Point?
    let leftCheek: Point?
    let rightCheek: Point?
}

struct Point: Codable {
    let x: Double
    let y: Double
}