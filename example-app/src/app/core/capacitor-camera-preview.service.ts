import { Injectable, NgZone } from '@angular/core';
import {
  CameraDevice,
  CameraPreview,
  CameraPreviewOptions,
  CameraPreviewPictureOptions,
  ExifData,
  FlashMode,
  LensInfo,
  CameraPreviewPlugin,
  GridMode,
  ExposureMode,
  CameraPermissionStatus,
  PermissionRequestOptions,
  FaceDetectionOptions,
  FaceDetectionCapabilities,
  FaceDetectionEvent,
  getBase64FromFilePath,
  deleteFile,
} from '@capgo/camera-preview';
import { Capacitor } from '@capacitor/core';
import { BehaviorSubject } from 'rxjs';

@Injectable({
  providedIn: 'root',
})
export class CapacitorCameraViewService {
  #cameraView: CameraPreviewPlugin;
  #isWeb = Capacitor.getPlatform() === 'web';
  #zoomButtonsWarningShown = false;

  readonly #cameraStarted = new BehaviorSubject<boolean>(false);
  public readonly cameraStarted = this.#cameraStarted.asObservable();

  constructor(private ngZone: NgZone) {
    this.#cameraView = CameraPreview;

    // Add event listeners
    this.#cameraView.removeAllListeners();
    this.cameraStarted.subscribe((started) => {
      this.ngZone.runOutsideAngular(() => {
        requestAnimationFrame(() => {
          document.body.classList.toggle('camera-running', started);
          // Force layout recalculation
          document.body.offsetHeight;
        });
      });
    });
  }

  /**
   * Start the camera view
   * @param options Configuration options for the camera session
   */
  async start(options: CameraPreviewOptions = {}): Promise<{
    width: number;
    height: number;
    x: number;
    y: number;
  }> {
    const result = await this.#cameraView.start(options);
    this.#cameraStarted.next(true);
    return result;
  }

  /**
   * Stop the camera view
   */
  async stop(): Promise<void> {
    await this.#cameraView.stop();
    this.#cameraStarted.next(false);
  }

