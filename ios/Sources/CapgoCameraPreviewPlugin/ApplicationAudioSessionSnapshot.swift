import AVFoundation
import Foundation

/// Captures and restores the app `AVAudioSession` category, mode, and options.
struct ApplicationAudioSessionSnapshot {
    private let category: AVAudioSession.Category
    private let mode: AVAudioSession.Mode
    private let categoryOptions: AVAudioSession.CategoryOptions

    static func capture(from session: AVAudioSession = .sharedInstance()) -> ApplicationAudioSessionSnapshot {
        ApplicationAudioSessionSnapshot(
            category: session.category,
            mode: session.mode,
            categoryOptions: session.categoryOptions
        )
    }

    @discardableResult
    func apply(to session: AVAudioSession = .sharedInstance()) -> Bool {
        do {
            try session.setCategory(category, mode: mode, options: categoryOptions)
            return true
        } catch {
            print("[CameraPreview] Failed to restore AVAudioSession: \(error)")
            return false
        }
    }
}
