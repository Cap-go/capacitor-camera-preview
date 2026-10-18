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

    /// Picks a supported `maxPhotoDimensions` value at or below the configured cap.
    static func photoMaxDimensions(
        configuredWidth: Int,
        configuredHeight: Int,
        supportedDimensions: [CMVideoDimensions],
        deviceMax: CMVideoDimensions
    ) -> CMVideoDimensions {
        let normalized = normalizedCaptureTargetResolution(configuredWidth: configuredWidth, configuredHeight: configuredHeight)
        let targetLong = Int32(normalized.width)
        let targetShort = Int32(normalized.height)

        let fittingSupported = supportedDimensions.filter { dimension in
            longEdge(dimension) <= targetLong && shortEdge(dimension) <= targetShort
        }

        if let bestFit = fittingSupported.max(by: { pixelArea($0) < pixelArea($1) }) {
            return bestFit
        }

        if let smallestSupported = supportedDimensions.min(by: { pixelArea($0) < pixelArea($1) }) {
            return smallestSupported
        }

        return clampPhotoDimensions(
            width: targetLong,
            height: targetShort,
            deviceMax: deviceMax
        )
    }

    static func clampPhotoDimensions(width: Int32, height: Int32, deviceMax: CMVideoDimensions) -> CMVideoDimensions {
        var clampedWidth = width
        var clampedHeight = height
        let deviceWidth = deviceMax.width
        let deviceHeight = deviceMax.height
        if clampedWidth > deviceWidth || clampedHeight > deviceHeight {
            let scale = min(Double(deviceWidth) / Double(clampedWidth), Double(deviceHeight) / Double(clampedHeight))
            clampedWidth = max(1, Int32((Double(clampedWidth) * scale).rounded(.down)))
            clampedHeight = max(1, Int32((Double(clampedHeight) * scale).rounded(.down)))
        }
        return CMVideoDimensions(width: clampedWidth, height: clampedHeight)
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
