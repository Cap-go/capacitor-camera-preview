import {
  Component,
  computed,
  effect,
  ElementRef,
  inject,
  input,
  OnDestroy,
  OnInit,
  signal,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { Capacitor } from '@capacitor/core';
import {
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardTitle,
  IonFab,
  IonFabButton,
  IonIcon,
  IonSpinner,
  ModalController,
} from '@ionic/angular/standalone';
import {
  type CameraDevice,
  type CameraPosition,
  type FlashMode,
  type LensInfo,
  type PictureFormat,
  type CameraLens,
  type CameraPreviewPictureOptions,
  type GridMode,
} from '@capgo/camera-preview';
import { CapacitorCameraViewService } from '../../core/capacitor-camera-preview.service';

function getDistance(touch1: Touch, touch2: Touch): number {
  const dx = touch1.clientX - touch2.clientX;
  const dy = touch1.clientY - touch2.clientY;
  return Math.sqrt(dx * dx + dy * dy);
}

@Component({
  selector: 'app-camera-modal',
  templateUrl: './camera-modal.component.html',
  styleUrls: ['./camera-modal.component.scss'],
  imports: [
    IonCard,
    IonCardContent,
    IonCardHeader,
    IonCardTitle,
    IonFab,
    IonFabButton,
    IonIcon,
    IonSpinner,
  ],
  host: {
    class: 'camera-modal',
  },
})
export class CameraModalComponent implements OnInit, OnDestroy {
  readonly #cameraViewService = inject(CapacitorCameraViewService);
  readonly #elementRef = inject(ElementRef);
  readonly #modalController = inject(ModalController);

  // Basic camera inputs
  public readonly deviceId = input<string>();
  public readonly position = input<CameraPosition>('rear');
  public readonly quality = input<number>(85);
  public readonly useTripleCameraIfAvailable = input<boolean>(false);
  public readonly initialZoomFactor = input<number>(1.0);
  public readonly x = input<number | null>(null);
  public readonly y = input<number | null>(null);
  public readonly width = input<number>(0);
  public readonly height = input<number>(0);
  public readonly aspectRatio = input<'4:3' | '16:9' | undefined>(
    undefined,
  );

  // Picture settings inputs
  public readonly pictureFormat = input<PictureFormat>('jpeg');
  public readonly pictureQuality = input<number>(85);
  public readonly useCustomSize = input<boolean>(false);
  public readonly pictureWidth = input<number>(1920);
  public readonly pictureHeight = input<number>(1080);

  // Camera behavior inputs
  public readonly opacity = input<number>(100);
  public readonly enableZoom = input<boolean>(false);
  public readonly disableAudio = input<boolean>(true);
  public readonly lockAndroidOrientation = input<boolean>(true);
  public readonly saveToGallery = input<boolean>(false);
  public readonly withExifLocation = input<boolean>(false);
  public readonly gridMode = input<'none' | '3x3' | '4x4'>('none');
  public readonly showBoundary = input<boolean>(false);

  protected readonly cameraStarted = toSignal(
    this.#cameraViewService.cameraStarted,
    {
      requireSync: true,
    },
  );

  protected readonly flashMode = signal<FlashMode>('auto');
  protected readonly isCapturingPhoto = signal(false);
  protected readonly currentZoomFactor = signal(1.0);
  protected readonly minZoom = signal(0.5);
  protected readonly maxZoom = signal(8.0);
  protected readonly availableDevices = signal<CameraDevice[]>([]);
  protected readonly currentDeviceId = signal<string>('');
  protected readonly currentLens = signal<LensInfo | null>(null);
  protected readonly isRunning = signal(false);

  // Video recording and testing state
  protected readonly isRecording = signal(false);
  protected readonly currentOpacity = signal(100);
  protected readonly testResults = signal<string>('');
  protected readonly showTestResults = signal(false);

  // Camera switching functionality
  protected readonly availableCameras = signal<CameraDevice[]>([]);
  protected readonly selectedCameraIndex = signal<number>(0);
  protected readonly currentAspectRatio = signal<'4:3' | '16:9'>('4:3');
  protected readonly currentGridMode = signal<GridMode>('none');
  protected readonly showOverlay = signal<boolean>(true);

  protected readonly canZoomIn = computed(() => {
    return this.currentZoomFactor() + 0.1 <= this.maxZoom();
  });

  protected readonly canZoomOut = computed(() => {
    return this.currentZoomFactor() - 0.1 > this.minZoom();
  });

  protected readonly isWeb = Capacitor.getPlatform() === 'web';
  protected readonly window = window;

  protected readonly isUsingCustomSize = computed(() => {
    return this.width() > 0 && this.height() > 0;
  });

  protected readonly displayAspectRatio = computed(() => {
    // Always show the current aspect ratio (which can be toggled)
    return this.currentAspectRatio();
  });

  #supportedFlashModes = signal<Array<FlashMode>>(['off']);
  #touchStartDistance = 0;
  #touchStartTime = 0;
  #touchStartX = 0;
  #touchStartY = 0;
  #initialZoomFactorOnPinch = 1.0;
  #lastZoomCall = 0;
  #zoomThrottleMs = 100; // Throttle zoom calls to max 20fps

  protected isHalfSize = signal(false);

  // Track current preview position and size for boundary overlay
  protected currentPreviewX = signal(0);
  protected currentPreviewY = signal(0);
  protected currentPreviewWidth = signal(0);
  protected currentPreviewHeight = signal(0);

  // Native-returned position from start() method
  protected nativePreviewX = signal(0);
  protected nativePreviewY = signal(0);
  protected nativePreviewWidth = signal(0);
  protected nativePreviewHeight = signal(0);

  protected async togglePreviewSize(): Promise<void> {
    try {
      if (this.isHalfSize()) {
        // Go to full screen (full device size)
        const newSize = {
          x: 0,
          y: 0,
          width: window.innerWidth,
          height: window.innerHeight,
        };
        const nativeResult =
          await this.#cameraViewService.setPreviewSize(newSize);
        this.isHalfSize.set(false);

        // Update red boundary overlay signals (requested)
        this.currentPreviewX.set(newSize.x);
        this.currentPreviewY.set(newSize.y);
        this.currentPreviewWidth.set(newSize.width);
        this.currentPreviewHeight.set(newSize.height);

        // Update blue boundary overlay signals (native returned)
        this.nativePreviewX.set(nativeResult.x);
        this.nativePreviewY.set(nativeResult.y);
        this.nativePreviewWidth.set(nativeResult.width);
        this.nativePreviewHeight.set(nativeResult.height);

        // Log the difference for debugging
        console.log('Preview Size Difference:', {
          requested: newSize,
          returned: nativeResult,
          difference: {
            x: nativeResult.x - newSize.x,
            y: nativeResult.y - newSize.y,
            width: nativeResult.width - newSize.width,
            height: nativeResult.height - newSize.height,
          },
        });
      } else {
        // Go to small centered preview (200x200 in center)
        const centerX = Math.floor((window.innerWidth - 200) / 2);
        const centerY = Math.floor((window.innerHeight - 200) / 2);
        const newSize = { x: centerX, y: centerY, width: 200, height: 200 };
        const nativeResult =
          await this.#cameraViewService.setPreviewSize(newSize);
        this.isHalfSize.set(true);

        // Update red boundary overlay signals (requested)
        this.currentPreviewX.set(newSize.x);
        this.currentPreviewY.set(newSize.y);
        this.currentPreviewWidth.set(newSize.width);
        this.currentPreviewHeight.set(newSize.height);

        // Update blue boundary overlay signals (native returned)
        this.nativePreviewX.set(nativeResult.x);
        this.nativePreviewY.set(nativeResult.y);
        this.nativePreviewWidth.set(nativeResult.width);
        this.nativePreviewHeight.set(nativeResult.height);

        // Log the difference for debugging
        console.log('Preview Size Difference:', {
          requested: newSize,
          returned: nativeResult,
          difference: {
            x: nativeResult.x - newSize.x,
            y: nativeResult.y - newSize.y,
            width: nativeResult.width - newSize.width,
            height: nativeResult.height - newSize.height,
          },
        });
      }
    } catch (error) {
      console.error('Failed to toggle preview size', error);
    }
  }

  constructor() {
    effect(() => {
      const flashModes = this.#supportedFlashModes();

      if (!flashModes.includes(this.flashMode())) {
        this.flashMode.set((flashModes[0] as FlashMode) ?? 'off');
      }
    });
  }

  async ngOnInit(): Promise<void> {
    await this.startCamera();
  }

  ngOnDestroy(): void {
    this.stop();
  }

  protected async startCamera(): Promise<void> {
    const startOptions: any = {
      parent: 'cameraView',
      deviceId: this.deviceId(),
      position: this.position(),
      enableZoom: this.enableZoom(),
      disableAudio: this.disableAudio(),
      lockAndroidOrientation: this.lockAndroidOrientation(),
      toBack: true,
      gridMode: this.gridMode(),
      storeToFile: true,
    };

    // Only add x and y if they are not null
    if (this.x() !== null) {
      startOptions.x = this.x();
    }
    if (this.y() !== null) {
      startOptions.y = this.y();
    }

    // Initialize aspect ratio based on input
    if (this.aspectRatio()) {
      this.currentAspectRatio.set(this.aspectRatio()!);
    }

    startOptions.aspectRatio = this.currentAspectRatio();

    try {
      const nativeResult = await this.#cameraViewService.start(startOptions);

      // Store native-returned position
      this.nativePreviewX.set(nativeResult.x);
      this.nativePreviewY.set(nativeResult.y);
      this.nativePreviewWidth.set(nativeResult.width);
      this.nativePreviewHeight.set(nativeResult.height);

      // Also update current preview position with native result initially
      this.currentPreviewX.set(nativeResult.x);
      this.currentPreviewY.set(nativeResult.y);
      this.currentPreviewWidth.set(nativeResult.width);
      this.currentPreviewHeight.set(nativeResult.height);

      // Log the difference for debugging
      const expectedX = startOptions.x ?? 0;
      const expectedY = startOptions.y ?? 0;
      const expectedWidth = startOptions.width ?? window.innerWidth;
      const expectedHeight = startOptions.height ?? window.innerHeight;

      console.log('Camera Start Difference:', {
        requested: {
          x: expectedX,
          y: expectedY,
          width: expectedWidth,
          height: expectedHeight,
          aspectRatio: startOptions.aspectRatio,
        },
        returned: nativeResult,
        difference: {
          x: nativeResult.x - expectedX,
          y: nativeResult.y - expectedY,
          width: nativeResult.width - expectedWidth,
          height: nativeResult.height - expectedHeight,
        },
      });

      await Promise.all([
        this.#initializeZoomLimits(),
        this.#initializeFlashModes(),
        this.#initializeDevices(),
        this.#updateRunningStatus(),
        this.#updateCurrentDeviceId(),
        this.#initializeCurrentPreviewSize(),
      ]);

      this.currentZoomFactor.set(this.initialZoomFactor());
      this.currentGridMode.set(this.gridMode());

      // Setup camera switching after devices are loaded
      this.#setupCameraSwitchButtons();
    } catch (error) {
      console.error('Failed to start camera:', error);
      // Close modal and show error
      await this.#modalController.dismiss({
        error: error instanceof Error ? error.message : String(error),
        type: 'error',
      });
    }
  }

  protected async stop(): Promise<void> {
    try {
      await this.#cameraViewService.stop();
    } catch (error) {
      console.warn('Failed to stop camera', error);
    }
  }

  protected async close(): Promise<void> {
    await this.#modalController.dismiss();
  }

  protected async capturePhoto(): Promise<void> {
    if (this.isCapturingPhoto()) return;

    this.isCapturingPhoto.set(true);

    try {
      const quality = this.pictureQuality();
      const format = this.pictureFormat();

      let captureOptions: Partial<CameraPreviewPictureOptions> = {
        quality,
        saveToGallery: this.saveToGallery(),
        withExifLocation: this.withExifLocation(),
      };
      if (format === 'png') {
        captureOptions = { ...captureOptions, ...{ format } };
      }

      captureOptions = {
        ...captureOptions,
        aspectRatio: this.currentAspectRatio(),
      };

      const { value, exif } = await this.#cameraViewService.capture(
        quality,
        captureOptions,
      );

      await this.#modalController.dismiss({
        photo: value,
        exif: exif,
        options: {
          ...captureOptions,
          actualAspectRatio: this.currentAspectRatio(),
        },
        type: 'capture',
      });
    } catch (error) {
      console.error('Failed to capture photo', error);
    } finally {
      this.isCapturingPhoto.set(false);
    }
  }

  protected async captureSample(): Promise<void> {
    if (this.isCapturingPhoto()) return;

    this.isCapturingPhoto.set(true);

    try {
      const quality = this.pictureQuality();
      const photo = await this.#cameraViewService.captureSample(quality);

      await this.#modalController.dismiss({
        photo,
        options: { quality },
        type: 'sample',
      });
    } catch (error) {
      console.error('Failed to capture sample', error);
    } finally {
      this.isCapturingPhoto.set(false);
    }
  }

  protected async flipCamera(): Promise<void> {
    try {
      await this.#cameraViewService.flipCamera();
      await this.#updateCurrentDeviceId();
      await this.#initializeZoomLimits();
      await this.#initializeFlashModes();
    } catch (error) {
      console.error('Failed to flip camera', error);
    }
  }

  protected async zoomIn(): Promise<void> {
    const newZoom = Math.min(this.currentZoomFactor() + 0.1, this.maxZoom());
    await this.setZoom(newZoom, true); // Force immediate zoom for button clicks
  }

  protected async zoomOut(): Promise<void> {
    const newZoom = Math.max(this.currentZoomFactor() - 0.1, this.minZoom());
    await this.setZoom(newZoom, true); // Force immediate zoom for button clicks
  }

  protected async setZoom(
    level: number,
    force: boolean = false,
  ): Promise<void> {
    const now = Date.now();

    // Throttle zoom calls unless forced
    if (!force && now - this.#lastZoomCall < this.#zoomThrottleMs) {
      // Update UI immediately for smooth feedback
      this.currentZoomFactor.set(level);
      return;
    }

    try {
      this.#lastZoomCall = now;
      await this.#cameraViewService.setZoom(level);
      this.currentZoomFactor.set(level);
    } catch (error) {
      console.error('Failed to set zoom', error);
    }
  }

  protected async nextFlashMode(): Promise<void> {
    try {
      const supportedModes = this.#supportedFlashModes();
      const currentIndex = supportedModes.indexOf(this.flashMode());
      const nextIndex = (currentIndex + 1) % supportedModes.length;
      const nextMode = supportedModes[nextIndex] as FlashMode;

      await this.#cameraViewService.setFlashMode(nextMode);
      this.flashMode.set(nextMode);
    } catch (error) {
      console.error('Failed to set flash mode', error);
    }
  }

  protected async toggleAspectRatio(): Promise<void> {
    try {
      const current = this.currentAspectRatio();
      let next: '4:3' | '16:9';

      switch (current) {
        case '4:3':
          default:
          next = '16:9';
          break;
        case '16:9':
          next = '4:3';
          break;
      }

      this.currentAspectRatio.set(next);

      // Instead of restarting camera, just apply the new aspect ratio
      const nativeResult = await this.#cameraViewService.setAspectRatio(next);

      // Update red boundary overlay with new preview size after aspect ratio change
      const newSize = await this.#cameraViewService.getPreviewSize();
      this.currentPreviewX.set(newSize.x);
      this.currentPreviewY.set(newSize.y);
      this.currentPreviewWidth.set(newSize.width);
      this.currentPreviewHeight.set(newSize.height);

      // Update blue boundary overlay signals (native returned)
      this.nativePreviewX.set(nativeResult.x);
      this.nativePreviewY.set(nativeResult.y);
      this.nativePreviewWidth.set(nativeResult.width);
      this.nativePreviewHeight.set(nativeResult.height);
    } catch (error) {
      console.error('Failed to toggle aspect ratio', error);
    }
  }

  protected async toggleGridMode(): Promise<void> {
    try {
      const currentMode = this.currentGridMode();
      let nextMode: GridMode;

      switch (currentMode) {
        case 'none':
          nextMode = '3x3';
          break;
        case '3x3':
          nextMode = '4x4';
          break;
        case '4x4':
          nextMode = 'none';
          break;
        default:
          nextMode = 'none';
      }

      this.currentGridMode.set(nextMode);
      await this.#cameraViewService.setGridMode(nextMode);
    } catch (error) {
      console.error('Failed to toggle grid mode', error);
    }
  }

  protected toggleOverlay(): void {
    this.showOverlay.set(!this.showOverlay());
  }

  protected async switchToDevice(deviceId: string): Promise<void> {
    try {
      await this.#cameraViewService.setDeviceId(deviceId);
      await this.#updateCurrentDeviceId();
      await this.#initializeZoomLimits();
      await this.#initializeFlashModes();

      // Update selected camera index to match the new device
      const cameras = this.availableCameras();
      const foundIndex = cameras.findIndex(
        (camera) => camera.deviceId === deviceId,
      );
      if (foundIndex >= 0) {
        this.selectedCameraIndex.set(foundIndex);
      }
    } catch (error) {
      console.error('Failed to switch device', error);
    }
  }

  protected async refreshDeviceInfo(): Promise<void> {
    await Promise.all([
      this.#initializeDevices(),
      this.#updateRunningStatus(),
      this.#updateCurrentDeviceId(),
    ]);
  }

  protected async testAllFeatures(): Promise<void> {
    if (this.showTestResults()) {
      // Hide test results
      this.showTestResults.set(false);
      this.testResults.set('');
      return;
    }

    let results = '=== Camera Modal Test Results ===\n';

    try {
      // Test running status
      const running = await this.#cameraViewService.isRunning();
      results += `\n✓ Camera running: ${running}`;

      // Test current device ID
      const currentId = await this.#cameraViewService.getDeviceId();
      results += `\n✓ Current device: ${currentId}`;

      // Test zoom capabilities and lens info
      const zoomData = await this.#cameraViewService.getZoom();
      results += `\n✓ Zoom: ${zoomData.min} - ${zoomData.max} (current: ${zoomData.current})`;
      results += `\n✓ Lens: ${zoomData.lens.deviceType} (${zoomData.lens.baseZoomRatio}x base)`;
      results += `\n  - Focal length: ${zoomData.lens.focalLength}mm`;
      results += `\n  - Digital zoom: ${zoomData.lens.digitalZoom}x`;

      // Test flash mode
      const flashMode = await this.#cameraViewService.getFlashMode();
      results += `\n✓ Flash mode: ${flashMode}`;

      // Test device information
      const devices = await this.#cameraViewService.getAvailableDevices();
      results += `\n✓ Available devices: ${devices.length}`;

      devices.forEach((device, index) => {
        results += `\n  ${index + 1}. ${device.label} (${device.position})`;
        results += `\n     Lenses: ${device.lenses.length}`;
        results += `\n     Zoom range: ${device.minZoom}x - ${device.maxZoom}x`;
        device.lenses.forEach((lens) => {
          results += `\n       - ${lens.deviceType} (${lens.baseZoomRatio}x)`;
        });
      });

      this.testResults.set(results);
      this.showTestResults.set(true);
    } catch (error) {
      results += `\n✗ Error during testing: ${error}`;
      this.testResults.set(results);
      this.showTestResults.set(true);
    }
  }

  protected async testLensInfo(): Promise<void> {
    if (this.showTestResults()) {
      // Hide test results
      this.showTestResults.set(false);
      this.testResults.set('');
      return;
    }

    try {
      let results = `\n=== Lens Information Test ===`;

      // Get current lens info from zoom data
      const zoomData = await this.#cameraViewService.getZoom();
      results += `\n✓ Current lens info:`;
      results += `\n  Type: ${zoomData.lens.deviceType}`;
      results += `\n  Base Zoom: ${zoomData.lens.baseZoomRatio}x`;
      results += `\n  Digital Zoom: ${zoomData.lens.digitalZoom}x`;
      results += `\n  Focal Length: ${zoomData.lens.focalLength}mm`;

      // Get available lenses from device data
      const devices = await this.#cameraViewService.getAvailableDevices();
      const currentDeviceId = await this.#cameraViewService.getDeviceId();
      const currentDevice = devices.find((d) => d.deviceId === currentDeviceId);

      if (currentDevice) {
        results += `\n✓ Available lenses for ${currentDevice.label}: ${currentDevice.lenses.length}`;
        currentDevice.lenses.forEach((lens, index) => {
          results += `\n  ${index + 1}. ${lens.label}`;
          results += `\n     Type: ${lens.deviceType}`;
          results += `\n     Base Zoom: ${lens.baseZoomRatio}x`;
          results += `\n     Zoom Range: ${lens.minZoom}x - ${lens.maxZoom}x`;
          results += `\n     Focal Length: ${lens.focalLength}mm`;
        });
      }

      this.testResults.set(results);
      this.showTestResults.set(true);
    } catch (error) {
      const results = `\n✗ Lens info test failed: ${error}`;
      this.testResults.set(results);
      this.showTestResults.set(true);
    }
  }

  protected async startRecording(): Promise<void> {
    try {
      await this.#cameraViewService.startRecordVideo({
        position: this.position(),
        deviceId: this.currentDeviceId(),
        disableAudio: this.disableAudio(),
      });
      this.isRecording.set(true);
      if (this.showTestResults()) {
        const results = this.testResults() + `\n✓ Video recording started`;
        this.testResults.set(results);
      }
    } catch (error) {
      if (this.showTestResults()) {
        const results =
          this.testResults() + `\n✗ Failed to start recording: ${error}`;
        this.testResults.set(results);
      }
      console.error('Failed to start recording:', error);
    }
  }

  protected async stopRecording(): Promise<void> {
    try {
      const result = await this.#cameraViewService.stopRecordVideo();
      this.isRecording.set(false);
      this.#modalController.dismiss({
        video: result.videoFilePath,
        type: 'video',
      });
    } catch (error) {
      if (this.showTestResults()) {
        const results =
          this.testResults() + `\n✗ Failed to stop recording: ${error}`;
        this.testResults.set(results);
      }
      console.error('Failed to stop recording:', error);
    }
  }

  protected getCameraSwitchLabel(index: number): string {
    const cameras = this.availableCameras();
    if (index < cameras.length) {
      const camera = cameras[index];
      // Use the primary lens base zoom ratio for the label
      const primaryLens =
        camera.lenses.find((l) => l.deviceType === 'wideAngle') ||
        camera.lenses[0];
      return `${primaryLens?.baseZoomRatio || 1}x`;
    }
    return `${index + 1}`;
  }

  async #initializeZoomLimits(): Promise<void> {
    try {
      const zoomData = await this.#cameraViewService.getZoom();
      this.minZoom.set(zoomData.min);
      this.maxZoom.set(zoomData.max);
      // Do not set currentZoomFactor from here, as it's managed locally
      this.currentLens.set(zoomData.lens);
    } catch {
      console.warn('Failed to get zoom limits');
    }
  }

  async #initializeFlashModes(): Promise<void> {
    try {
      const flashModes = await this.#cameraViewService.getSupportedFlashModes();
      this.#supportedFlashModes.set(flashModes);

      const currentFlashMode = await this.#cameraViewService.getFlashMode();
      this.flashMode.set(currentFlashMode);
    } catch {
      console.warn('Failed to get flash modes');
    }
  }

  async #updateCurrentDeviceId(): Promise<void> {
    try {
      const deviceId = await this.#cameraViewService.getDeviceId();
      this.currentDeviceId.set(deviceId);
    } catch {
      console.warn('Failed to get current device ID');
    }
  }

  async #updateRunningStatus(): Promise<void> {
    try {
      const running = await this.#cameraViewService.isRunning();
      this.isRunning.set(running);
    } catch (error) {
      console.warn('Failed to get running status', error);
    }
  }

  async #initializeDevices(): Promise<void> {
    try {
      const devices = await this.#cameraViewService.getAvailableDevices();
      this.availableDevices.set(devices);
    } catch (error) {
      console.warn('Failed to get available devices', error);
    }
  }

  /**
   * Setup camera switch buttons based on available devices
   * Groups cameras by position and assigns them as zoom levels
   */
  #setupCameraSwitchButtons(): void {
    const devices = this.availableDevices();

    // Filter cameras by current position preference
    const currentPosition = this.position();
    const currentPositionDevices = devices.filter(
      (device) => device.position === currentPosition,
    );

    if (currentPositionDevices.length === 0) return;

    // Use the found devices for the camera switching UI
    this.availableCameras.set(currentPositionDevices);

    // Set initial camera selection to match current device if possible
    const currentDeviceId = this.currentDeviceId();
    let initialIndex = 0;
    if (currentDeviceId !== null && currentDeviceId !== undefined) {
      const foundIndex = currentPositionDevices.findIndex(
        (camera) => camera.deviceId === currentDeviceId,
      );
      if (foundIndex >= 0) {
        initialIndex = foundIndex;
      }
    }
    this.selectedCameraIndex.set(initialIndex);
  }

  // Touch event handlers for pinch-to-zoom
  protected handleTouchStart(event: TouchEvent): void {
    if (event.touches.length === 1) {
      this.#touchStartTime = Date.now();
      this.#touchStartX = event.touches[0].clientX;
      this.#touchStartY = event.touches[0].clientY;
    }
    if (event.touches.length === 2) {
      this.#touchStartDistance = getDistance(
        event.touches[0],
        event.touches[1],
      );
      this.#initialZoomFactorOnPinch = this.currentZoomFactor();
      event.preventDefault();
    }
  }

  protected handleTouchMove(event: TouchEvent): void {
    if (event.touches.length === 2 && this.#touchStartDistance > 0) {
      const currentDistance = getDistance(event.touches[0], event.touches[1]);
      const scale = currentDistance / this.#touchStartDistance;

      const newZoom = Math.max(
        this.minZoom(),
        Math.min(this.maxZoom(), this.#initialZoomFactorOnPinch * scale),
      );

      this.setZoom(newZoom);
      event.preventDefault(); // Prevent scrolling during pinch
    }
  }

  public async handleTouchEnd(event?: TouchEvent) {
    // Handle pinch-to-zoom end
    if (this.#touchStartDistance > 0) {
      // Ensure final zoom level is set on native side
      this.setZoom(this.currentZoomFactor(), true);
      this.#touchStartDistance = 0;
      return;
    }

    // Handle tap-to-focus
    if (
      event &&
      event.changedTouches.length === 1 &&
      this.#touchStartTime > 0
    ) {
      const touchEndTime = Date.now();
      const touchDuration = touchEndTime - this.#touchStartTime;

      // Check if it's a tap (not a long press or drag)
      if (touchDuration < 300) {
        const touch = event.changedTouches[0];
        const deltaX = Math.abs(touch.clientX - this.#touchStartX);
        const deltaY = Math.abs(touch.clientY - this.#touchStartY);

        // Check if finger didn't move much (not a swipe)
        if (deltaX < 10 && deltaY < 10) {
          await this.setFocusAtPoint(touch.clientX, touch.clientY);
        }
      }
    }

    this.#touchStartTime = 0;
  }

  protected getDisplayLenses(device: CameraDevice): CameraLens[] {
    return device.lenses;
  }

  async #initializeGridMode(): Promise<void> {
    try {
      const gridMode = await this.#cameraViewService.getGridMode();
      this.currentGridMode.set(gridMode);
    } catch (error) {
      console.warn('Failed to get grid mode', error);
    }
  }

  async #initializeCurrentPreviewSize(): Promise<void> {
    try {
      const currentSize = await this.#cameraViewService.getPreviewSize();
      this.currentPreviewX.set(currentSize.x);
      this.currentPreviewY.set(currentSize.y);
      this.currentPreviewWidth.set(currentSize.width);
      this.currentPreviewHeight.set(currentSize.height);
    } catch (error) {
      console.warn('Failed to get current preview size', error);
      // Fallback to input values
      this.currentPreviewX.set(this.x() ?? 0);
      this.currentPreviewY.set(this.y() ?? 0);
      this.currentPreviewWidth.set(this.width());
      this.currentPreviewHeight.set(this.height());
    }
  }

  private async setFocusAtPoint(clientX: number, clientY: number) {
    try {
      // Use the actual native preview bounds, not the cameraView element
      const nativeX = this.nativePreviewX();
      const nativeY = this.nativePreviewY();
      const nativeWidth = this.nativePreviewWidth();
      const nativeHeight = this.nativePreviewHeight();

      // Check if we have valid native bounds
      if (nativeWidth <= 0 || nativeHeight <= 0) {
        console.warn('Native preview bounds not available');
        return;
      }

      // Check if the click is within the native preview bounds
      if (
        clientX < nativeX ||
        clientX > nativeX + nativeWidth ||
        clientY < nativeY ||
        clientY > nativeY + nativeHeight
      ) {
        console.log('Click outside native preview bounds');
        return;
      }

      // Calculate normalized coordinates (0-1) relative to native preview
      const normalizedX = (clientX - nativeX) / nativeWidth;
      const normalizedY = (clientY - nativeY) / nativeHeight;

      await this.#cameraViewService.setFocus({
        x: normalizedX,
        y: normalizedY,
      });
    } catch (error) {
      // Silently fail if focus is not supported
    }
  }
}
