import {
  Component,
  inject,
  model,
  OnInit,
  signal,
  computed,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonButton,
  IonItemDivider,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardTitle,
  IonCheckbox,
  IonContent,
  IonHeader,
  IonIcon,
  IonSelect,
  IonItem,
  IonInput,
  IonLabel,
  IonList,
  IonRange,
  IonSelectOption,
  IonTitle,
  IonToolbar,
  ModalController,
  IonGrid,
  IonRow,
  IonCol,
} from '@ionic/angular/standalone';
import {
  CameraDevice,
  CameraPosition,
  CameraPermissionStatus,
  ExifData,
  FlashMode,
  PictureFormat,
} from '@capgo/camera-preview';
import { CameraModalComponent } from '../../components/camera-modal/camera-modal.component';
import { CapacitorCameraViewService } from '../../core/capacitor-camera-preview.service';
import { GalleryService } from '../../services/gallery.service';

@Component({
  selector: 'app-camera-view',
  templateUrl: 'camera-view.page.html',
  standalone: true,
  imports: [
    FormsModule,
    IonButton,
    IonItemDivider,
    IonCard,
    IonCardContent,
    IonCardHeader,
    IonCardTitle,
    IonCheckbox,
    IonContent,
    IonHeader,
    IonInput,
    IonIcon,
    IonInput,
    IonItem,
    IonLabel,
    IonList,
    IonRange,
    IonSelect,
    IonSelectOption,
    IonTitle,
    IonToolbar,
    IonGrid,
    IonRow,
    IonCol,
  ],
})
export class CameraViewPage implements OnInit {
  protected unsetXY() {
    this.previewX.set(-1);
    this.previewY.set(-1);
  }
  readonly #cameraViewService = inject(CapacitorCameraViewService);
  readonly #galleryService = inject(GalleryService);
  readonly #modalController = inject(ModalController);

  protected readonly cameraDevices = signal<CameraDevice[]>([]);
  protected readonly rearCameras = computed(() =>
    this.cameraDevices().filter((d) => d.position === 'rear'),
  );
  protected readonly frontCameras = computed(() =>
    this.cameraDevices().filter((d) => d.position === 'front'),
  );
  protected readonly testResults = signal<string>('');

  // Basic camera settings
  protected deviceId = model<string | null>(null);
  protected position = model<CameraPosition>('rear');
  protected quality = model<number>(85);
  protected useTripleCameraIfAvailable = model<boolean>(false);
  protected initialZoomFactor = model<number>(1.0);

  // Preview settings
  protected previewX = model<number>(0);
  protected previewY = model<number>(0);
  protected previewWidth = model<number>(0);
  protected previewHeight = model<number>(0);
  protected aspectRatio = model<'4:3' | '16:9' | 'custom'>('custom');

  // Picture settings
  protected pictureFormat = model<PictureFormat>('jpeg');
  protected pictureQuality = model<number>(85);
  protected useCustomSize = model<boolean>(false);
  protected pictureWidth = model<number>(1920);
  protected pictureHeight = model<number>(1080);

  // Camera behavior settings
  protected opacity = model<number>(100);
  protected disableAudio = model<boolean>(true);
  protected lockAndroidOrientation = model<boolean>(false);
  protected saveToGallery = model<boolean>(false);
  protected withExifLocation = model<boolean>(false);
  protected gridMode = model<'none' | '3x3' | '4x4'>('none');

  protected showBoundary = model<boolean>(true);

  protected toBack = model<boolean>(false);

