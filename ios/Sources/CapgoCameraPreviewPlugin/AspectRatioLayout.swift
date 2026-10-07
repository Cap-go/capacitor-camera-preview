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

        let parts = ratio.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            return nil
        }

        return isPortrait ?
            CGFloat(parts[1] / parts[0]) :
            CGFloat(parts[0] / parts[1])
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
