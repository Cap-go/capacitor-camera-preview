import Foundation

/// Serial queue for still-capture pixel work (crop, resize, mirror, JPEG/EXIF, file I/O).
enum CapturePhotoProcessingQueue {
    private static let queueKey = DispatchSpecificKey<UInt8>()

    static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.capgo.camera-preview.capture-processing", qos: .userInitiated)
        queue.setSpecific(key: queueKey, value: 1)
        return queue
    }()

    static func async(execute work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    static var isCurrentQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }
}
