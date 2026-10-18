import Foundation
import ImageIO
import MobileCoreServices
import UIKit

enum ImageIOJpegEncoding {
    static func compressionQuality(forPercent qualityPercent: Int) -> CGFloat {
        CGFloat(Double(qualityPercent) / 100.0)
    }

    static func applyingCompressionQuality(_ qualityPercent: Int, to properties: [String: Any]) -> [String: Any] {
        var result = properties
        result[kCGImageDestinationLossyCompressionQuality as String] = compressionQuality(forPercent: qualityPercent)
        return result
    }

    static func encode(cgImage: CGImage, properties: [String: Any], qualityPercent: Int) -> Data? {
        let finalProperties = applyingCompressionQuality(qualityPercent, to: properties)
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, finalProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }
}