  ngOnInit() {
    setTimeout(() => {
      this.#cameraViewService.getAvailableDevices().then((devices) => {
        this.cameraDevices.set(devices);
      });
    }, 100);
  }

  protected setPreset(preset: string) {
    let x = 0,
      y = 0,
      w = 0,
      h = 0;
    const screenWidth = window.innerWidth;
    const screenHeight = window.innerHeight;
    switch (preset) {
      case 'full':
        x = 0;
        y = 0;
        w = 0;
        h = 0;
        break;
      case 'top-left':
        x = 0;
        y = 0;
        w = Math.floor(screenWidth / 2);
        h = Math.floor(screenHeight / 2);
        break;
      case 'bottom-right':
        x = Math.floor(screenWidth / 2);
        y = Math.floor(screenHeight / 2);
        w = Math.floor(screenWidth / 2);
        h = Math.floor(screenHeight / 2);
        break;
      case 'small-center':
        x = Math.floor((screenWidth - 200) / 2);
        y = Math.floor((screenHeight - 200) / 2);
        w = 200;
        h = 200;
        break;
    }
  this.previewX.set(x);
  this.previewY.set(y);
    this.previewWidth.set(w);
    this.previewHeight.set(h);
    this.aspectRatio.set('custom');
  }

  protected setCapturePreset(preset: string) {
    let width: number, height: number;

    switch (preset) {
      case 'vga':
        width = 640;
        height = 480;
        break;
      case 'hd':
        width = 1280;
        height = 720;
        break;
      case 'fullhd':
        width = 1920;
        height = 1080;
        break;
      case '4k':
        width = 3840;
        height = 2160;
        break;
      case 'square':
        width = 1080;
        height = 1080;
        break;
      case 'portrait':
        width = 1080;
        height = 1920;
        break;
      case 'small':
        width = 480;
        height = 320;
        break;
      case 'large':
        width = 4096;
        height = 3072;
        break;
      case 'disable':
        this.useCustomSize.set(false);
        return;
      default:
        return;
    }

    this.pictureWidth.set(width);
    this.pictureHeight.set(height);
    this.useCustomSize.set(true);

    // Add to test results to show what was selected
    const results =
      this.testResults() +
      `\n📐 Capture size set to: ${width}x${height} (${preset.toUpperCase()})`;
    this.testResults.set(results);
  }

  protected setMaxCapturePreset(preset: string) {
    let maxWidth: number | undefined, maxHeight: number | undefined;

    switch (preset) {
      case 'max-width-800':
        maxWidth = 800;
        maxHeight = undefined;
        break;
      case 'max-height-600':
        maxWidth = undefined;
        maxHeight = 600;
        break;
      case 'max-800x600':
        maxWidth = 800;
        maxHeight = 600;
        break;
      case 'max-1200x800':
        maxWidth = 1200;
        maxHeight = 800;
        break;
      case 'max-square-500':
        maxWidth = 500;
        maxHeight = 500;
        break;
      case 'disable':
        this.useCustomSize.set(false);
        return;
      default:
        return;
    }

    this.pictureWidth.set(maxWidth || 0);
    this.pictureHeight.set(maxHeight || 0);
    this.useCustomSize.set(true);

    // Add to test results to show what was selected
    const maxWidthText = maxWidth ? maxWidth.toString() : 'unlimited';
    const maxHeightText = maxHeight ? maxHeight.toString() : 'unlimited';
    const results =
      this.testResults() +
      `\n📏 Max capture size set to: ${maxWidthText}x${maxHeightText} (${preset.toUpperCase()})`;
    this.testResults.set(results);
  }

  protected async startCamera(): Promise<void> {
    // Validate that aspect ratio and size (width/height) are not both set
    const hasAspectRatio = this.aspectRatio() !== 'custom';
    const hasSize = this.previewWidth() > 0 || this.previewHeight() > 0;

    if (hasAspectRatio && hasSize) {
      const results = this.testResults() +
        `\n✗ Error: Cannot set both aspect ratio and size (width/height). Use setPreviewSize after start.`;
      this.testResults.set(results);
      return;
    }

    const disableAudio = this.disableAudio();
    const isDenied = (s?: CameraPermissionStatus['camera']) => s === 'denied';
    const shouldRequest = (s?: CameraPermissionStatus['camera']) =>
      s === 'prompt' || s === 'prompt-with-rationale';

    let permissions = await this.#cameraViewService.checkPermissions({ disableAudio });
    const micNeeded = !disableAudio;

    // First, request if either permission is in a prompt state
    if (
      shouldRequest(permissions.camera) ||
      (micNeeded && shouldRequest(permissions.microphone))
    ) {
      permissions = await this.#cameraViewService.requestPermissions({
        disableAudio,
        showSettingsAlert: false,
      });
    }

    // If still denied, guide to Settings (and log)
    if (
      isDenied(permissions.camera) ||
      (micNeeded && isDenied(permissions.microphone))
    ) {
      const message =
        micNeeded && isDenied(permissions.microphone)
          ? 'Camera or microphone permission denied. Enable access in Settings and try again.'
          : 'Camera permission denied. Enable access in Settings and try again.';
      let results =
        this.testResults() +
        `\n✗ ${message} (camera: ${permissions.camera}${
          permissions.microphone ? `, microphone: ${permissions.microphone}` : ''
        })`;
      try {
        const followUp = await this.#cameraViewService.requestPermissions({
          disableAudio,
          showSettingsAlert: true,
        });
        results += `\n  (after requestPermissions → camera: ${followUp.camera}${
          followUp.microphone ? `, microphone: ${followUp.microphone}` : ''
        })`;
      } catch (err) {
        console.warn('Unable to open settings prompt', err);
      }
      this.testResults.set(results);
      return;
    }
    const cameraModal = await this.#modalController.create({
      component: CameraModalComponent,
      animated: false,
      componentProps: {
        deviceId: this.deviceId(),
        position: this.position(),
        quality: this.quality(),
        x: this.previewX() == null ? undefined : this.previewX(),
        y: this.previewY() == null ? undefined : this.previewY(),
        width: this.previewWidth(),
        height: this.previewHeight(),
        aspectRatio:
          this.aspectRatio() === 'custom' ? undefined : this.aspectRatio(),
        useTripleCameraIfAvailable: this.useTripleCameraIfAvailable(),
        initialZoomFactor: this.initialZoomFactor(),
        pictureFormat: this.pictureFormat(),
        pictureQuality: this.pictureQuality(),
        useCustomSize: this.useCustomSize(),
        pictureWidth: this.pictureWidth(),
        pictureHeight: this.pictureHeight(),
        opacity: this.opacity(),
        disableAudio: this.disableAudio(),
        lockAndroidOrientation: this.lockAndroidOrientation(),
        saveToGallery: this.saveToGallery(),
        withExifLocation: this.withExifLocation(),
        gridMode: this.gridMode(),
        showBoundary: this.showBoundary(),
      },
    });

    await cameraModal.present();

    const { data } = await cameraModal.onDidDismiss<{
      photo: string;
      exif: ExifData;
      options?: any;
      type?: string;
      error?: string;
      permissions?: CameraPermissionStatus;
    }>();

    console.log('Camera modal dismissed', data);
    if (data?.type === 'permissionDenied') {
      const message = data.error || 'Camera permission denied. Enable access in Settings and try again.';
      const details = data.permissions
        ? ` (camera: ${data.permissions.camera}${data.permissions.microphone ? `, microphone: ${data.permissions.microphone}` : ''})`
        : '';
      let results = this.testResults() + `\n✗ ${message}${details}`;
      try {
        const followUp = await this.#cameraViewService.requestPermissions({
          disableAudio: this.disableAudio(),
          showSettingsAlert: true,
        });
        const followUpDetails = ` (after requestPermissions → camera: ${followUp.camera}${followUp.microphone ? `, microphone: ${followUp.microphone}` : ''})`;
        results += `\n  ${followUpDetails}`;
      } catch (err) {
        console.warn('Unable to open settings prompt', err);
      }
      this.testResults.set(results);
      return;
    }

    if (data?.error) {
      // Show error in test results
      const results =
        this.testResults() + `\n✗ Camera start failed: ${data.error}`;
      this.testResults.set(results);
      return;
    }

    if (data?.photo) {
      this.#galleryService.addPhoto(data?.photo, data?.exif as any);
      let results = this.testResults() + `\n✓ Photo captured successfully`;
      if (data.type) {
        results += ` (${data.type})`;
      }
      if (data.options) {
        results += `\n  Options: ${JSON.stringify(data.options)}`;
      }
      if (data.exif) {
        results += `\n  EXIF: ${JSON.stringify(data.exif, null, 2)}`;
      }
      this.testResults.set(results);
    }
  }

  // Testing Methods
  protected async testHorizontalFov(): Promise<void> {
    try {
      const fov = await this.#cameraViewService.getHorizontalFov();
      const results =
        this.testResults() + `\n✓ Horizontal FOV: ${JSON.stringify(fov)}`;
      this.testResults.set(results);
    } catch (error) {
      const results = this.testResults() + `\n✗ FOV test failed: ${error}`;
      this.testResults.set(results);
    }
  }

  protected async testSupportedPictureSizes(): Promise<void> {
    try {
      const sizes = await this.#cameraViewService.getSupportedPictureSizes();
      const results =
        this.testResults() +
        `\n✓ Picture sizes: ${JSON.stringify(sizes, null, 2)}`;
      this.testResults.set(results);
    } catch (error) {
      const results =
        this.testResults() + `\n✗ Picture sizes test failed: ${error}`;
      this.testResults.set(results);
    }
  }

  protected async testFlashModes(): Promise<void> {
    try {
      const modes = await this.#cameraViewService.getSupportedFlashModes();
      const results =
        this.testResults() + `\n✓ Flash modes: ${modes.join(', ')}`;
      this.testResults.set(results);
    } catch (error) {
      const results =
        this.testResults() + `\n✗ Flash modes test failed: ${error}`;
      this.testResults.set(results);
    }
  }

  protected async testZoomCapabilities(): Promise<void> {
    try {
      const zoom = await this.#cameraViewService.getZoom();
      const results =
        this.testResults() +
        `\n✓ Zoom: min=${zoom.min}, max=${zoom.max}, current=${zoom.current}`;
      this.testResults.set(results);
    } catch (error) {
      const results = this.testResults() + `\n✗ Zoom test failed: ${error}`;
      this.testResults.set(results);
    }
  }

  protected async testErrorScenarios(): Promise<void> {
    let results = this.testResults() + `\n=== Error Scenario Testing ===`;

    // Test invalid device ID
    try {
      await this.#cameraViewService.setDeviceId('invalid-device-id');
      results += `\n✗ Invalid device ID should have failed`;
    } catch (error) {
      results += `\n✓ Invalid device ID correctly failed`;
    }

    // Test invalid zoom level
    try {
      await this.#cameraViewService.setZoom(999, false);
      results += `\n✗ Invalid zoom should have failed`;
    } catch (error) {
      results += `\n✓ Invalid zoom correctly failed`;
    }

    this.testResults.set(results);
  }

  protected async testAspectRatioFeature(): Promise<void> {
    let results = '=== Aspect Ratio Capture Test ===\n';
    results +=
      '\nThis test verifies aspectRatio parameter in capture options\n';

    try {
      // Test supported picture sizes first
      const sizes = await this.#cameraViewService.getSupportedPictureSizes();
      results += `\n✓ Picture sizes available for testing`;

      // Test different aspect ratios
      const ratios = ['4:3', '16:9'] as const;
      results += `\n\n📐 Aspect ratios to test: ${ratios.join(', ')}`;
      results += `\n\nTo test:`;
      results += `\n1. Click each aspect ratio button above`;
      results += `\n2. Take a photo`;
      results += `\n3. Check if the captured image has the correct aspect ratio`;
      results += `\n\nNote: When aspectRatio is set without width/height,`;
      results += `\nthe plugin captures the largest possible image with that ratio.`;

      this.testResults.set(results);
    } catch (error) {
      results += `\n✗ Test failed: ${error}`;
      this.testResults.set(results);
    }
  }

  protected async testAllFeatures(): Promise<void> {
    let results = '=== Comprehensive Camera Test ===\n';

    try {
      // Test running status
      const running = await this.#cameraViewService.isRunning();
      results += `\n✓ Camera running: ${running}`;

      // Test available devices
      const devices = await this.#cameraViewService.getAvailableDevices();
      results += `\n✓ Available devices: ${devices.length}`;
      devices.forEach((device, index) => {
        results += `\n  ${index + 1}. ${device.label} (${device.position})`;
        results += `\n     Lenses: ${device.lenses.length}`;
        results += `\n     Overall zoom range: ${device.minZoom}x - ${device.maxZoom}x`;
        device.lenses.forEach((lens) => {
          results += `\n       - ${lens.deviceType}: ${lens.baseZoomRatio}x base (${lens.minZoom}x-${lens.maxZoom}x)`;
        });
      });

      // Test supported flash modes
      const flashModes = await this.#cameraViewService.getSupportedFlashModes();
      results += `\n✓ Flash modes: ${flashModes.join(', ')}`;

      // Test zoom capabilities and lens info
      const zoomData = await this.#cameraViewService.getZoom();
      results += `\n✓ Zoom range: ${zoomData.min} - ${zoomData.max} (current: ${zoomData.current})`;
      results += `\n✓ Current lens: ${zoomData.lens.deviceType} (${zoomData.lens.baseZoomRatio}x base, ${zoomData.lens.digitalZoom}x digital)`;
      results += `\n  - Focal length: ${zoomData.lens.focalLength}mm`;

      // Test horizontal FOV
      const fov = await this.#cameraViewService.getHorizontalFov();
      results += `\n✓ Horizontal FOV: ${JSON.stringify(fov)}`;

      // Test picture sizes
      const sizes = await this.#cameraViewService.getSupportedPictureSizes();
      results += `\n✓ Picture sizes available: ${sizes.supportedPictureSizes?.length || 0} cameras`;

      this.testResults.set(results);
    } catch (error) {
      results += `\n✗ Test failed: ${error}`;
      this.testResults.set(results);
    }
  }

  // Quick test methods
  protected async quickTestHighQuality(): Promise<void> {
    this.pictureFormat.set('png');
    this.pictureQuality.set(100);
    this.useCustomSize.set(true);
    this.pictureWidth.set(4096);
    this.pictureHeight.set(3072);
    await this.startCamera();
  }

  protected async quickTestLowQuality(): Promise<void> {
    this.pictureFormat.set('jpeg');
    this.pictureQuality.set(20);
    this.useCustomSize.set(true);
    this.pictureWidth.set(640);
    this.pictureHeight.set(480);
    await this.startCamera();
  }

  protected async quickTestVideo(): Promise<void> {
    // Set optimal settings for video
    this.disableAudio.set(false);
    this.opacity.set(100);
    await this.startCamera();
  }

  protected async quickTestCaptureSize(preset: string): Promise<void> {
    this.setCapturePreset(preset);
    this.pictureFormat.set('jpeg');
    this.pictureQuality.set(85);
    await this.startCamera();
  }

  protected async quickTestHDCapture(): Promise<void> {
    await this.quickTestCaptureSize('hd');
  }

  protected async quickTest4KCapture(): Promise<void> {
    await this.quickTestCaptureSize('4k');
  }

  protected async quickTestSquareCapture(): Promise<void> {
    await this.quickTestCaptureSize('square');
  }

  protected async quickTestAspectRatioCapture(
    ratio: '4:3' | '16:9',
  ): Promise<void> {
    // Disable custom size to test aspectRatio
    this.useCustomSize.set(false);
    this.aspectRatio.set(ratio);
    this.pictureFormat.set('jpeg');
    this.pictureQuality.set(85);

    // Add to test results
    const results =
      this.testResults() + `\n📐 Testing aspect ratio capture: ${ratio}`;
    this.testResults.set(results);

    await this.startCamera();
  }

  // Legacy methods for compatibility
  async isCameraRunning() {
    return this.#cameraViewService.isRunning();
  }

  async getSupportedFlashModes() {
    console.log(await this.#cameraViewService.getSupportedFlashModes());
  }

  async setFlashMode(flashMode: FlashMode) {
    return this.#cameraViewService.setFlashMode(flashMode);
  }

  async getZoom() {
    console.log(await this.#cameraViewService.getZoom());
  }
}
