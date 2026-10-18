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
        return Int(numeric)
    }

    /// Matches Android `normalizedCaptureTargetResolution`: landscape-major width and height.
    static func normalizedCaptureTargetResolution(configuredWidth: Int, configuredHeight: Int) -> (width: Int, height: Int) {
        (max(configuredWidth, configuredHeight), min(configuredWidth, configuredHeight))
    }

    /// Picks `maxPhotoDimensions` for AVCapturePhotoSettings, clamped to the output maximum.
    static func photoMaxDimensions(
        configuredWidth: Int,
        configuredHeight: Int,
        deviceMax: CMVideoDimensions
    ) -> CMVideoDimensions {
        let normalized = normalizedCaptureTargetResolution(configuredWidth: configuredWidth, configuredHeight: configuredHeight)
        var width = Int32(normalized.width)
        var height = Int32(normalized.height)

        let deviceWidth = deviceMax.width
        let deviceHeight = deviceMax.height
        if width > deviceWidth || height > deviceHeight {
            let scale = min(Double(deviceWidth) / Double(width), Double(deviceHeight) / Double(height))
            width = max(1, Int32((Double(width) * scale).rounded(.down)))
            height = max(1, Int32((Double(height) * scale).rounded(.down)))
        }

        return CMVideoDimensions(width: width, height: height)
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
