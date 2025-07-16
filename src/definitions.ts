export type CameraPosition = "rear" | "front";

export type FlashMode = CameraPreviewFlashMode;

export enum DeviceType {
  ULTRA_WIDE = "ultraWide",
  WIDE_ANGLE = "wideAngle",
  TELEPHOTO = "telephoto",
  TRUE_DEPTH = "trueDepth",
  DUAL = "dual",
  DUAL_WIDE = "dualWide",
  TRIPLE = "triple",
}

/**
 * Represents a single camera lens on a device. A {@link CameraDevice} can have multiple lenses.
 */
export interface CameraLens {
  /** A human-readable name for the lens, e.g., "Ultra-Wide". */
  label: string;
  /** The type of the camera lens. */
  deviceType: DeviceType;
  /** The focal length of the lens in millimeters. */
  focalLength: number;
  /** The base zoom factor for this lens (e.g., 0.5 for ultra-wide, 1.0 for wide). */
  baseZoomRatio: number;
  /** The minimum zoom factor supported by this specific lens. */
  minZoom: number;
  /** The maximum zoom factor supported by this specific lens. */
  maxZoom: number;
}

/**
 * Represents a physical camera on the device (e.g., the front-facing camera).
 */
export interface CameraDevice {
  /** A unique identifier for the camera device. */
  deviceId: string;
  /** A human-readable name for the camera device. */
  label: string;
  /** The physical position of the camera on the device. */
  position: CameraPosition;
  /** A list of all available lenses for this camera device. */
  lenses: CameraLens[];
  /** The overall minimum zoom factor available across all lenses on this device. */
  minZoom: number;
  /** The overall maximum zoom factor available across all lenses on this device. */
  maxZoom: number;
  /** Identifies whether the device is a logical camera (composed of multiple physical lenses). */
  isLogical: boolean;
}

/**
 * Represents the detailed information of the currently active lens.
 */
export interface LensInfo {
  /** The focal length of the active lens in millimeters. */
  focalLength: number;
  /** The device type of the active lens. */
  deviceType: DeviceType;
  /** The base zoom ratio of the active lens (e.g., 0.5x, 1.0x). */
  baseZoomRatio: number;
  /** The current digital zoom factor applied on top of the base zoom. */
  digitalZoom: number;
}

/**
 * Defines the configuration options for starting the camera preview.
 */
export interface CameraPreviewOptions {
  /** 
   * The parent element to attach the video preview to.
   * @platform web
   */
  parent?: string;
  /** 
   * A CSS class name to add to the preview element.
   * @platform web
   */
  className?: string;
  /** 
   * The width of the preview in pixels. Defaults to the screen width.
   * @platform android, ios, web
   */
  width?: number;
  /** 
   * The height of the preview in pixels. Defaults to the screen height.
   * @platform android, ios, web
   */
  height?: number;
  /** 
   * The horizontal origin of the preview, in pixels.
   * @platform android, ios
   */
  x?: number;
  /** 
   * The vertical origin of the preview, in pixels.
   * @platform android, ios
   */
  y?: number;
  /** 
   * Adjusts the y-position to account for safe areas (e.g., notches).
   * @platform ios
   * @default false
   */
  includeSafeAreaInsets?: boolean;
  /** 
   * If true, places the preview behind the webview.
   * @platform android
   * @default true
   */
  toBack?: boolean;
  /** 
   * Bottom padding for the preview, in pixels.
   * @platform android, ios
   */
  paddingBottom?: number;
  /** 
   * Whether to rotate the preview when the device orientation changes.
   * @platform ios
   * @default true
   */
  rotateWhenOrientationChanged?: boolean;
  /** 
   * The camera to use.
   * @default "rear"
   */
  position?: CameraPosition | string;
  /** 
   * If true, saves the captured image to a file and returns the file path.
   * If false, returns a base64 encoded string.
   * @default false
   */
  storeToFile?: boolean;
  /** 
   * If true, prevents the plugin from rotating the image based on EXIF data.
   * @platform android
   * @default false
   */
  disableExifHeaderStripping?: boolean;
  /** 
   * If true, enables high-resolution image capture.
   * @platform ios
   * @default false
   */
  enableHighResolution?: boolean;
  /** 
   * If true, disables the audio stream, preventing audio permission requests.
   * @default false
   */
  disableAudio?: boolean;
  /** 
   * If true, locks the device orientation while the camera is active.
   * @platform android
   * @default false
   */
  lockAndroidOrientation?: boolean;
  /** 
   * If true, allows the camera preview's opacity to be changed.
   * @platform android, web
   * @default false
   */
  enableOpacity?: boolean;
  /** 
   * If true, enables pinch-to-zoom functionality on the preview.
   * @platform android
   * @default false
   */
  enableZoom?: boolean;
  /** 
   * If true, uses the video-optimized preset for the camera session.
   * @platform ios
   * @default false
   */
  enableVideoMode?: boolean;
  /** 
   * The `deviceId` of the camera to use. If provided, `position` is ignored.
   * @platform ios
   */
  deviceId?: string;
}

