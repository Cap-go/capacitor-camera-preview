import Foundation
import CoreGraphics
import AVFoundation

/// Utility class to transform face detection coordinates from camera frame space
/// to preview layer space, accounting for aspect ratio differences, letterboxing,
/// pillarboxing, videoGravity, and device orientation.
public class FaceCoordinateTransformer {
    private let frameWidth: CGFloat
    private let frameHeight: CGFloat
    private let previewWidth: CGFloat
    private let previewHeight: CGFloat
    private let videoGravity: AVLayerVideoGravity
    private let orientation: AVCaptureVideoOrientation
    
    /// Creates a coordinate transformer
    ///
    /// - Parameters:
    ///   - frameWidth: Width of camera frame in pixels
    ///   - frameHeight: Height of camera frame in pixels
    ///   - previewWidth: Width of preview layer in points
    ///   - previewHeight: Height of preview layer in points
    ///   - videoGravity: Video gravity setting (resizeAspect, resizeAspectFill, resize)
    ///   - orientation: Current video orientation
    public init(
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        previewWidth: CGFloat,
        previewHeight: CGFloat,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        orientation: AVCaptureVideoOrientation = .portrait
    ) {
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.videoGravity = videoGravity
        self.orientation = orientation
        
        print("""
        [FaceCoordTransformer] Created: frame=\(Int(frameWidth))x\(Int(frameHeight)), \
        preview=\(Int(previewWidth))x\(Int(previewHeight)), \
        gravity=\(videoGravity.rawValue), orientation=\(orientation.rawValue)
        """)
    }
    
    /// Transform a bounding box from normalized frame coordinates (0-1) to normalized preview coordinates (0-1)
    ///
    /// Vision framework provides normalized coordinates with origin at bottom-left.
    /// This method transforms them to be relative to the preview layer, accounting for
    /// aspect ratio differences and video gravity.
    ///
    /// - Parameter frameBounds: Normalized bounding box in frame coordinates (0-1, bottom-left origin)
    /// - Returns: Normalized bounds (x, y, width, height) in range 0-1 relative to preview (top-left origin)
    public func transformBounds(_ frameBounds: CGRect) -> CGRect {
        // Step 1: Apply orientation transformation
        var rotatedBounds = applyOrientationTransform(to: frameBounds)
        
        // Step 2: Calculate aspect ratio differences and scaling based on video gravity
        let frameAspect = frameWidth / frameHeight
        let previewAspect = previewWidth / previewHeight
        
        // Account for orientation swapping dimensions
        var effectiveFrameAspect = frameAspect
        if orientation == .landscapeLeft || orientation == .landscapeRight {
            effectiveFrameAspect = frameHeight / frameWidth
        }
        
        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        
        switch videoGravity {
        case .resizeAspectFill:
            // Fill mode - content may be cropped
            if effectiveFrameAspect > previewAspect {
                // Frame is wider - crop sides
                scaleX = effectiveFrameAspect / previewAspect
                scaleY = 1.0
                offsetX = -(scaleX - 1.0) / 2.0
                offsetY = 0.0
            } else {
                // Frame is taller - crop top/bottom
                scaleX = 1.0
                scaleY = previewAspect / effectiveFrameAspect
                offsetX = 0.0
                offsetY = -(scaleY - 1.0) / 2.0
            }
            
        case .resize:
            // Stretch to fill - no letterboxing
            scaleX = 1.0
            scaleY = 1.0
            offsetX = 0.0
            offsetY = 0.0
            
        default: // .resizeAspect
            // Fit mode - content may be letterboxed/pillarboxed
            if effectiveFrameAspect > previewAspect {
                // Frame is wider - pillarbox (black bars on left/right)
                scaleY = 1.0
                scaleX = previewAspect / effectiveFrameAspect
                offsetX = (1.0 - scaleX) / 2.0
                offsetY = 0.0
            } else {
                // Frame is taller - letterbox (black bars on top/bottom)
                scaleX = 1.0
                scaleY = effectiveFrameAspect / previewAspect
                offsetX = 0.0
                offsetY = (1.0 - scaleY) / 2.0
            }
        }
        
        // Step 3: Apply scaling and offset
        let finalX = rotatedBounds.origin.x * scaleX + offsetX
        let finalY = rotatedBounds.origin.y * scaleY + offsetY
        let finalW = rotatedBounds.width * scaleX
        let finalH = rotatedBounds.height * scaleY
        
        return CGRect(x: finalX, y: finalY, width: finalW, height: finalH)
    }
    
    /// Transform a point from normalized frame coordinates to normalized preview coordinates
    ///
    /// - Parameter framePoint: Normalized point in frame coordinates (0-1)
    /// - Returns: Normalized point in range 0-1 relative to preview
    public func transformPoint(_ framePoint: CGPoint) -> CGPoint {
        // Use the same transformation as bounds but for a single point
        let pointAsRect = CGRect(origin: framePoint, size: .zero)
        let transformed = transformBounds(pointAsRect)
        return transformed.origin
    }
    
    /// Apply orientation transformation to normalized coordinates
    ///
    /// Coordinates are already in top-left origin from FaceDetectionManager.
    /// This method rotates them based on device orientation.
    ///
    /// - Parameter rect: Normalized rect with top-left origin
    /// - Returns: Normalized rect adjusted for orientation with top-left origin
    private func applyOrientationTransform(to rect: CGRect) -> CGRect {
        var x = rect.origin.x
        var y = rect.origin.y
        var w = rect.width
        var h = rect.height
        
        // Coordinates are already top-left origin - no need to flip Y
        
        // Apply rotation based on orientation
        let rotatedX: CGFloat
        let rotatedY: CGFloat
        let rotatedW: CGFloat
        let rotatedH: CGFloat
        
        switch orientation {
        case .landscapeLeft:
            // 90° counterclockwise: (x, y) -> (y, 1-x-w)
            rotatedX = y
            rotatedY = 1.0 - x - w
            rotatedW = h
            rotatedH = w
            
        case .landscapeRight:
            // 90° clockwise: (x, y) -> (1-y-h, x)
            rotatedX = 1.0 - y - h
            rotatedY = x
            rotatedW = h
            rotatedH = w
            
        case .portraitUpsideDown:
            // 180°: (x, y) -> (1-x-w, 1-y-h)
            rotatedX = 1.0 - x - w
            rotatedY = 1.0 - y - h
            rotatedW = w
            rotatedH = h
            
        default: // .portrait
            rotatedX = x
            rotatedY = y
            rotatedW = w
            rotatedH = h
        }
        
        return CGRect(x: rotatedX, y: rotatedY, width: rotatedW, height: rotatedH)
    }
    
    /// Convert from normalized coordinates to pixel/point coordinates
    ///
    /// - Parameter normalized: Normalized rect (0-1)
    /// - Returns: Rect in preview layer pixel/point coordinates
    public func denormalizeToPreview(_ normalized: CGRect) -> CGRect {
        return CGRect(
            x: normalized.origin.x * previewWidth,
            y: normalized.origin.y * previewHeight,
            width: normalized.width * previewWidth,
            height: normalized.height * previewHeight
        )
    }
}