  /**
   * Check if the camera view is running
   */
  async isRunning(): Promise<boolean> {
    return (await this.#cameraView.isRunning()).isRunning;
  }

  async checkPermissions(options?: {
    disableAudio?: boolean;
  }): Promise<CameraPermissionStatus> {
    return this.#cameraView.checkPermissions(options ?? {});
  }

  async requestPermissions(
    options?: PermissionRequestOptions,
  ): Promise<CameraPermissionStatus> {
    return this.#cameraView.requestPermissions(options ?? {});
  }

  /**
   * Capture a photo from the camera view
   * @param quality The quality of the photo (0-100)
   * @param options Additional capture options
   * @returns A base64 encoded string of the captured photo
   */
  async capture(
    quality: number = 90,
    options?: Partial<CameraPreviewPictureOptions>,
  ): Promise<{ value: string; exif: ExifData }> {
    const captureOptions: CameraPreviewPictureOptions = {
      quality,
      ...options,
    };
    return this.#cameraView.capture(captureOptions);
  }

  /**
   * Capture a sample from the camera view
   * @param quality The quality of the sample (0-100)
   * @returns A base64 encoded string of the captured sample
   */
  async captureSample(quality: number = 90): Promise<string> {
    return (await this.#cameraView.captureSample({ quality })).value;
  }

  /**
   * Get a list of available camera devices
   * @returns Array of available camera devices
   */
  async getAvailableDevices(): Promise<Array<CameraDevice>> {
    return (await this.#cameraView.getAvailableDevices()).devices;
  }
  /**
   * Switch between front and back camera
   */
  async flipCamera(): Promise<void> {
    await this.#cameraView.flip();
  }

  /**
   * Get current zoom capabilities and level with lens information
   * @returns Object with min, max, current zoom levels and lens info
   */
  async getZoom(): Promise<{
    min: number;
    max: number;
    current: number;
    lens: LensInfo;
  }> {
    return this.#cameraView.getZoom();
  }

  async getZoomButtonValues(): Promise<number[]> {
    if (this.#isWeb) {
      return [];
    }

    try {
      const result = await (this.#cameraView as any).getZoomButtonValues();
      const values = Array.isArray(result?.values) ? result.values : [];
      return values.filter(
        (value: number): value is number => typeof value === 'number' && !Number.isNaN(value),
      );
    } catch (error) {
      if (!this.#zoomButtonsWarningShown) {
        console.warn('getZoomButtonValues not available on this platform', error);
        this.#zoomButtonsWarningShown = true;
      }
      return [];
    }
  }

  /**
   * Set the zoom level
   * @param level The zoom level to set
   * @param ramp Whether to animate the zoom level change, defaults to true (iOS / Android only)
   */
  async setZoom(level: number, ramp?: boolean): Promise<void> {
    return this.#cameraView.setZoom({ level, ramp });
  }

  /**
   * Get the current flash mode
   * @returns The current flash mode
   */
  async getFlashMode(): Promise<FlashMode> {
    return (await this.#cameraView.getFlashMode()).flashMode;
  }

  /**
   * Get all supported flash modes for the current device
   * @returns Array of supported flash modes
   */
  async getSupportedFlashModes(): Promise<FlashMode[]> {
    return (await this.#cameraView.getSupportedFlashModes()).result;
  }

  async setAspectRatio(
    aspectRatio: '4:3' | '16:9',
    x?: number,
    y?: number,
  ): Promise<{
    width: number;
    height: number;
    x: number;
    y: number;
  }> {
    const options: any = { aspectRatio };
    if (x !== undefined && y !== undefined) {
      options.x = x;
      options.y = y;
    }
    return CameraPreview.setAspectRatio(options);
  }

  async getAspectRatio(): Promise<{ aspectRatio: '4:3' | '16:9' }> {
    return CameraPreview.getAspectRatio();
  }

  async setFocus(options: { x: number; y: number }): Promise<void> {
    return this.#cameraView.setFocus(options);
  }

  /**
   * Set the flash mode
   * @param mode The flash mode to set
   */
  async setFlashMode(mode: FlashMode): Promise<void> {
    return this.#cameraView.setFlashMode({ flashMode: mode });
  }

  /**
   * Get the current device ID
   * @returns The current device ID
   */
  async getDeviceId(): Promise<string> {
    return (await this.#cameraView.getDeviceId()).deviceId;
  }

  /**
   * Set/swap to a specific device ID
   * @param deviceId The device ID to switch to
   */
  async setDeviceId(deviceId: string): Promise<void> {
    return this.#cameraView.setDeviceId({ deviceId });
  }

  /**
   * Get horizontal field of view
   * @returns The horizontal field of view
   */
  async getHorizontalFov(): Promise<any> {
    return (await this.#cameraView.getHorizontalFov()).result;
  }

  /**
   * Get supported picture sizes for available devices
   * @returns Object containing supported picture sizes for each device
   */
  async getSupportedPictureSizes(): Promise<any> {
    return await this.#cameraView.getSupportedPictureSizes();
  }

  /**
   * Set camera opacity
   * @param opacity The opacity value (0.0 - 1.0)
   */
  async setOpacity(opacity: number): Promise<void> {
    return this.#cameraView.setOpacity({ opacity });
  }

  /**
   * Start video recording
   * @param options Configuration options for video recording
   */
  async startRecordVideo(options: CameraPreviewOptions = {}): Promise<void> {
    return this.#cameraView.startRecordVideo(options);
  }

  /**
   * Stop video recording
   * @returns Object containing the video file path
   */
  async stopRecordVideo(): Promise<{ videoFilePath: string }> {
    return this.#cameraView.stopRecordVideo();
  }

  async getPreviewSize(): Promise<{
    x: number;
    y: number;
    width: number;
    height: number;
  }> {
    return this.#cameraView.getPreviewSize();
  }
  async setPreviewSize(options: {
    x: number;
    y: number;
    width: number;
    height: number;
  }): Promise<{
    width: number;
    height: number;
    x: number;
    y: number;
  }> {
    return this.#cameraView.setPreviewSize(options);
  }

  /**
   * Remove all event listeners
   */
  async removeAllListeners(): Promise<void> {
    return this.#cameraView.removeAllListeners();
  }

  /**
   * Set the grid mode for the camera preview overlay
   * @param gridMode The grid mode to set ('none', '3x3', or '4x4')
   */
  async setGridMode(gridMode: GridMode): Promise<void> {
    return (this.#cameraView as any).setGridMode({ gridMode });
  }

  /**
   * Get the current grid mode of the camera preview overlay
   * @returns The current grid mode
   */
  async getGridMode(): Promise<GridMode> {
    const result = await (this.#cameraView as any).getGridMode();
    return result.gridMode;
  }

  async getBase64FromFilePath(filePath: string): Promise<string> {
    return getBase64FromFilePath(filePath);
  }

  async deleteFile(filePath: string): Promise<boolean> {
    return deleteFile(filePath);
  }

  /**
   * Read a video file and return its contents as base64
   * @param filePath Path to the video file
   * @returns Base64 encoded string of the video file
   */
  async readVideoFile(filePath: string): Promise<string> {
    return this.getBase64FromFilePath(filePath);
  }

  // ===== Exposure controls =====
  async getExposureModes(): Promise<ExposureMode[]> {
    const { modes } = await this.#cameraView.getExposureModes();
    return modes;
  }

  async getExposureMode(): Promise<ExposureMode> {
    const { mode } = await this.#cameraView.getExposureMode();
    return mode;
  }

  async setExposureMode(mode: ExposureMode): Promise<void> {
    await this.#cameraView.setExposureMode({ mode });
  }

  async getExposureCompensationRange(): Promise<{ min: number; max: number; step: number }> {
    return await this.#cameraView.getExposureCompensationRange();
  }

  async getExposureCompensation(): Promise<number> {
    const { value } = await this.#cameraView.getExposureCompensation();
    return value;
  }

  async setExposureCompensation(value: number): Promise<void> {
    await this.#cameraView.setExposureCompensation({ value });
  }

  // ===== Face Detection Controls =====
  /**
   * Enable face detection on the camera preview
   * @param options Configuration options for face detection
   */
  async enableFaceDetection(options?: FaceDetectionOptions): Promise<void> {
    return this.#cameraView.enableFaceDetection(options);
  }

  /**
   * Disable face detection on the camera preview
   */
  async disableFaceDetection(): Promise<void> {
    return this.#cameraView.disableFaceDetection();
  }

  /**
   * Check if face detection is currently enabled
   */
  async isFaceDetectionEnabled(): Promise<boolean> {
    const { enabled } = await this.#cameraView.isFaceDetectionEnabled();
    return enabled;
  }

  /**
   * Get face detection capabilities for the current device
   */
  async getFaceDetectionCapabilities(): Promise<FaceDetectionCapabilities> {
    return this.#cameraView.getFaceDetectionCapabilities();
  }

  /**
   * Listen to face detection events
   * @param callback Callback function to be called when faces are detected
   */
  async onFacesDetected(callback: (event: FaceDetectionEvent) => void): Promise<any> {
    return this.#cameraView.addListener('onFacesDetected', callback);
  }
}
