import CoreLocation
import ImageIO
import MobileCoreServices
import UIKit

enum CaptureImageExifEncoder {
    typealias JpegEncoder = (UIImage, Int) -> Data?

    static func createImageData(
        from image: UIImage,
        quality: Int,
        location: CLLocation?,
        heading: CLHeading?,
        originalPhotoData: Data?,
        jpegEncoder: JpegEncoder = defaultJpegEncoder
    ) -> Data? {
        guard let cgImage = image.cgImage else {
            return jpegEncoder(image, quality)
        }

        let sourceDataForMetadata: CFData
        if let originalPhotoData {
            sourceDataForMetadata = originalPhotoData as CFData
        } else if let encoded = jpegEncoder(image, quality) {
            sourceDataForMetadata = encoded as CFData
        } else {
            return nil
        }

        guard let imageSource = CGImageSourceCreateWithData(sourceDataForMetadata, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return jpegEncoder(image, quality)
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) else {
            return jpegEncoder(image, quality)
        }

        var finalProperties = imageProperties

        // Ensure orientation reflects the pixel data (we pass an orientation-fixed UIImage)
        finalProperties[kCGImagePropertyOrientation as String] = 1

        if let location {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            formatter.timeZone = TimeZone(abbreviation: "UTC")

            var gpsDict: [String: Any] = [
                kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSTimeStamp as String: formatter.string(from: location.timestamp),
                kCGImagePropertyGPSAltitude as String: location.altitude,
                kCGImagePropertyGPSAltitudeRef as String: location.altitude >= 0 ? 0 : 1
            ]

            if let heading {
                let directionDegrees: Double
                let directionRef: String
                if heading.trueHeading >= 0 {
                    directionDegrees = heading.trueHeading
                    directionRef = "T"
                } else {
                    directionDegrees = heading.magneticHeading
                    directionRef = "M"
                }
                gpsDict[kCGImagePropertyGPSImgDirection as String] = directionDegrees
                gpsDict[kCGImagePropertyGPSImgDirectionRef as String] = directionRef
            }

            finalProperties[kCGImagePropertyGPSDictionary as String] = gpsDict
        }

        var tiffDict = finalProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiffDict[kCGImagePropertyTIFFMake as String] = "Apple"
        tiffDict[kCGImagePropertyTIFFModel as String] = UIDevice.current.model
        tiffDict[kCGImagePropertyTIFFOrientation as String] = 1
        finalProperties[kCGImagePropertyTIFFDictionary as String] = tiffDict

        CGImageDestinationAddImage(destination, cgImage, finalProperties as CFDictionary)

        if CGImageDestinationFinalize(destination) {
            return mutableData as Data
        }

        return jpegEncoder(image, quality)
    }

    private static func defaultJpegEncoder(image: UIImage, quality: Int) -> Data? {
        image.jpegData(compressionQuality: CGFloat(Double(quality) / 100.0))
    }
}
