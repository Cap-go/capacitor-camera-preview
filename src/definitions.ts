import type { PermissionState, PluginListenerHandle } from "@capacitor/core";

export type CameraPosition = "rear" | "front";

export type FlashMode = CameraPreviewFlashMode;

export type GridMode = "none" | "3x3" | "4x4";

export type CameraPositioning = "center" | "top" | "bottom";

export interface CameraPermissionStatus {
  camera: PermissionState;
  microphone?: PermissionState;
}

export interface PermissionRequestOptions {
  disableAudio?: boolean;
  showSettingsAlert?: boolean;
  title?: string;
  message?: string;
  openSettingsButtonTitle?: string;
  cancelButtonTitle?: string;
}

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
   * The aspect ratio of the camera preview, '4:3' or '16:9' or 'fill'.
   * Cannot be set if width or height is provided, otherwise the call will be rejected.
   * Use setPreviewSize to adjust size after starting.
   *
   * @since 2.0.0
   */
  aspectRatio?: "4:3" | "16:9";
  /**
   * The grid overlay to display on the camera preview.
   * @default "none"
   * @since 2.1.0
   */
  gridMode?: GridMode;
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
   * If true, disables the audio stream, preventing audio permission requests.
   * @default true
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
   * If true, disables the visual focus indicator when tapping to focus.
   * @platform android, ios
   * @default false
   */
  disableFocusIndicator?: boolean;
  /**
   * The `deviceId` of the camera to use. If provided, `position` is ignored.
   * @platform ios
   */
  deviceId?: string;
  /**
   * The initial zoom level when starting the camera preview.
   * If the requested zoom level is not available, the native plugin will reject.
   * @default 1.0
   * @platform android, ios
   * @since 2.2.0
   */
  initialZoomLevel?: number;
  /**
   * The vertical positioning of the camera preview.
   * @default "center"
   * @platform android, ios, web
   * @since 2.3.0
   */
  positioning?: CameraPositioning;
  /**
   * If true, enables video capture capabilities when the camera starts.
   * @default false
   * @platform android
   * @since 7.11.0
   */
  enableVideoMode?: boolean;
}

/**
 * Defines the options for capturing a picture.
 */
export interface CameraPreviewPictureOptions {
  /**
   * The maximum height of the picture in pixels. The image will be resized to fit within this height while maintaining aspect ratio.
   * If not specified the captured image will match the preview's visible area.
   */
  height?: number;
  /**
   * The maximum width of the picture in pixels. The image will be resized to fit within this width while maintaining aspect ratio.
   * If not specified the captured image will match the preview's visible area.
   */
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
  /**
   * If true, the captured image will be saved to the user's gallery.
   * @default false
   * @since 7.5.0
   */
  saveToGallery?: boolean;
  /**
   * If true, the plugin will attempt to add GPS location data to the image's EXIF metadata.
   * This may prompt the user for location permissions.
   * @default false
   * @since 7.6.0
   */
  withExifLocation?: boolean;
  /**
   * If true, the plugin will embed a timestamp in the top-right corner of the image.
   * @default false
   * @since 7.17.0
   */
  embedTimestamp?: boolean;
  /**
   * If true, the plugin will embed the current location in the top-right corner of the image.
   * Requires `withExifLocation` to be enabled.
   * @default false
   * @since 7.18.0
   */
  embedLocation?: boolean;
  /**
   * Sets the priority for photo quality vs. capture speed.
   * - "speed": Prioritizes faster capture times, may reduce image quality.
   * - "balanced": Aims for a balance between quality and speed.
   * - "quality": Prioritizes image quality, may reduce capture speed.
   * See https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/photoqualityprioritization for details.
   *
   * @since 7.21.0
   * @platform ios
   * @default "speed"
   */
  photoQualityPrioritization?: "speed" | "balanced" | "quality";
}