/**
 * Defines the options for capturing a picture.
 */
export interface CameraPreviewPictureOptions {
  /** The desired height of the picture in pixels. If not provided, the device default is used. */
  height?: number;
  /** The desired width of the picture in pixels. If not provided, the device default is used. */
  width?: number;
  /** 
   * The quality of the captured image, from 0 to 100.
   * Does not apply to `png` format.
   * @default 85
   */
  quality?: number;
  /** 
   * The format of the captured image.
   * @default "jpeg"
   */
  format?: PictureFormat;
}

export type PictureFormat = "jpeg" | "png";

/** Defines a standard picture size with width and height. */
export interface PictureSize {
  /** The width of the picture in pixels. */
  width: number;
  /** The height of the picture in pixels. */
  height: number;
}

/** Represents the supported picture sizes for a camera facing a certain direction. */
export interface SupportedPictureSizes {
  /** The camera direction ("front" or "rear"). */
  facing: string;
  /** A list of supported picture sizes for this camera. */
  supportedPictureSizes: PictureSize[];
}

/**
 * Defines the options for capturing a sample frame from the camera preview.
 */
export interface CameraSampleOptions {
  /** 
   * The quality of the captured sample, from 0 to 100.
   * @default 85
   */
  quality?: number;
}

/**
 * The available flash modes for the camera.
 * 'torch' is a continuous light mode.
 */
export type CameraPreviewFlashMode =
  | "off"
  | "on"
  | "auto"
  | "torch";

/**
 * Defines the options for setting the camera preview's opacity.
 */
export interface CameraOpacityOptions {
  /** 
   * The opacity percentage, from 0.0 (fully transparent) to 1.0 (fully opaque).
   * @default 1.0
   */
  opacity?: number;
}

/**
 * The main interface for the CameraPreview plugin.
 */
export interface CameraPreviewPlugin {
  /**
   * Starts the camera preview.
   *
   * @param {CameraPreviewOptions} options - The configuration for the camera preview.
   * @returns {Promise<void>} A promise that resolves when the camera preview is started.
   * @since 0.0.1
   */
  start(options: CameraPreviewOptions): Promise<void>;

  /**
   * Stops the camera preview.
   *
   * @returns {Promise<void>} A promise that resolves when the camera preview is stopped.
   * @since 0.0.1
   */
  stop(): Promise<void>;

  /**
   * Captures a picture from the camera.
   *
   * @param {CameraPreviewPictureOptions} options - The options for capturing the picture.
   * @returns {Promise<{ value: string }>} A promise that resolves with the captured image data.
   * The `value` is a base64 encoded string unless `storeToFile` is true, in which case it's a file path.
   * @since 0.0.1
   */
  capture(options: CameraPreviewPictureOptions): Promise<{ value: string }>;

  /**
   * Captures a single frame from the camera preview stream.
   *
   * @param {CameraSampleOptions} options - The options for capturing the sample.
   * @returns {Promise<{ value: string }>} A promise that resolves with the sample image as a base64 encoded string.
   * @since 0.0.1
   */
  captureSample(options: CameraSampleOptions): Promise<{ value: string }>;

  /**
   * Gets the flash modes supported by the active camera.
   *
   * @returns {Promise<{ result: CameraPreviewFlashMode[] }>} A promise that resolves with an array of supported flash modes.
   * @since 0.0.1
   */
  getSupportedFlashModes(): Promise<{
    result: CameraPreviewFlashMode[];
  }>;

