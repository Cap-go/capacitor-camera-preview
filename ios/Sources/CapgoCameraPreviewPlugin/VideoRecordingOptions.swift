import AVFoundation
import Foundation

enum VideoRecordingOptions {
    /// Returns a positive bits-per-second value, or `nil` when omitted or invalid.
    static func parseVideoBitrate(from value: Any?) -> Int? {
        guard let value = value else {
            return nil
        }
        if let intValue = value as? Int {
            return intValue > 0 ? intValue : nil
        }
        if let doubleValue = value as? Double {
            guard doubleValue.isFinite, doubleValue > 0, doubleValue <= Double(Int.max) else {
                return nil
            }
            return Int(doubleValue.rounded())
        }
        if let stringValue = value as? String, let doubleValue = Double(stringValue) {
            guard doubleValue.isFinite, doubleValue > 0, doubleValue <= Double(Int.max) else {
                return nil
            }
            return Int(doubleValue.rounded())
        }
        return nil
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