/** Represents EXIF data extracted from an image. */
export interface ExifData {
  [key: string]: any;
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
export type CameraPreviewFlashMode = "off" | "on" | "auto" | "torch";

/** Reusable exposure mode type for cross-platform support. */
export type ExposureMode = "AUTO" | "LOCK" | "CONTINUOUS" | "CUSTOM";

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
 * Represents safe area insets for devices.
 * Android: Values are expressed in logical pixels (dp) to match JS layout units.
 * iOS: Values are expressed in physical pixels and exclude status bar.
 */
export interface SafeAreaInsets {
  /** Current device orientation (1 = portrait, 2 = landscape, 0 = unknown). */
  orientation: number;
  /**
   * Orientation-aware notch/camera cutout inset (excluding status bar).
   * In portrait mode: returns top inset (notch at top).
   * In landscape mode: returns left inset (notch at side).
   * Android: Value in dp, iOS: Value in pixels (status bar excluded).
   */
  top: number;
}

/**
 * Canonical device orientation values across platforms.
 */
export type DeviceOrientation =
  | "portrait"
  | "landscape-left"
  | "landscape-right"
  | "portrait-upside-down"
  | "unknown";

/**
 * The main interface for the CameraPreview plugin.
 */
export interface CameraPreviewPlugin {
  /**
   * Starts the camera preview.
   *
   * @param {CameraPreviewOptions} options - The configuration for the camera preview.
   * @returns {Promise<{ width: number; height: number; x: number; y: number }>} A promise that resolves with the preview dimensions.
   * @since 0.0.1
   */
  start(options: CameraPreviewOptions): Promise<{
    /** The width of the preview in pixels. */
    width: number;
    /** The height of the preview in pixels. */
    height: number;
    /** The horizontal origin of the preview, in pixels. */
    x: number;
    /** The vertical origin of the preview, in pixels. */
    y: number;
  }>;

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
   * If `storeToFile` was set to `true` when starting the preview, the returned
   * `value` will be an absolute file path on the device instead of a base64 string. Use getBase64FromFilePath to get the base64 string from the file path.
   *
   * @param {CameraPreviewPictureOptions} options - The options for capturing the picture.
   * @returns {Promise<{ value: string; exif: ExifData }>} Resolves with:
   *   - `value`: base64 string, or file path if `storeToFile` is true
   *   - `exif`: extracted EXIF metadata when available
   * @since 0.0.1
   */
  capture(
    options: CameraPreviewPictureOptions,
  ): Promise<{ value: string; exif: ExifData }>;

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
   * Set the aspect ratio of the camera preview.
   *
   * @param {{ aspectRatio: '4:3' | '16:9'; x?: number; y?: number }} options - The desired aspect ratio and optional position.
   *   - aspectRatio: The desired aspect ratio ('4:3' or '16:9')
   *   - x: Optional x coordinate for positioning. If not provided, view will be auto-centered horizontally.
   *   - y: Optional y coordinate for positioning. If not provided, view will be auto-centered vertically.
   * @returns {Promise<{ width: number; height: number; x: number; y: number }>} A promise that resolves with the actual preview dimensions and position.
   * @since 7.5.0
   * @platform android, ios
   */
  setAspectRatio(options: {
    aspectRatio: "4:3" | "16:9";
    x?: number;
    y?: number;
  }): Promise<{
    width: number;
    height: number;
    x: number;
    y: number;
  }>;

  /**
   * Gets the current aspect ratio of the camera preview.
   *
   * @returns {Promise<{ aspectRatio: '4:3' | '16:9' }>} A promise that resolves with the current aspect ratio.
   * @since 7.5.0
   * @platform android, ios
   */
  getAspectRatio(): Promise<{ aspectRatio: "4:3" | "16:9" }>;

  /**
   * Sets the grid mode of the camera preview overlay.
   *
   * @param {{ gridMode: GridMode }} options - The desired grid mode ('none', '3x3', or '4x4').
   * @returns {Promise<void>} A promise that resolves when the grid mode is set.
   * @since 8.0.0
   */
  setGridMode(options: { gridMode: GridMode }): Promise<void>;

  /**
   * Gets the current grid mode of the camera preview overlay.
   *
   * @returns {Promise<{ gridMode: GridMode }>} A promise that resolves with the current grid mode.
   * @since 8.0.0
   */
  getGridMode(): Promise<{ gridMode: GridMode }>;

  /**
   * Checks the current camera (and optionally microphone) permission status without prompting the system dialog.
   *
   * @param options Set `disableAudio` to `false` to also include microphone status (defaults to `true`).
   * @returns {Promise<CameraPermissionStatus>} A promise resolving to the current authorization states.
   * @since 8.7.0
   */
  checkPermissions(options?: Pick<PermissionRequestOptions, 'disableAudio'>): Promise<CameraPermissionStatus>;

