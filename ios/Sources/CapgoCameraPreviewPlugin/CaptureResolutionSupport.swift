import AVFoundation
import Foundation

struct CaptureResolutionParseResult {
    let width: Int?
    let height: Int?
    let errorMessage: String?

    var isError: Bool { errorMessage != nil }

    static func success(width: Int?, height: Int?) -> CaptureResolutionParseResult {
        CaptureResolutionParseResult(width: width, height: height, errorMessage: nil)
    }

    static func error(_ message: String) -> CaptureResolutionParseResult {
        CaptureResolutionParseResult(width: nil, height: nil, errorMessage: message)
    }
}

enum CaptureResolutionSupport {
    static func parseStartCaptureResolution(_ captureResolutionObject: Any?) -> CaptureResolutionParseResult {
        guard let captureResolutionObject else {
            return .success(width: nil, height: nil)
        }

        guard let captureResolution = captureResolutionObject as? [String: Any] else {
            return .error("captureResolution must be an object with width and height")
        }

        guard captureResolution["width"] != nil, captureResolution["height"] != nil else {
            return .error("captureResolution requires both width and height")
        }

        guard let captureWidth = parsePositivePixelDimension(captureResolution["width"]),
              let captureHeight = parsePositivePixelDimension(captureResolution["height"]) else {
            return .error("captureResolution width and height must be positive")
        }

        return .success(width: captureWidth, height: captureHeight)
    }

    static func parsePositivePixelDimension(_ value: Any?) -> Int? {
        guard let value else { return nil }

        if let number = value as? NSNumber {
            return parsePositivePixelDimensionFromDouble(number.doubleValue)
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            guard let numeric = Double(trimmed) else { return nil }
            return parsePositivePixelDimensionFromDouble(numeric)
        }
        return nil
    }

    private static func parsePositivePixelDimensionFromDouble(_ numeric: Double) -> Int? {
        guard !numeric.isNaN, !numeric.isInfinite, numeric > 0 else { return nil }
        guard numeric == floor(numeric), numeric <= Double(Int.max) else { return nil }
        guard numeric <= Double(Int32.max) else { return nil }
        return Int(numeric)
    }

    /// Matches Android `normalizedCaptureTargetResolution`: landscape-major width and height.
    static func normalizedCaptureTargetResolution(configuredWidth: Int, configuredHeight: Int) -> (width: Int, height: Int) {
        (max(configuredWidth, configuredHeight), min(configuredWidth, configuredHeight))
    }

    static func longEdge(_ dimensions: CMVideoDimensions) -> Int32 {
        max(dimensions.width, dimensions.height)
    }

    static func shortEdge(_ dimensions: CMVideoDimensions) -> Int32 {
        min(dimensions.width, dimensions.height)
    }

    static func pixelArea(_ dimensions: CMVideoDimensions) -> Int64 {
        Int64(dimensions.width) * Int64(dimensions.height)
    }

    /// Picks a value from `supportedMaxPhotoDimensions` at or below the configured cap when possible.
    /// When no supported size fits under the cap (for example a single full-sensor entry), returns the
    /// smallest supported size by long edge, matching Android `filterCaptureResolutionCandidates`.
    /// Returns `nil` when `supportedDimensions` is empty so callers never assign an unsupported value.
    static func photoMaxDimensions(
        configuredWidth: Int,
        configuredHeight: Int,
        supportedDimensions: [CMVideoDimensions]
    ) -> CMVideoDimensions? {
        guard !supportedDimensions.isEmpty else { return nil }

        let normalized = normalizedCaptureTargetResolution(configuredWidth: configuredWidth, configuredHeight: configuredHeight)
        let targetLong = Int32(normalized.width)
        let targetShort = Int32(normalized.height)

        let fittingSupported = supportedDimensions.filter { dimension in
            longEdge(dimension) <= targetLong && shortEdge(dimension) <= targetShort
        }

        if let bestFit = fittingSupported.max(by: { pixelArea($0) < pixelArea($1) }) {
            return bestFit
        }

        return smallestSupportedPhotoDimension(supportedDimensions)
    }

    static func smallestSupportedPhotoDimension(_ supportedDimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
        guard !supportedDimensions.isEmpty else { return nil }
        return supportedDimensions.min(by: { longEdge($0) < longEdge($1) })
    }

    static func dimensionsEqual(_ lhs: CMVideoDimensions, _ rhs: CMVideoDimensions) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
    }

    static func isSupportedPhotoDimension(_ dimension: CMVideoDimensions, in supportedDimensions: [CMVideoDimensions]) -> Bool {
        supportedDimensions.contains { dimensionsEqual($0, dimension) }
    }

    static func shouldEnableHighResolutionPhoto(
        captureResolutionWidth: Int?,
        captureResolutionHeight: Int?,
        captureMaxWidth: Int?,
        captureMaxHeight: Int?
    ) -> Bool {
        if captureResolutionWidth != nil, captureResolutionHeight != nil {
            return false
        }
        let widthExceedsDefault = captureMaxWidth.map { $0 > 1920 } ?? false
        let heightExceedsDefault = captureMaxHeight.map { $0 > 1920 } ?? false
        return widthExceedsDefault || heightExceedsDefault
    }
}
