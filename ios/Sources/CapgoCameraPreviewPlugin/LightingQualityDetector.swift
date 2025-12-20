import Foundation
import CoreVideo
import AVFoundation

/// Utility class to assess lighting quality from camera frames.
/// Analyzes brightness levels and provides guidance for better lighting.
public class LightingQualityDetector {
    
    // Default thresholds for lighting quality
    private static let defaultMinBrightness: Double = 0.25 // Too dark below 25%
    private static let defaultMaxBrightness: Double = 0.85 // Too bright above 85%
    private static let defaultOptimalMin: Double = 0.35
    private static let defaultOptimalMax: Double = 0.75
    
    private let minBrightness: Double
    private let maxBrightness: Double
    private let optimalMin: Double
    private let optimalMax: Double
    
    /// Create detector with default thresholds
    public init() {
        self.minBrightness = Self.defaultMinBrightness
        self.maxBrightness = Self.defaultMaxBrightness
        self.optimalMin = Self.defaultOptimalMin
        self.optimalMax = Self.defaultOptimalMax
    }
    
    /// Create detector with custom thresholds
    public init(
        minBrightness: Double,
        maxBrightness: Double,
        optimalMin: Double,
        optimalMax: Double
    ) {
        self.minBrightness = minBrightness
        self.maxBrightness = maxBrightness
        self.optimalMin = optimalMin
        self.optimalMax = optimalMax
    }
    
    /// Analyze lighting quality from camera frame
    ///
    /// - Parameter pixelBuffer: Camera frame pixel buffer
    /// - Returns: Lighting quality result with feedback
    public func analyzeLighting(_ pixelBuffer: CVPixelBuffer) -> LightingResult {
        // Calculate average brightness
        let brightness = calculateBrightness(pixelBuffer)
        
        var result = LightingResult()
        result.brightnessLevel = brightness
        
        // Assess lighting quality
        if brightness < minBrightness {
            result.isGoodLighting = false
            result.isTooDark = true
            result.isTooBright = false
            result.feedback = "Move to a brighter area"
        } else if brightness > maxBrightness {
            result.isGoodLighting = false
            result.isTooDark = false
            result.isTooBright = true
            result.feedback = "Reduce lighting or move to shade"
        } else if brightness < optimalMin || brightness > optimalMax {
            result.isGoodLighting = true // Acceptable but not optimal
            result.isTooDark = false
            result.isTooBright = false
            result.feedback = brightness < optimalMin 
                ? "Lighting acceptable, but brighter is better" 
                : "Lighting acceptable, but dimmer is better"
        } else {
            result.isGoodLighting = true
            result.isTooDark = false
            result.isTooBright = false
            result.feedback = "Lighting is good"
        }
        
        return result
    }
    
    /// Calculate average brightness from pixel buffer
    /// Returns value from 0.0 (black) to 1.0 (white)
    private func calculateBrightness(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Handle different pixel formats
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        var brightness: Double = 0.5 // Default
        
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // Y plane contains luminance
            brightness = calculateBrightnessFromYPlane(pixelBuffer, width: width, height: height)
            
        case kCVPixelFormatType_32BGRA:
            // BGRA format - calculate from RGB
            brightness = calculateBrightnessFromBGRA(pixelBuffer, width: width, height: height)
            
        default:
            print("[LightingQualityDetector] Unsupported pixel format: \(pixelFormat)")
        }
        
        return brightness
    }
    
    /// Calculate brightness from Y plane (luminance)
    private func calculateBrightnessFromYPlane(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> Double {
        guard let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return 0.5
        }
        
        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let yBuffer = yBaseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Sample every 8th pixel for performance
        let sampleSize = 8
        var sum: UInt64 = 0
        var count = 0
        
        for y in stride(from: 0, to: height, by: sampleSize) {
            for x in stride(from: 0, to: width, by: sampleSize) {
                let index = y * yBytesPerRow + x
                let luminance = yBuffer[index]
                sum += UInt64(luminance)
                count += 1
            }
        }
        
        guard count > 0 else { return 0.5 }
        
        // Return normalized brightness (0.0 - 1.0)
        return Double(sum) / Double(count) / 255.0
    }
    
    /// Calculate brightness from BGRA pixel data
    private func calculateBrightnessFromBGRA(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> Double {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0.5
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Sample every 8th pixel for performance
        let sampleSize = 8
        var sum: Double = 0
        var count = 0
        
        for y in stride(from: 0, to: height, by: sampleSize) {
            for x in stride(from: 0, to: width, by: sampleSize) {
                let index = y * bytesPerRow + x * 4
                let b = Double(buffer[index])
                let g = Double(buffer[index + 1])
                let r = Double(buffer[index + 2])
                
                // Calculate relative luminance (perceived brightness)
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                sum += luminance
                count += 1
            }
        }
        
        guard count > 0 else { return 0.5 }
        
        // Return normalized brightness (0.0 - 1.0)
        return sum / Double(count) / 255.0
    }
    
    /// Result of lighting quality analysis
    public struct LightingResult {
        public var isGoodLighting: Bool = false
        public var brightnessLevel: Double = 0.0
        public var isTooDark: Bool = false
        public var isTooBright: Bool = false
        public var feedback: String = ""
        
        /// Get recommended exposure compensation adjustment
        /// - Returns: Suggested EV adjustment (-2.0 to +2.0)
        public var recommendedExposureCompensation: Float {
            if isTooDark {
                // Increase exposure for dark scenes
                return Float(min(2.0, (0.4 - brightnessLevel) * 3.0))
            } else if isTooBright {
                // Decrease exposure for bright scenes
                return Float(max(-2.0, (0.7 - brightnessLevel) * 3.0))
            }
            return 0.0 // No adjustment needed
        }
    }
}
