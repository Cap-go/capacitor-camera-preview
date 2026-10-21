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

        var finalProperties = imageProperties

        // Ensure orientation reflects the pixel data (we pass an orientation-fixed UIImage)
        finalProperties[kCGImagePropertyOrientation as String] = 1

        if let location {
            finalProperties[kCGImagePropertyGPSDictionary as String] = ExifGpsMetadata.gpsDictionary(
                for: location,
                heading: heading
            )
        }

        var tiffDict = finalProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiffDict[kCGImagePropertyTIFFMake as String] = "Apple"
        tiffDict[kCGImagePropertyTIFFModel as String] = UIDevice.current.model
        tiffDict[kCGImagePropertyTIFFOrientation as String] = 1
        finalProperties[kCGImagePropertyTIFFDictionary as String] = tiffDict

        if let encoded = ImageIOJpegEncoding.encode(cgImage: cgImage, properties: finalProperties, qualityPercent: quality) {
            return encoded
        }

        return jpegEncoder(image, quality)
    }

    private static func defaultJpegEncoder(image: UIImage, quality: Int) -> Data? {
        image.jpegData(compressionQuality: CGFloat(Double(quality) / 100.0))
    }
}