  /**
   * Requests camera (and optional microphone) permissions. If permissions are already granted or denied,
   * the current status is returned without prompting. When `showSettingsAlert` is true and permissions are denied,
   * a platform specific alert guiding the user to the app settings will be presented.
   *
   * @param {PermissionRequestOptions} options - Configuration for the permission request behaviour.
   * @returns {Promise<CameraPermissionStatus>} A promise resolving to the final authorization states.
   * @since 8.7.0
   */
  requestPermissions(
    options?: PermissionRequestOptions,
  ): Promise<CameraPermissionStatus>;

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
   * @param {CameraPreviewOptions} options - The options for video recording. Only iOS.
   * @returns {Promise<void>} A promise that resolves when video recording starts.
   * @since 0.0.1
   */
  startRecordVideo(options: CameraPreviewOptions): Promise<void>;

  /**
   * Checks if the camera preview is currently running.
   *
   * @returns {Promise<{ isRunning: boolean }>} A promise that resolves with the running state.
   * @since 7.5.0
   * @platform android, ios
   */
  isRunning(): Promise<{ isRunning: boolean }>;

  /**
   * Gets all available camera devices.
   *
   * @returns {Promise<{ devices: CameraDevice[] }>} A promise that resolves with the list of available camera devices.
   * @since 7.5.0
   * @platform android, ios
   */
  getAvailableDevices(): Promise<{ devices: CameraDevice[] }>;

  /**
   * Gets the current zoom state, including min/max and current lens info.
   *
   * @returns {Promise<{ min: number; max: number; current: number; lens: LensInfo }>} A promise that resolves with the zoom state.
   * @since 7.5.0
   * @platform android, ios
   */
  getZoom(): Promise<{
    min: number;
    max: number;
    current: number;
    lens: LensInfo;
  }>;

  /**
   * Returns zoom button values for quick switching.
   * - iOS/Android: includes 0.5 if ultra-wide available; 1 and 2 if wide available; 3 if telephoto available
   * - Web: unsupported
   * @since 7.5.0
   * @platform android, ios
   */
  getZoomButtonValues(): Promise<{ values: number[] }>;

  /**
   * Sets the zoom level of the camera.
   *
   * @param {{ level: number; ramp?: boolean; autoFocus?: boolean }} options - The desired zoom level. `ramp` is currently unused. `autoFocus` defaults to true.
   * @returns {Promise<void>} A promise that resolves when the zoom level is set.
   * @since 7.5.0
   * @platform android, ios
   */
  setZoom(options: {
    level: number;
    ramp?: boolean;
    autoFocus?: boolean;
  }): Promise<void>;

  /**
   * Gets the current flash mode.
   *
   * @returns {Promise<{ flashMode: FlashMode }>} A promise that resolves with the current flash mode.
   * @since 7.5.0
   * @platform android, ios
   */
  getFlashMode(): Promise<{ flashMode: FlashMode }>;

  /**
   * Removes all registered listeners.
   *
   * @since 7.5.0
   * @platform android, ios
   */
  removeAllListeners(): Promise<void>;

  /**
   * Switches the active camera to the one with the specified `deviceId`.
   *
   * @param {{ deviceId: string }} options - The ID of the device to switch to.
   * @returns {Promise<void>} A promise that resolves when the camera is switched.
   * @since 7.5.0
   * @platform android, ios
   */
  setDeviceId(options: { deviceId: string }): Promise<void>;

  /**
   * Gets the ID of the currently active camera device.
   *
   * @returns {Promise<{ deviceId: string }>} A promise that resolves with the current device ID.
   * @since 7.5.0
   * @platform android, ios
   */
  getDeviceId(): Promise<{ deviceId: string }>;

