import Foundation
import CoreGraphics

/// Utility class to validate face alignment for optimal capture.
/// Checks head pose angles (pitch, roll, yaw) and face size.
public class FaceAlignmentValidator {
    
    // Default thresholds for face alignment validation
    private static let defaultMaxRollDegrees: Double = 15.0
    private static let defaultMaxPitchDegrees: Double = 15.0
    private static let defaultMaxYawDegrees: Double = 20.0
    private static let defaultMinFaceSize: Double = 0.20 // 20% of frame
    private static let defaultMaxFaceSize: Double = 0.80 // 80% of frame
    private static let defaultMinCenterX: Double = 0.35 // Face center should be 35-65% horizontally
    private static let defaultMaxCenterX: Double = 0.65
    private static let defaultMinCenterY: Double = 0.30 // Face center should be 30-70% vertically
    private static let defaultMaxCenterY: Double = 0.70
    
    private let maxRollDegrees: Double
    private let maxPitchDegrees: Double
    private let maxYawDegrees: Double
    private let minFaceSize: Double
    private let maxFaceSize: Double
    private let minCenterX: Double
    private let maxCenterX: Double
    private let minCenterY: Double
    private let maxCenterY: Double
    
    /// Create validator with default thresholds
    public init() {
        self.maxRollDegrees = Self.defaultMaxRollDegrees
        self.maxPitchDegrees = Self.defaultMaxPitchDegrees
        self.maxYawDegrees = Self.defaultMaxYawDegrees
        self.minFaceSize = Self.defaultMinFaceSize
        self.maxFaceSize = Self.defaultMaxFaceSize
        self.minCenterX = Self.defaultMinCenterX
        self.maxCenterX = Self.defaultMaxCenterX
        self.minCenterY = Self.defaultMinCenterY
        self.maxCenterY = Self.defaultMaxCenterY
    }
    
    /// Create validator with custom thresholds
    public init(
        maxRollDegrees: Double,
        maxPitchDegrees: Double,
        maxYawDegrees: Double,
        minFaceSize: Double,
        maxFaceSize: Double,
        minCenterX: Double,
        maxCenterX: Double,
        minCenterY: Double,
        maxCenterY: Double
    ) {
        self.maxRollDegrees = maxRollDegrees
        self.maxPitchDegrees = maxPitchDegrees
        self.maxYawDegrees = maxYawDegrees
        self.minFaceSize = minFaceSize
        self.maxFaceSize = maxFaceSize
        self.minCenterX = minCenterX
        self.maxCenterX = maxCenterX
        self.minCenterY = minCenterY
        self.maxCenterY = maxCenterY
    }
    
    /// Validate face alignment
    ///
    /// - Parameters:
    ///   - rollAngle: Head roll angle in degrees (tilt left/right)
    ///   - pitchAngle: Head pitch angle in degrees (nod up/down)
    ///   - yawAngle: Head yaw angle in degrees (turn left/right)
    ///   - bounds: Face bounding box in normalized coordinates (0-1)
    /// - Returns: Validation result with detailed feedback
    public func validate(
        rollAngle: Double,
        pitchAngle: Double,
        yawAngle: Double,
        bounds: CGRect
    ) -> AlignmentResult {
        var result = AlignmentResult()
        
        // Validate roll (head tilt)
        if abs(rollAngle) > maxRollDegrees {
            result.isRollValid = false
            result.rollFeedback = rollAngle > 0 
                ? "Tilt your head less to the right" 
                : "Tilt your head less to the left"
        } else {
            result.isRollValid = true
        }
        
        // Validate pitch (head nod)
        if abs(pitchAngle) > maxPitchDegrees {
            result.isPitchValid = false
            result.pitchFeedback = pitchAngle > 0 
                ? "Look down less" 
                : "Look up less"
        } else {
            result.isPitchValid = true
        }
        
        // Validate yaw (head turn)
        if abs(yawAngle) > maxYawDegrees {
            result.isYawValid = false
            result.yawFeedback = yawAngle > 0 
                ? "Turn your head less to the right" 
                : "Turn your head less to the left"
        } else {
            result.isYawValid = true
        }
        
        // Validate face size
        let faceSize = max(bounds.width, bounds.height)
        if faceSize < minFaceSize {
            result.isSizeValid = false
            result.sizeFeedback = "Move closer to the camera"
        } else if faceSize > maxFaceSize {
            result.isSizeValid = false
            result.sizeFeedback = "Move farther from the camera"
        } else {
            result.isSizeValid = true
        }
        
        // Validate face centering
        let centerX = bounds.origin.x + bounds.width / 2.0
        let centerY = bounds.origin.y + bounds.height / 2.0
        
        if centerX < minCenterX {
            result.isCenteringValid = false
            result.centeringFeedback = "Move right"
        } else if centerX > maxCenterX {
            result.isCenteringValid = false
            result.centeringFeedback = "Move left"
        } else if centerY < minCenterY {
            result.isCenteringValid = false
            result.centeringFeedback = "Move down"
        } else if centerY > maxCenterY {
            result.isCenteringValid = false
            result.centeringFeedback = "Move up"
        } else {
            result.isCenteringValid = true
        }
        
        // Overall validation
        result.isValid = result.isRollValid && result.isPitchValid && 
                        result.isYawValid && result.isSizeValid && result.isCenteringValid
        
        return result
    }
    
    /// Result of face alignment validation
    public struct AlignmentResult {
        public var isValid: Bool = false
        
        // Individual validations
        public var isRollValid: Bool = false
        public var isPitchValid: Bool = false
        public var isYawValid: Bool = false
        public var isSizeValid: Bool = false
        public var isCenteringValid: Bool = false
        
        // Feedback messages
        public var rollFeedback: String?
        public var pitchFeedback: String?
        public var yawFeedback: String?
        public var sizeFeedback: String?
        public var centeringFeedback: String?
        
        /// Get primary feedback message (first issue found)
        public var primaryFeedback: String {
            if let feedback = rollFeedback { return feedback }
            if let feedback = pitchFeedback { return feedback }
            if let feedback = yawFeedback { return feedback }
            if let feedback = sizeFeedback { return feedback }
            if let feedback = centeringFeedback { return feedback }
            return "Face aligned perfectly"
        }
        
        /// Get all feedback messages
        public var allFeedback: [String] {
            var feedback: [String] = []
            if let msg = rollFeedback { feedback.append(msg) }
            if let msg = pitchFeedback { feedback.append(msg) }
            if let msg = yawFeedback { feedback.append(msg) }
            if let msg = sizeFeedback { feedback.append(msg) }
            if let msg = centeringFeedback { feedback.append(msg) }
            return feedback
        }
    }
}
