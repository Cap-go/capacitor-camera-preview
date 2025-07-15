import { Component, inject, model, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonButton,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardTitle,
  IonCheckbox,
  IonContent,
  IonHeader,
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
  ModalController,
} from '@ionic/angular/standalone';
import {
  CameraDevice,
  CameraPosition,
  FlashMode,
  PictureFormat,
} from '@capgo/camera-preview';
import { CameraModalComponent } from '../../components/camera-modal/camera-modal.component';
import { CapacitorCameraViewService } from '../../core/capacitor-camera-preview.service';
import { GalleryService } from '../../services/gallery.service';

@Component({
  selector: 'app-camera-view',
  templateUrl: 'camera-view.page.html',
  imports: [
    FormsModule,
    IonButton,
    IonCard,
    IonCardContent,
    IonCardHeader,
    IonCardTitle,
    IonCheckbox,
    IonContent,
    IonHeader,
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
  ],
})
export class CameraSettingsPage implements OnInit {
  readonly #cameraViewService = inject(CapacitorCameraViewService);
  readonly #galleryService = inject(GalleryService);
  readonly #modalController = inject(ModalController);

  protected readonly cameraDevices = signal<CameraDevice[]>([]);
  protected readonly testResults = signal<string>('');

  // Basic camera settings
  protected deviceId = model<string | null>(null);
  protected position = model<CameraPosition>('rear');
  protected quality = model<number>(85);
  protected useTripleCameraIfAvailable = model<boolean>(false);
  protected initialZoomFactor = model<number>(1.0);

  // Picture settings
  protected pictureFormat = model<PictureFormat>('jpeg');
  protected pictureQuality = model<number>(85);
  protected useCustomSize = model<boolean>(false);
  protected pictureWidth = model<number>(1920);
  protected pictureHeight = model<number>(1080);

  // Camera behavior settings
  protected opacity = model<number>(100);
  protected enableZoom = model<boolean>(false);
  protected disableAudio = model<boolean>(false);
  protected enableHighResolution = model<boolean>(false);
  protected lockAndroidOrientation = model<boolean>(false);

