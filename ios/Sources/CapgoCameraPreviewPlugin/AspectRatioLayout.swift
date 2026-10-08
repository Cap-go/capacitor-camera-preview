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

        let viewportRatio = CGFloat(isPortrait ? height / width : width / height)
        guard viewportRatio.isFinite, viewportRatio > 0 else {
            return nil
        }

        return viewportRatio
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

    /// Length left in `available` after an explicit `origin`, clamped at zero.
    /// Used to size an explicitly positioned `fill` axis from the web view.
    static func remainingLength(from origin: CGFloat, in available: CGFloat) -> CGFloat {
        max(0, available - origin)
    }

    /// Size of a `fill` preview with explicit `x` and `y` and no width or height:
    /// the web-view space remaining to the right of `x` and below `y`.
    static func positionedFillSize(
        x: CGFloat,
        y: CGFloat,
        viewportWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> (width: CGFloat, height: CGFloat) {
        (width: remainingLength(from: x, in: viewportWidth), height: remainingLength(from: y, in: viewportHeight))
    }

    /// Width-to-height ratio of the area visible in a `fill` preview using `cover`
    /// (`resizeAspectFill`), expressed in the orientation of the captured photo.
    /// Returns `nil` when the preview size is unusable.
    static func visibleFillCaptureAspectRatio(
        previewSize: CGSize,
        interfaceIsPortrait: Bool,
        captureIsPortrait: Bool
    ) -> CGFloat? {
        guard previewSize.width.isFinite, previewSize.height.isFinite,
              previewSize.width > 0, previewSize.height > 0 else {
            return nil
        }

        let ratio = previewSize.width / previewSize.height
        return interfaceIsPortrait == captureIsPortrait ? ratio : 1 / ratio
    }

    /// Centered crop rect with `targetAspectRatio` (width / height) inside `imageSize`,
    /// matching how `resizeAspectFill` centers the visible area.
    static func centerCropRect(imageSize: CGSize, targetAspectRatio: CGFloat) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        guard targetAspectRatio.isFinite, targetAspectRatio > 0,
              imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        let imageAspectRatio = imageSize.width / imageSize.height
        let rect: CGRect
        if imageAspectRatio > targetAspectRatio {
            let width = imageSize.height * targetAspectRatio
            rect = CGRect(x: (imageSize.width - width) / 2, y: 0, width: width, height: imageSize.height)
        } else {
            let height = imageSize.width / targetAspectRatio
            rect = CGRect(x: 0, y: (imageSize.height - height) / 2, width: imageSize.width, height: height)
        }
        return rect.intersection(bounds).integral.intersection(bounds)
    }
}
