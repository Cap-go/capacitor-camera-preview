import AVFoundation
import Foundation

enum VideoRecordingOptions {
    /// Returns a positive bits-per-second value, or `nil` when omitted or invalid.
    static func parseVideoBitrate(from value: Any?) -> Int? {
        guard let value = value else {
            return nil
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        if let intValue = value as? Int {
            return intValue > 0 ? intValue : nil
        }
        if let doubleValue = value as? Double {
            return positiveInt(from: doubleValue)
        }
        if let stringValue = value as? String, let doubleValue = Double(stringValue) {
            return positiveInt(from: doubleValue)
        }
        if let numberValue = value as? NSNumber {
            return positiveInt(from: numberValue.doubleValue)
        }
        return nil
    }

    private static func positiveInt(from doubleValue: Double) -> Int? {
        guard doubleValue.isFinite, doubleValue > 0, doubleValue.rounded() == doubleValue else {
            return nil
        }
        return Int(exactly: doubleValue)
    }

    /// Per-call override when the key is present and valid; `nil` when omitted or invalid (restore preview bitrate).
    static func resolveRecordingVideoBitrateOverride(from value: Any?, isKeyPresent: Bool) -> Int? {
        guard isKeyPresent else {
            return nil
        }
        return parseVideoBitrate(from: value)
    }

    static func movieFileOutputSettings(
        codecType: AVVideoCodecType,
        videoBitrate: Int?
    ) -> [String: Any] {
        var settings: [String: Any] = [AVVideoCodecKey: codecType]
        if let videoBitrate = videoBitrate, videoBitrate > 0 {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: videoBitrate]
        }
        return settings
    }
}