  ngOnInit() {
    setTimeout(() => {
      this.#cameraViewService.getAvailableDevices().then((devices) => {
        this.cameraDevices.set(devices);
      });
    }, 100);
  }

  protected async startCamera(): Promise<void> {
    const cameraModal = await this.#modalController.create({
      component: CameraModalComponent,
      animated: false,
      componentProps: {
        deviceId: this.deviceId(),
        position: this.position(),
        quality: this.quality(),
        useTripleCameraIfAvailable: this.useTripleCameraIfAvailable(),
        initialZoomFactor: this.initialZoomFactor(),
        pictureFormat: this.pictureFormat(),
        pictureQuality: this.pictureQuality(),
        useCustomSize: this.useCustomSize(),
        pictureWidth: this.pictureWidth(),
        pictureHeight: this.pictureHeight(),
        opacity: this.opacity(),
        enableZoom: this.enableZoom(),
        disableAudio: this.disableAudio(),
        enableHighResolution: this.enableHighResolution(),
        lockAndroidOrientation: this.lockAndroidOrientation(),
      },
    });

    await cameraModal.present();

    const { data } = await cameraModal.onDidDismiss<{
      photo: string;
      options?: any;
      type?: string;
    }>();

    if (data?.photo) {
      this.#galleryService.addPhoto(data?.photo);
      let results = this.testResults() + `\n✓ Photo captured successfully`;
      if (data.type) {
        results += ` (${data.type})`;
      }
      if (data.options) {
        results += `\n  Options: ${JSON.stringify(data.options)}`;
      }
      this.testResults.set(results);
    }
  }

  // Testing Methods
  protected async testHorizontalFov(): Promise<void> {
    try {
      const fov = await this.#cameraViewService.getHorizontalFov();
      const results = this.testResults() + `\n✓ Horizontal FOV: ${JSON.stringify(fov)}`;
      this.testResults.set(results);
    } catch (error) {
      const results = this.testResults() + `\n✗ FOV test failed: ${error}`;
      this.testResults.set(results);
    }
  }

  // protected async testSupportedPictureSizes(): Promise<void> {
  //   try {
  //     const sizes = await this.#cameraViewService.getSupportedPictureSizes();
  //     const results = this.testResults() + `\n✓ Picture sizes: ${JSON.stringify(sizes, null, 2)}`;
  //     this.testResults.set(results);
  //   } catch (error) {
  //     const results = this.testResults() + `\n✗ Picture sizes test failed: ${error}`;
  //     this.testResults.set(results);
  //   }
  // }

  // protected async testFlashModes(): Promise<void> {
  //   try {
  //     const modes = await this.#cameraViewService.getSupportedFlashModes();
  //     const results = this.testResults() + `\n✓ Flash modes: ${modes.join(', ')}`;
  //     this.testResults.set(results);
  //   } catch (error) {
  //     const results = this.testResults() + `\n✗ Flash modes test failed: ${error}`;
  //     this.testResults.set(results);
  //   }
  // }

  // protected async testZoomCapabilities(): Promise<void> {
  //   try {
  //     const zoom = await this.#cameraViewService.getZoom();
  //     const results = this.testResults() + `\n✓ Zoom: min=${zoom.min}, max=${zoom.max}, current=${zoom.current}`;
  //     this.testResults.set(results);
  //   } catch (error) {
  //     const results = this.testResults() + `\n✗ Zoom test failed: ${error}`;
  //     this.testResults.set(results);
  //   }
  // }

  // protected async testErrorScenarios(): Promise<void> {
  //   let results = this.testResults() + `\n=== Error Scenario Testing ===`;

  //   // Test invalid device ID
  //   try {
  //     await this.#cameraViewService.setDeviceId('invalid-device-id');
  //     results += `\n✗ Invalid device ID should have failed`;
  //   } catch (error) {
  //     results += `\n✓ Invalid device ID correctly failed`;
  //   }

  //   // Test invalid zoom level
  //   try {
  //     await this.#cameraViewService.setZoom(999, false);
  //     results += `\n✗ Invalid zoom should have failed`;
  //   } catch (error) {
  //     results += `\n✓ Invalid zoom correctly failed`;
  //   }

  //   this.testResults.set(results);
  // }

  // protected async testAllFeatures(): Promise<void> {
  //   let results = '=== Comprehensive Camera Test ===\n';

  //   try {
  //     // Test running status
  //     const running = await this.#cameraViewService.isRunning();
  //     results += `\n✓ Camera running: ${running}`;

  //     // Test available devices
  //     const devices = await this.#cameraViewService.getAvailableDevices();
  //     results += `\n✓ Available devices: ${devices.length}`;

  //     // Test supported flash modes
  //     const flashModes = await this.#cameraViewService.getSupportedFlashModes();
  //     results += `\n✓ Flash modes: ${flashModes.join(', ')}`;

  //     // Test zoom capabilities
  //     const zoom = await this.#cameraViewService.getZoom();
  //     results += `\n✓ Zoom range: ${zoom.min} - ${zoom.max}`;

  //     // Test horizontal FOV
  //     const fov = await this.#cameraViewService.getHorizontalFov();
  //     results += `\n✓ Horizontal FOV: ${JSON.stringify(fov)}`;

  //     // Test picture sizes
  //     // const sizes = await this.#cameraViewService.getSupportedPictureSizes();
  //     // results += `\n✓ Picture sizes available: ${sizes.supportedPictureSizes?.length || 0} cameras`;

  //     this.testResults.set(results);
  //   } catch (error) {
  //     results += `\n✗ Test failed: ${error}`;
  //     this.testResults.set(results);
  //   }
  // }

  // // Quick test methods
  // protected async quickTestHighQuality(): Promise<void> {
  //   this.pictureFormat.set('png');
  //   this.pictureQuality.set(100);
  //   this.useCustomSize.set(true);
  //   this.pictureWidth.set(4096);
  //   this.pictureHeight.set(3072);
  //   await this.startCamera();
  // }

  // protected async quickTestLowQuality(): Promise<void> {
  //   this.pictureFormat.set('jpeg');
  //   this.pictureQuality.set(20);
  //   this.useCustomSize.set(true);
  //   this.pictureWidth.set(640);
  //   this.pictureHeight.set(480);
  //   await this.startCamera();
  // }

  // protected async quickTestVideo(): Promise<void> {
  //   // Set optimal settings for video
  //   this.disableAudio.set(false);
  //   this.enableZoom.set(true);
  //   this.opacity.set(100);
  //   await this.startCamera();
  // }

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
