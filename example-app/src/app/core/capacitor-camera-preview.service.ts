import { Injectable } from '@angular/core';
// import { PermissionState } from '@capacitor/core';
import {
  // BarcodeDetectionData,
  CameraDevice,
  CameraSessionConfiguration,
  CameraPreview,
  CameraPreviewPlugin,
  CameraPreviewPictureOptions,
  FlashMode,
  PictureFormat,
} from '@capgo/camera-preview';
import type { CameraLens } from '../../../../src/definitions';
import { BehaviorSubject } from 'rxjs';
// import { BehaviorSubject, Subject } from 'rxjs';

@Injectable({
  providedIn: 'root',
})
export class CapacitorCameraViewService {
  #cameraView: CameraPreviewPlugin;
  // #barcodeData = new Subject<BarcodeDetectionData>();

  /**
   * Observable for barcode detection events
   */
  // readonly barcodeData = this.#barcodeData.asObservable();

  readonly #cameraStarted = new BehaviorSubject<boolean>(false);
  public readonly cameraStarted = this.#cameraStarted.asObservable();

  constructor() {
    this.#cameraView = CameraPreview;

    // Add event listeners
    this.#cameraView.removeAllListeners().then(() => {
      // this.#cameraView.addListener('barcodeDetected', (event) => {
      //   this.#barcodeData.next(event);
      // });
    });

    this.cameraStarted.subscribe((started) => {
      document.body.classList.toggle('camera-running', started);
    });
  }

  /**
   * Start the camera view
   * @param options Configuration options for the camera session
   */
  async start(options: CameraSessionConfiguration = {}): Promise<void> {
    await this.#cameraView.start(options);
    this.#cameraStarted.next(true);
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

  /**
   * Capture a photo from the camera view
   * @param quality The quality of the photo (0-100)
   * @param options Additional capture options
   * @returns A base64 encoded string of the captured photo
   */
  async capture(quality: number = 90, options?: Partial<CameraPreviewPictureOptions>): Promise<string> {
    const captureOptions: CameraPreviewPictureOptions = {
      quality,
      ...options,
    };
    return (await this.#cameraView.capture(captureOptions)).value;
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
   * Get current zoom capabilities and level
   * @returns Object with min, max and current zoom levels
   */
  async getZoom(): Promise<{ min: number; max: number; current: number }> {
    return this.#cameraView.getZoom();
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
   * Get current logical zoom capabilities and level
   * @returns Object with min, max and current zoom levels
   */
  async getZoomLogical(): Promise<{ min: number; max: number; current: number }> {
    return this.#cameraView.getZoomLogical();
  }

  /**
   * Set the logical zoom level
   * @param level The logical zoom level to set
   */
  async setZoomLogical(level: number): Promise<void> {
    return this.#cameraView.setZoomLogical({ level });
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
  async startRecordVideo(options: CameraSessionConfiguration = {}): Promise<void> {
    return this.#cameraView.startRecordVideo(options);
  }

  /**
   * Stop video recording
   * @returns Object containing the video file path
   */
  async stopRecordVideo(): Promise<{ videoFilePath: string }> {
    return this.#cameraView.stopRecordVideo();
  }

  /**
   * Get available camera lenses for the current camera position
   * @returns Array of available camera lenses
   */
  async getAvailableLenses(): Promise<Array<CameraLens>> {
    return (await this.#cameraView.getAvailableLenses()).lenses;
  }

  /**
   * Get the currently active lens based on zoom level
   * @returns The currently active camera lens
   */
  async getCurrentLens(): Promise<CameraLens> {
    return (await this.#cameraView.getCurrentLens()).lens;
  }

  /**
   * Remove all event listeners
   */
  async removeAllListeners(): Promise<void> {
    return this.#cameraView.removeAllListeners();
  }
  // /**
  //  * Check camera permission status
  //  * @returns The current permission status
  //  */
  // async checkPermissions(): Promise<PermissionState> {
  //   return (await this.#cameraView.checkPermissions()).camera;
  // }

  // /**
  //  * Request camera permissions
  //  * @returns The updated permission status after request
  //  */
  // async requestPermissions(): Promise<PermissionState> {
  //   return (await this.#cameraView.requestPermissions()).camera;
  // }
}
