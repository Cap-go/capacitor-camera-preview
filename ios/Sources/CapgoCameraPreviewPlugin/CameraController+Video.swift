import AVFoundation
import CoreGraphics
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import UIKit

extension CameraController {
    func captureVideo() throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CameraControllerError.cannotFindDocumentsDirectory
        }

        guard let fileVideoOutput = self.fileVideoOutput else {
            throw CameraControllerError.fileVideoOutputNotFound
        }

        // Ensure audio session is configured for recording before starting a movie,
        // only when we are actually recording audio (disableAudio was false).
        // This reclaims the microphone even if other parts of the app changed the
        // AVAudioSession category (e.g. for UI sound effects) between recordings.
        if self.audioInput != nil {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
                try audioSession.setActive(true)
            } catch {
                print("[CameraPreview] Failed to configure AVAudioSession for video recording: \(error)")
            }
        }

        // Ensure the movie file output is attached to the active session.
        // If the camera was started without cameraMode=true, the output may not have been added yet.
        if !captureSession.outputs.contains(where: { $0 === fileVideoOutput }) {
            captureSession.beginConfiguration()
            if captureSession.canAddOutput(fileVideoOutput) {
                captureSession.addOutput(fileVideoOutput)
            } else {
                captureSession.commitConfiguration()
                throw CameraControllerError.invalidOperation
            }
            captureSession.commitConfiguration()
        }

        if let connection = fileVideoOutput.connection(with: .video) {
            if connection.isEnabled == false { connection.isEnabled = true }
            // Goes off accelerometer now
            connection.videoOrientation = self.getPhysicalOrientation()

            // Front camera: mirror the recorded video so it looks natural (selfie style).
            if self.currentCameraPosition == .front, connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            } else {
                connection.isVideoMirrored = false
            }
        }

        let identifier = UUID()
        let randomIdentifier = identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let finalIdentifier = String(randomIdentifier.prefix(8))
        let fileName="cpcp_video_"+finalIdentifier+".mp4"

        let fileUrl = documentsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileUrl)

        // Start recording video
        fileVideoOutput.startRecording(to: fileUrl, recordingDelegate: self)

        // Save the file URL for later use
        self.videoFileURL = fileUrl
    }

    func stopRecording(completion: @escaping (URL?, Error?) -> Void) {
        guard let captureSession = self.captureSession, captureSession.isRunning else {
            completion(nil, CameraControllerError.captureSessionIsMissing)
            return
        }
        guard let fileVideoOutput = self.fileVideoOutput else {
            completion(nil, CameraControllerError.fileVideoOutputNotFound)
            return
        }

        guard fileVideoOutput.isRecording else {
            completion(self.videoFileURL, nil)
            return
        }

        self.videoRecordingCompletion = completion
        fileVideoOutput.stopRecording()
    }
}
