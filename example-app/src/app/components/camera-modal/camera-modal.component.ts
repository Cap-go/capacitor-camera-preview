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
  viewChild,
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
  IonSelect,
  IonSelectOption,
  IonSpinner,
  ModalController,
} from '@ionic/angular/standalone';
import {
  type CameraDevice,
  type CameraLens,
  type CameraPosition,
  type FlashMode,
  type PictureFormat
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
    IonSelect,
    IonSelectOption,
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

  // Picture settings inputs
  public readonly pictureFormat = input<PictureFormat>('jpeg');
  public readonly pictureQuality = input<number>(85);
  public readonly useCustomSize = input<boolean>(false);
  public readonly pictureWidth = input<number>(1920);
  public readonly pictureHeight = input<number>(1080);

  // Camera behavior inputs
  public readonly opacity = input<number>(100);
  public readonly enableZoom = input<boolean>(false);
  public readonly disableAudio = input<boolean>(false);
  public readonly enableHighResolution = input<boolean>(false);
  public readonly lockAndroidOrientation = input<boolean>(false);

  protected readonly cameraStarted = toSignal(
    this.#cameraViewService.cameraStarted,
    {
      requireSync: true,
    },
  );

  protected readonly flashMode = signal<FlashMode>('auto');
  protected readonly isCapturingPhoto = signal(false);
  protected readonly currentZoomFactor = signal(1.0);
  protected readonly MIN_ZOOM = 0.5;
  protected readonly MAX_ZOOM = 8.0;
  protected readonly minZoom = signal(this.MIN_ZOOM);
  protected readonly maxZoom = signal(this.MAX_ZOOM);
  protected readonly minZoomReel = signal(1.0);
  protected readonly maxZoomReel = signal(8.0);
  protected readonly availableDevices = signal<CameraDevice[]>([]);
  protected readonly currentDeviceId = signal<string>('');
  protected readonly availableLenses = signal<CameraLens[]>([]);
  protected readonly currentLens = signal<CameraLens | null>(null);
  protected readonly isRunning = signal(false);

  // Video recording and testing state
  protected readonly isRecording = signal(false);
  protected readonly currentOpacity = signal(100);
  protected readonly testResults = signal<string>('');
  protected readonly showTestResults = signal(false);

  // Camera switching functionality
  protected readonly availableCameras = signal<CameraDevice[]>([]);
  protected readonly selectedCameraIndex = signal<number>(0);

  protected readonly canZoomIn = computed(() => {
    return this.currentZoomFactor() + 0.1 <= this.maxZoom();
    return this.currentZoomFactor() + 0.1 <= this.maxZoom();
  });

  protected readonly canZoomOut = computed(() => {
    return this.currentZoomFactor() - 0.1 >= this.minZoom();
    return this.currentZoomFactor() - 0.1 >= this.minZoom();
  });

  protected readonly isWeb = Capacitor.getPlatform() === 'web';

  #supportedFlashModes = signal<Array<FlashMode>>(['off']);
  #touchStartDistance = 0;
  #initialZoomFactorOnPinch = 1.0;

  constructor() {
    effect(() => {
      const flashModes = this.#supportedFlashModes();

      if (!flashModes.includes(this.flashMode())) {
        this.flashMode.set((flashModes[0] as FlashMode) ?? 'off');
      }
    });
  }

  public ngOnInit() {
    this.startCamera().catch((error) => {
      console.error('Failed to start camera', error);
      this.#modalController.dismiss();
    });

    this.#initializeEventListeners();
  }

  public ngOnDestroy(): void {
    this.#destroyEventListeners();
  }

  protected async startCamera(): Promise<void> {
    const startOptions = {
      deviceId: this.deviceId(),
      position: this.position(),
      enableZoom: this.enableZoom(),
      disableAudio: this.disableAudio(),
      enableHighResolution: this.enableHighResolution(),
      lockAndroidOrientation: this.lockAndroidOrientation(),
      toBack: true,
    };

    await this.#cameraViewService.start(startOptions);

    await Promise.all([
      this.#initializeZoomLimits(),
      this.#initializeFlashModes(),
      this.#initializeDevices(),
      this.#initializeLenses(),
      this.#updateRunningStatus(),
      this.#updateCurrentDeviceId(),
    ]);

    this.currentZoomFactor.set(this.initialZoomFactor());

    // Setup camera switching after devices are loaded
    this.#setupCameraSwitchButtons();
  }

  protected async stopCamera(): Promise<void> {
    try {
      await this.#cameraViewService.stop();
    } catch (error) {
      console.error('Failed to stop camera', error);
    }
  }

  protected async close(): Promise<void> {
    this.stopCamera().catch((error) =>
      console.error('Failed to stop camera', error),
    );
    await this.#modalController.dismiss();
  }

  protected async capturePhoto(): Promise<void> {
    this.isCapturingPhoto.set(true);
    try {
      const captureOptions = {
        quality: this.pictureQuality(),
        format: this.pictureFormat(),
        ...(this.useCustomSize() && {
          width: this.pictureWidth(),
          height: this.pictureHeight(),
        }),
      };

      const photo = await this.#cameraViewService.capture(this.quality(), captureOptions);
      this.#modalController.dismiss({
        photo,
        options: captureOptions,
        type: 'standard'
      });
    } catch (error) {
      console.error('Failed to capture photo', error);
      this.#modalController.dismiss();
    }

    this.stopCamera().catch((error) => {
      console.error('Failed to stop camera', error);
    });

    this.isCapturingPhoto.set(false);
  }

  protected async captureSample(): Promise<void> {
    this.isCapturingPhoto.set(true);
    try {
      const photo = await this.#cameraViewService.captureSample(this.pictureQuality());
      this.#modalController.dismiss({
        photo,
        type: 'sample'
      });
    } catch (error) {
      console.error('Failed to capture sample', error);
      this.#modalController.dismiss();
    }

    this.stopCamera().catch((error) => {
      console.error('Failed to stop camera', error);
    });

    this.isCapturingPhoto.set(false);
  }

  protected async flipCamera(): Promise<void> {
    await this.#cameraViewService.flipCamera();
    await this.#setZoom(1.0);
    await this.#initializeZoomLimits();
  }

  protected async nextFlashMode(): Promise<void> {
    const supportedModes = this.#supportedFlashModes();
    if (supportedModes.length <= 1) return;

    const currentMode = this.flashMode();
    const currentIndex = supportedModes.indexOf(currentMode);
    const nextIndex = (currentIndex + 1) % supportedModes.length;
    const nextFlashMode = supportedModes[nextIndex] as FlashMode;

    this.flashMode.set(nextFlashMode);
    await this.#cameraViewService.setFlashMode(nextFlashMode);
  }

  protected async zoomIn(): Promise<void> {
    if (this.canZoomIn()) {
      this.currentZoomFactor.update((curr) => curr + 0.1);
      await this.#setZoom(this.currentZoomFactor());
    }
  }

  protected async zoomOut(): Promise<void> {
    if (this.canZoomOut()) {
      this.currentZoomFactor.update((curr) => curr - 0.1);
      await this.#setZoom(this.currentZoomFactor());
    }
  }

  protected async switchToDevice(deviceId: string): Promise<void> {
    await this.#cameraViewService.flipCamera();
    try {
      await this.#cameraViewService.setDeviceId(deviceId);
      await this.#updateCurrentDeviceId();
      await this.#initializeZoomLimits();
      await this.#initializeFlashModes();

      // Update selected camera index to match the new device
      const cameras = this.availableCameras();
      const foundIndex = cameras.findIndex(camera => camera.deviceId === deviceId);
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

      // Test zoom capabilities
      const zoom = await this.#cameraViewService.getZoom();
      results += `\n✓ Zoom: ${zoom.min} - ${zoom.max} (current: ${zoom.current})`;

      // Test flash mode
      const flashMode = await this.#cameraViewService.getFlashMode();
      results += `\n✓ Flash mode: ${flashMode}`;

      // Test lens information
      const lenses = await this.#cameraViewService.getAvailableLenses();
      results += `\n✓ Available lenses: ${lenses.length}`;

      const currentLens = await this.#cameraViewService.getCurrentLens();
      results += `\n✓ Current lens: ${currentLens.label} (${currentLens.deviceType})`;
      results += `\n  - Base zoom: ${currentLens.baseZoomRatio}x`;
      results += `\n  - Focal length: ${currentLens.focalLength}mm`;

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

      // Get available lenses
      const lenses = await this.#cameraViewService.getAvailableLenses();
      results += `\n✓ Available lenses: ${lenses.length}`;

      lenses.forEach((lens, index) => {
        results += `\n  ${index + 1}. ${lens.label}`;
        results += `\n     Type: ${lens.deviceType}`;
        results += `\n     Base Zoom: ${lens.baseZoomRatio}x`;
        results += `\n     Zoom Range: ${lens.minZoom}x - ${lens.maxZoom}x`;
        results += `\n     Focal Length: ${lens.focalLength}mm`;
        results += `\n     Active: ${lens.isActive ? 'Yes' : 'No'}`;
      });

      // Get current lens
      const currentLens = await this.#cameraViewService.getCurrentLens();
      results += `\n✓ Current lens: ${currentLens.label} (${currentLens.deviceType})`;

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
        const results = this.testResults() + `\n✗ Failed to start recording: ${error}`;
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
        type: 'video'
      });
    } catch (error) {
      if (this.showTestResults()) {
        const results = this.testResults() + `\n✗ Failed to stop recording: ${error}`;
        this.testResults.set(results);
      }
      console.error('Failed to stop recording:', error);
    }
  }

  /**
 * Mappe un zoom utilisateur (0.5x - 10x) vers un zoom réel (zoomMin - zoomMax)
 */
  private mapUserZoomToCameraZoom(userZoom: number): number {
    const currentLens = this.currentLens();
    // if (currentLens?.deviceType === 'wideAngle') {
    //   userZoom = userZoom + 0.2;
    // }

    const clampedZoom = Math.max(this.minZoom(), Math.min(this.maxZoom(), userZoom));
    const t = (clampedZoom - this.minZoom()) / (this.maxZoom() - this.minZoom());

    return this.minZoomReel() + t * (this.maxZoomReel() - this.minZoomReel());
  }

  /**
 * Mappe un zoom réel (zoomMin - zoomMax) vers un zoom utilisateur (0.5x - 10x)
 */
  // private mapCameraZoomToUserZoom(cameraZoom: number): number {
  //   const clampedZoom = Math.max(this.minZoomReel(), Math.min(this.maxZoomReel(), cameraZoom));
  //   const t = (clampedZoom - this.minZoomReel()) / (this.maxZoomReel() - this.minZoomReel());

  //   return this.minZoom() + t * (this.maxZoom() - this.minZoom());
  // }

  async #setZoom(zoomFactor: number): Promise<void> {
    const previousLens = this.currentLens();
    this.currentZoomFactor.set(zoomFactor);
    console.log('availableLenses:', JSON.stringify(this.availableLenses(), null, 2));
    console.log('currentZoomFactor:', zoomFactor);
    console.log('mapUserZoomToCameraZoom:', this.mapUserZoomToCameraZoom(zoomFactor));
    // await this.#cameraViewService.setZoom(this.mapUserZoomToCameraZoom(zoomFactor), false);
    await this.#cameraViewService.setZoom(zoomFactor, false);
    await this.#updateCurrentDeviceId();
    await this.#updateAvailableLenses();

    // Check if lens changed and update test results
    const newLens = this.currentLens();
    if (previousLens && newLens && previousLens.id !== newLens.id && this.showTestResults()) {
      const results = this.testResults() + `\n✓ Lens switched: ${newLens.label} (${newLens.deviceType}, ${newLens.baseZoomRatio}x) at ${zoomFactor.toFixed(1)}x zoom`;
      this.testResults.set(results);
    }
  }


  async #initializeZoomLimits(): Promise<void> {
    try {
      const zoomRange = await this.#cameraViewService.getZoom();

      if (zoomRange) {
        this.minZoomReel.set(zoomRange.min);
        this.maxZoomReel.set(zoomRange.max);
      }
    } catch (error) {
      console.warn('Failed to get zoom range, using default values.', error);
    }
  }
  async #initializeLenses(): Promise<void> {
    try {
      const lenses = await this.#cameraViewService.getAvailableLenses();
      const currentLens = await this.#cameraViewService.getCurrentLens();
      this.availableLenses.set(lenses);
      this.currentLens.set(currentLens);
    } catch (error) {
      console.warn('Failed to get available lenses', error);
    }
  }

  async #updateAvailableLenses(): Promise<void> {
    try {
      const lenses = await this.#cameraViewService.getAvailableLenses();
      const currentLens = await this.#cameraViewService.getCurrentLens();
      this.availableLenses.set(lenses);
      this.currentLens.set(currentLens);
    } catch (error) {
      console.warn('Failed to update available lenses', error);
    }
  }

  async #initializeFlashModes(): Promise<void> {
    try {
      this.#supportedFlashModes.set(
        await this.#cameraViewService.getSupportedFlashModes(),
      );
    } catch (error) {
      console.warn('Failed to get supported flash modes', error);
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
    const camerasForPosition = devices.filter(device =>
      device.position === currentPosition
    );

    console.log('camerasForPosition:', JSON.stringify(camerasForPosition, null, 2));

    // Sort cameras by device type to create a logical progression
    const sortedCameras = camerasForPosition.sort((a, b) => {
      const typeOrder: { [key: string]: number } = { 'ultraWide': 0, 'wideAngle': 1, 'telephoto': 2, 'multi': 3 };
      const aOrder = typeOrder[a.deviceType || 'unknown'] ?? 4;
      const bOrder = typeOrder[b.deviceType || 'unknown'] ?? 4;
      return aOrder - bOrder;
    });

    this.availableCameras.set(sortedCameras);

    // Set initial camera selection to match current device if possible
    const currentDeviceId = this.currentDeviceId();
    let initialIndex = 0;
    if (currentDeviceId !== null && currentDeviceId !== undefined) {
      const foundIndex = sortedCameras.findIndex(camera => camera.deviceId === currentDeviceId);
      if (foundIndex >= 0) {
        initialIndex = foundIndex;
      }
    }
    this.selectedCameraIndex.set(initialIndex);

    console.log('Current device ID:', this.currentDeviceId());
    console.log('selectedCameraIndex:', this.selectedCameraIndex());
  }

  /**
   * Switch to a specific camera by index
   */
  protected switchToCameraByIndex(index: number): Promise<void> {
    const cameras = this.availableCameras();
    if (index >= 0 && index < cameras.length) {
      this.selectedCameraIndex.set(index);
      const camera = cameras[index];

      // Update test results
      // const results = this.testResults() + `\n✓ Switched to camera: ${camera.label} (${camera.deviceType})`;
      // this.testResults.set(results);

      return this.switchToDevice(camera.deviceId);
    }
    return Promise.resolve();
  }

  /**
   * Get the label for a camera switch button
   */
  protected getCameraSwitchLabel(index: number): string {
    const cameras = this.availableCameras();
    if (index >= cameras.length) return '';

    const camera = cameras[index];

    // Map device types to user-friendly zoom descriptions
    const typeLabels: { [key: string]: string } = {
      'ultraWide': '0.5x',
      'wideAngle': '1x',
      'telephoto': index === 2 ? '2x' : '3x',
      'multi': `${index + 1}x`
    };

    return typeLabels[camera.deviceType || 'unknown'] || `${index + 1}x`;
  }

  async #updateRunningStatus(): Promise<void> {
    try {
      const running = await this.#cameraViewService.isRunning();
      this.isRunning.set(running);
    } catch (error) {
      console.warn('Failed to get running status', error);
    }
  }

  async #updateCurrentDeviceId(): Promise<void> {
    try {
      const deviceId = await this.#cameraViewService.getDeviceId();
      this.currentDeviceId.set(deviceId);
    } catch (error) {
      console.warn('Failed to get current device ID', error);
    }
  }

  #initializeEventListeners(): void {
    this.#elementRef.nativeElement.addEventListener(
      'touchstart',
      this.#handleTouchStart.bind(this),
    );
    this.#elementRef.nativeElement.addEventListener(
      'touchmove',
      this.#handleTouchMove.bind(this),
    );
  }

  #destroyEventListeners(): void {
    this.#elementRef.nativeElement.removeEventListener(
      'touchstart',
      this.#handleTouchStart.bind(this),
    );
    this.#elementRef.nativeElement.removeEventListener(
      'touchmove',
      this.#handleTouchMove.bind(this),
    );
  }

  #handleTouchStart(event: TouchEvent): void {
    if (event.touches.length < 2) return;

    this.#touchStartDistance = getDistance(event.touches[0], event.touches[1]);
    this.#initialZoomFactorOnPinch = this.currentZoomFactor();
  }

  #handleTouchMove(event: TouchEvent): void {
    if (event.touches.length < 2 || this.#touchStartDistance <= 0) return;

    const currentDistance = getDistance(event.touches[0], event.touches[1]);

    // Calculate new zoom factor
    const scale = currentDistance / this.#touchStartDistance;
    const newZoomFactor = Math.max(
      this.minZoom(),
      Math.min(this.maxZoom(), this.#initialZoomFactorOnPinch * scale),
    );

    this.#setZoom(newZoomFactor);
    event.preventDefault(); // Prevent scrolling
  }
}