  /**
   * Gets the horizontal field of view (FoV) for the active camera.
   * Note: This can be an estimate on some devices.
   *
   * @returns {Promise<{ result: number }>} A promise that resolves with the horizontal field of view in degrees.
   * @since 0.0.1
   */
  getHorizontalFov(): Promise<{
    result: number;
  }>;

  /**
   * Gets the supported picture sizes for all cameras.
   *
   * @returns {Promise<{ supportedPictureSizes: SupportedPictureSizes[] }>} A promise that resolves with the list of supported sizes.
   * @since 7.4.0
   */
  getSupportedPictureSizes(): Promise<{
    supportedPictureSizes: SupportedPictureSizes[];
  }>;

  /**
   * Sets the flash mode for the active camera.
   *
   * @param {{ flashMode: CameraPreviewFlashMode | string }} options - The desired flash mode.
   * @returns {Promise<void>} A promise that resolves when the flash mode is set.
   * @since 0.0.1
   */
  setFlashMode(options: {
    flashMode: CameraPreviewFlashMode | string;
  }): Promise<void>;

  /**
   * Toggles between the front and rear cameras.
   *
   * @returns {Promise<void>} A promise that resolves when the camera is flipped.
   * @since 0.0.1
   */
  flip(): Promise<void>;

  /**
   * Sets the opacity of the camera preview.
   *
   * @param {CameraOpacityOptions} options - The opacity options.
   * @returns {Promise<void>} A promise that resolves when the opacity is set.
   * @since 0.0.1
   */
  setOpacity(options: CameraOpacityOptions): Promise<void>;

  /**
   * Stops an ongoing video recording.
   *
   * @returns {Promise<{ videoFilePath: string }>} A promise that resolves with the path to the recorded video file.
   * @since 0.0.1
   */
  stopRecordVideo(): Promise<{ videoFilePath: string }>;

  /**
   * Starts recording a video.
   *
   * @param {CameraPreviewOptions} options - The options for video recording.
   * @returns {Promise<void>} A promise that resolves when video recording starts.
   * @since 0.0.1
   */
  startRecordVideo(options: CameraPreviewOptions): Promise<void>;

  /**
   * Checks if the camera preview is currently running.
   *
   * @returns {Promise<{ isRunning: boolean }>} A promise that resolves with the running state.
   * @since 7.4.0
   */
  isRunning(): Promise<{ isRunning: boolean }>;

  /**
   * Gets all available camera devices.
   *
   * @returns {Promise<{ devices: CameraDevice[] }>} A promise that resolves with the list of available camera devices.
   * @since 7.4.0
   */
  getAvailableDevices(): Promise<{ devices: CameraDevice[] }>;

  /**
   * Gets the current zoom state, including min/max and current lens info.
   *
   * @returns {Promise<{ min: number; max: number; current: number; lens: LensInfo }>} A promise that resolves with the zoom state.
   * @since 7.4.0
   */
  getZoom(): Promise<{ 
    min: number; 
    max: number; 
    current: number;
    lens: LensInfo;
  }>;

  /**
   * Sets the camera's zoom level.
   *
   * @param {{ level: number; ramp?: boolean }} options - The desired zoom level. `ramp` is currently unused.
   * @returns {Promise<void>} A promise that resolves when the zoom level is set.
   * @since 7.4.0
   */
  setZoom(options: { level: number; ramp?: boolean }): Promise<void>;

  /**
   * Gets the current flash mode.
   *
   * @returns {Promise<{ flashMode: FlashMode }>} A promise that resolves with the current flash mode.
   * @since 7.4.0
   */
  getFlashMode(): Promise<{ flashMode: FlashMode }>;

  /**
   * Removes all registered listeners.
   *
   * @since 7.4.0
   */
  removeAllListeners(): Promise<void>;

  /**
   * Switches the active camera to the one with the specified `deviceId`.
   *
   * @param {{ deviceId: string }} options - The ID of the device to switch to.
   * @returns {Promise<void>} A promise that resolves when the camera is switched.
   * @since 7.4.0
   */
  setDeviceId(options: { deviceId: string }): Promise<void>;

  /**
   * Gets the ID of the currently active camera device.
   *
   * @returns {Promise<{ deviceId: string }>} A promise that resolves with the current device ID.
   * @since 7.4.0
   */
  getDeviceId(): Promise<{ deviceId: string }>;
}