  /**
   * Gets the current preview size and position.
   * @returns {Promise<{x: number, y: number, width: number, height: number}>}
   * @since 7.5.0
   * @platform android, ios
   */
  getPreviewSize(): Promise<{
    x: number;
    y: number;
    width: number;
    height: number;
  }>;
  /**
   * Sets the preview size and position.
   * @param options The new position and dimensions.
   * @returns {Promise<{ width: number; height: number; x: number; y: number }>} A promise that resolves with the actual preview dimensions and position.
   * @since 7.5.0
   * @platform android, ios
   */
  setPreviewSize(options: {
    x?: number;
    y?: number;
    width: number;
    height: number;
  }): Promise<{
    width: number;
    height: number;
    x: number;
    y: number;
  }>;

  /**
   * Sets the camera focus to a specific point in the preview.
   *
   * Note: The plugin does not attach any native tap-to-focus gesture handlers. Handle taps in
   * your HTML/JS (e.g., on the overlaying UI), then pass normalized coordinates here.
   *
   * @param {Object} options - The focus options.
   * @param {number} options.x - The x coordinate in the preview view to focus on (0-1 normalized).
   * @param {number} options.y - The y coordinate in the preview view to focus on (0-1 normalized).
   * @returns {Promise<void>} A promise that resolves when the focus is set.
   * @since 7.5.0
   * @platform android, ios
   */
  setFocus(options: { x: number; y: number }): Promise<void>;

  /**
   * Adds a listener for screen resize events.
   * @param {string} eventName - The event name to listen for.
   * @param {Function} listenerFunc - The function to call when the event is triggered.
   * @returns {Promise<PluginListenerHandle>} A promise that resolves with a handle to the listener.
   * @since 7.5.0
   * @platform android, ios
   */
  addListener(
    eventName: "screenResize",
    listenerFunc: (data: {
      width: number;
      height: number;
      x: number;
      y: number;
    }) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Adds a listener for orientation change events.
   * @param {string} eventName - The event name to listen for.
   * @param {Function} listenerFunc - The function to call when the event is triggered.
   * @returns {Promise<PluginListenerHandle>} A promise that resolves with a handle to the listener.
   * @since 7.5.0
   * @platform android, ios
   */
  addListener(
    eventName: "orientationChange",
    listenerFunc: (data: { orientation: DeviceOrientation }) => void,
  ): Promise<PluginListenerHandle>;
  /**
   * Deletes a file at the given absolute path on the device.
   * Use this to quickly clean up temporary images created with `storeToFile`.
   * On web, this is not supported and will throw.
   * @since 7.5.0
   * @platform android, ios
   */
  deleteFile(options: { path: string }): Promise<{ success: boolean }>;

  /**
   * Gets the safe area insets for devices.
   * Returns the orientation-aware notch/camera cutout inset and the current orientation.
   * In portrait mode: returns top inset (notch at top).
   * In landscape mode: returns left inset (notch moved to side).
   * This specifically targets the cutout area (notch, punch hole, etc.) that all modern phones have.
   *
   * Android: Values returned in dp (logical pixels).
   * iOS: Values returned in physical pixels, excluding status bar (only pure notch/cutout size).
   *
   * @platform android, ios
   */
  getSafeAreaInsets(): Promise<SafeAreaInsets>;

  /**
   * Gets the current device orientation in a cross-platform format.
   * @since 7.5.0
   * @platform android, ios
   */
  getOrientation(): Promise<{ orientation: DeviceOrientation }>;

  /**
   * Returns the exposure modes supported by the active camera.
   * Modes can include: 'locked', 'auto', 'continuous', 'custom'.
   * @platform android, ios
   */
  getExposureModes(): Promise<{ modes: ExposureMode[] }>;

  /**
   * Returns the current exposure mode.
   * @platform android, ios
   */
  getExposureMode(): Promise<{ mode: ExposureMode }>;

  /**
   * Sets the exposure mode.
   * @platform android, ios
   */
  setExposureMode(options: { mode: ExposureMode }): Promise<void>;

  /**
   * Returns the exposure compensation (EV bias) supported range.
   * @platform ios, android
   */
  getExposureCompensationRange(): Promise<{
    min: number;
    max: number;
    step: number;
  }>;

  /**
   * Returns the current exposure compensation (EV bias).
   * @platform ios, android
   */
  getExposureCompensation(): Promise<{ value: number }>;

  /**
   * Sets the exposure compensation (EV bias). Value will be clamped to range.
   * @platform ios, android
   */
  setExposureCompensation(options: { value: number }): Promise<void>;
}
