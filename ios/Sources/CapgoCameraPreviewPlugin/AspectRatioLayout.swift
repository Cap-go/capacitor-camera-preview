import CoreGraphics
import Foundation

/// Viewport sizing for numeric aspect ratios (`4:3`, `16:9`) vs full-frame `fill`.
enum AspectRatioLayout {
    static func isFillMode(_ aspectRatio: String) -> Bool {
        aspectRatio.lowercased() == "fill"
    }

    /// Width-to-height ratio for the preview view in the current interface orientation.
    /// Returns `nil` for `fill` and other non-numeric values.
    static func parseViewportAspectRatio(_ ratio: String, isPortrait: Bool) -> CGFloat? {
        if isFillMode(ratio) {
            return nil
        }

        let parts = ratio.split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width.isFinite, height.isFinite,
              width > 0, height > 0 else {
            return nil
        }

        return isPortrait ?
            CGFloat(height / width) :
            CGFloat(width / height)
    }

    static func dimensionsForAspectRatio(
        _ aspectRatio: String,
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        isPortrait: Bool
    ) -> (width: CGFloat, height: CGFloat) {
        guard let ratio = parseViewportAspectRatio(aspectRatio, isPortrait: isPortrait) else {
            return (width: availableWidth, height: availableHeight)
        }

        let maxWidthByHeight = availableHeight * ratio
        let maxHeightByWidth = availableWidth / ratio

        if maxWidthByHeight <= availableWidth {
            return (width: maxWidthByHeight, height: availableHeight)
        }

        return (width: availableWidth, height: maxHeightByWidth)
    }
}
