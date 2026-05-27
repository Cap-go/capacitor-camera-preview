import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func drawTimestampAndLocation(on image: UIImage, when: String?, where whereStr: String?) -> UIImage {
        let base = image.fixedOrientation() ?? image
        let scale = base.scale
        let size  = base.size

        // Style (match drawTimestamp)
        let textColor: UIColor = .white
        let backgroundColor = UIColor(white: 0.12, alpha: 0.22)
        let paddingH: CGFloat = 16
        let paddingV: CGFloat = 10
        let cornerRadius: CGFloat = 10
        let margin: CGFloat = 12
        let gap: CGFloat = 8

        // ≈3.5% of image width (≥10pt)
        let fontPointSize = max(10, size.width * 0.035)
        let font: UIFont = .systemFont(ofSize: fontPointSize, weight: .semibold)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))

            func drawPill(_ text: String, top: CGFloat) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let textSize = (text as NSString).size(withAttributes: attrs)
                let bgSize  = CGSize(width: textSize.width + paddingH * 2,
                                     height: textSize.height + paddingV * 2)
                let origin  = CGPoint(x: size.width - bgSize.width - margin, y: top)
                let rect    = CGRect(origin: origin, size: bgSize)

                // shadowed rounded bg
                let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
                ctx.cgContext.saveGState()
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 2),
                                        blur: 6,
                                        color: UIColor.black.withAlphaComponent(0.25).cgColor)
                backgroundColor.setFill()
                path.fill()
                ctx.cgContext.restoreGState()

                // high-quality text
                let graphics = ctx.cgContext
                graphics.setAllowsAntialiasing(true)
                graphics.setShouldAntialias(true)
                graphics.setAllowsFontSmoothing(true)
                graphics.setShouldSmoothFonts(true)
                graphics.setShouldSubpixelPositionFonts(true)
                graphics.interpolationQuality = .high

                (text as NSString).draw(at: CGPoint(x: rect.minX + paddingH, y: rect.minY + paddingV),
                                        withAttributes: attrs)

                return rect.maxY
            }

            var top = margin
            if let whenText = when, !whenText.isEmpty {
                top = drawPill(whenText, top: top) + gap
            }
            if let locationText = whereStr, !locationText.isEmpty {
                _ = drawPill(locationText, top: (top == margin ? margin : top))
            }
        }
    }

    func makeTimestampString(from photoData: Data?, metadata: [AnyHashable: Any]?) -> String {
        func extractDateString(from meta: [String: Any]) -> String? {
            if let exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                if let dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String { return dateTimeOriginal }
                if let dateTimeDigitized = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String { return dateTimeDigitized }
            }
            if let tiff = meta[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                if let dateTime = tiff[kCGImagePropertyTIFFDateTime as String] as? String { return dateTime }
            }
            return nil
        }

        var raw: String?
        if let metadata = metadata as? [String: Any] {
            raw = extractDateString(from: metadata)
        }
        if raw == nil, let data = photoData,
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            raw = extractDateString(from: props)
        }

        let outFmt = DateFormatter()
        outFmt.locale = .current
        outFmt.timeZone = .current
        outFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        if let raw = raw {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = .current
            dateFormatter.dateFormat = raw.contains(".") ? "yyyy:MM:dd HH:mm:ss.SSS" : "yyyy:MM:dd HH:mm:ss"
            if let date = dateFormatter.date(from: raw) {
                return outFmt.string(from: date)
            }
        }

        return outFmt.string(from: Date())
    }

    func makeLocationString(from location: CLLocation?,
                            photoData: Data?,
                            metadata: [AnyHashable: Any]?) -> String? {
        // 1) Prefer the explicit CLLocation that was just provided
        if let loc = location {
            let lat = String(format: "%.5f", loc.coordinate.latitude)
            let lon = String(format: "%.5f", loc.coordinate.longitude)
            return "\(lat), \(lon)"
        }

        // 2) Fall back to EXIF GPS in metadata / photo data
        func extractGPS(_ meta: [String: Any]) -> (Double, Double)? {
            guard let gps = meta[kCGImagePropertyGPSDictionary as String] as? [String: Any] else { return nil }
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
               let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                let signedLat = (latRef.uppercased() == "S") ? -lat : lat
                let signedLon = (lonRef.uppercased() == "W") ? -lon : lon
                return (signedLat, signedLon)
            }
            return nil
        }

        if let metaDict = metadata as? [String: Any], let (lat, lon) = extractGPS(metaDict) {
            return String(format: "%.5f, %.5f", lat, lon)
        }

        if let data = photoData,
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
           let (lat, lon) = extractGPS(props) {
            return String(format: "%.5f, %.5f", lat, lon)
        }

        return nil
    }

    // Create JPEG data from `image`, merging the original EXIF/GPS/etc. and forcing Orientation=1.

    func jpegDataPreservingMetadata(from image: UIImage,
                                    originalPhotoData: Data?,
                                    originalMetadata: [AnyHashable: Any]?,
                                    quality: CGFloat = 0.9) -> Data? {
        // Encode pixels first
        guard let cgImg = image.cgImage else { return image.jpegData(compressionQuality: quality) }
        let uiImageData = UIImage(cgImage: cgImg, scale: image.scale, orientation: .up)
            .jpegData(compressionQuality: quality)

        // If we don’t have source metadata, just return the new JPEG
        guard let srcData = originalPhotoData, let newJPEG = uiImageData else { return uiImageData }

        // Load base metadata from source, then overlay any explicit metadata dict we were given
        let cgSrc = CGImageSourceCreateWithData(srcData as CFData, nil)
        let baseMetadata: [String: Any]
        if let src = cgSrc,
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            var merged = props
            if let explicit = originalMetadata as? [String: Any] {
                for (key, value) in explicit { merged[key] = value }
            }
            baseMetadata = merged
        } else if let explicit = originalMetadata as? [String: Any] {
            baseMetadata = explicit
        } else {
            return newJPEG
        }

        // Prepare destination
        let dstData = NSMutableData()
        guard let cgDst = CGImageDestinationCreateWithData(dstData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return newJPEG
        }

        // Force normalized orientation (pixels are already .up)
        var metaOut = baseMetadata
        if var tiff = metaOut[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metaOut[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        metaOut[kCGImagePropertyOrientation as String] = 1

        // Write the new pixels + merged metadata
        if let cgImage = UIImage(data: newJPEG)?.cgImage {
            CGImageDestinationAddImage(cgDst, cgImage, metaOut as CFDictionary)
            CGImageDestinationFinalize(cgDst)
            return (dstData as Data)
        }

        return newJPEG
    }

}
