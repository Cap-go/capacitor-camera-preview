import { Component, OnInit, signal, computed, OnDestroy, ViewChild, ElementRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
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
  IonItem,
  IonLabel,
  IonList,
  IonTitle,
  IonToolbar,
  IonToggle,
  IonText,
  IonItemDivider,
  AlertController,
} from '@ionic/angular/standalone';
import { FormsModule } from '@angular/forms';
import { addIcons } from 'ionicons';
import { play, stop } from 'ionicons/icons';
import {
  FaceDetectionEvent,
  DetectedFace,
  FaceDetectionCapabilities,
} from '@capgo/camera-preview';
import { CapacitorCameraViewService } from '../../core/capacitor-camera-preview.service';

@Component({
  selector: 'app-face-detection',
  templateUrl: './face-detection.page.html',
  styleUrls: ['./face-detection.page.scss'],
  standalone: true,
  imports: [
    CommonModule,
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
    IonItem,
    IonLabel,
    IonList,
    IonTitle,
    IonToolbar,
    IonToggle,
    IonText,
    IonItemDivider,
  ],
})
export class FaceDetectionPage implements OnInit, OnDestroy {
  @ViewChild('canvas', { static: false }) canvasRef!: ElementRef;

  private cameraService = inject(CapacitorCameraViewService);
  private alertController = inject(AlertController);

  // State signals
  isDetecting = signal(false);
  detectedFaces = signal<DetectedFace[]>([]);
  faceCount = signal(0);
  frameWidth = signal(0);
  frameHeight = signal(0);
  timestamp = signal(0);
  enableLandmarks = signal(true);
  enableClassification = signal(true);
  performanceMode = signal<'fast' | 'accurate'>('fast');
  detectionInterval = signal(1);
  capabilities = signal<FaceDetectionCapabilities>({
    supported: false,
    landmarks: false,
    contours: false,
    classification: false,
    tracking: false,
  });

  private faceDetectionListener: any;
  private canvas: HTMLCanvasElement | null = null;
  private animationId: number | null = null;

  constructor() {
    addIcons({ play, stop });
  }

  ngOnInit() {
    this.loadCapabilities();
  }

  ngOnDestroy() {
    this.stopDetection();
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }
  }

  async loadCapabilities() {
    try {
      const caps = await this.cameraService.getFaceDetectionCapabilities();
      this.capabilities.set(caps);
    } catch (error) {
      console.error('Error loading capabilities:', error);
      await this.showAlert('Error', 'Failed to load face detection capabilities');
    }
  }

  async startDetection() {
    try {
      // First start the camera if not already running
      const isRunning = await this.cameraService.isRunning();
      if (!isRunning) {
        await this.cameraService.start({
          position: 'front',
        });
      }

      // Enable face detection with options
      await this.cameraService.enableFaceDetection({
        enableLandmarks: this.enableLandmarks(),
        enableClassification: this.enableClassification(),
        performanceMode: this.performanceMode(),
        detectionInterval: this.detectionInterval(),
        enableTracking: true,
      });

      // Subscribe to face detection events
      this.faceDetectionListener = await this.cameraService.onFacesDetected(
        (event: FaceDetectionEvent) => {
          this.detectedFaces.set(event.faces);
          this.faceCount.set(event.faces.length);
          this.frameWidth.set(event.frameWidth);
          this.frameHeight.set(event.frameHeight);
          this.timestamp.set(event.timestamp);
          this.drawFaces(event);
        }
      );

      this.isDetecting.set(true);
      this.drawOverlay();
    } catch (error) {
      console.error('Error starting face detection:', error);
      await this.showAlert('Error', 'Failed to start face detection');
    }
  }

  async stopDetection() {
    try {
      if (this.faceDetectionListener) {
        await this.faceDetectionListener.remove();
        this.faceDetectionListener = null;
      }

      await this.cameraService.disableFaceDetection();
      this.isDetecting.set(false);
      this.detectedFaces.set([]);
      this.faceCount.set(0);
    } catch (error) {
      console.error('Error stopping face detection:', error);
    }
  }

  private drawOverlay() {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }

    this.canvas = this.canvasRef?.nativeElement;
    if (!this.canvas) return;

    const ctx = this.canvas.getContext('2d');
    if (!ctx) return;

    // Set canvas size to match window
    this.canvas.width = window.innerWidth;
    this.canvas.height = window.innerHeight;

    this.animationId = requestAnimationFrame(() => this.drawOverlay());
  }

  private drawFaces(event: FaceDetectionEvent) {
    if (!this.canvas) return;

    const ctx = this.canvas.getContext('2d');
    if (!ctx) return;

    // Clear canvas
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    const scaleX = this.canvas.width / event.frameWidth;
    const scaleY = this.canvas.height / event.frameHeight;

    for (const face of event.faces) {
      // Draw face bounding box
      const x = face.bounds.x * this.canvas.width;
      const y = face.bounds.y * this.canvas.height;
      const width = face.bounds.width * this.canvas.width;
      const height = face.bounds.height * this.canvas.height;

      // Face rectangle
      ctx.strokeStyle = '#00ff00';
      ctx.lineWidth = 3;
      ctx.strokeRect(x, y, width, height);

      // Face ID
      ctx.fillStyle = '#00ff00';
      ctx.font = 'bold 16px Arial';
      ctx.fillText(`ID: ${face.trackingId}`, x, y - 10);

      // Draw landmarks if available
      if (face.landmarks) {
        ctx.fillStyle = '#ff0000';

        if (face.landmarks.leftEye) {
          this.drawPoint(ctx, face.landmarks.leftEye, this.canvas.width, this.canvas.height, 'Left Eye');
        }
        if (face.landmarks.rightEye) {
          this.drawPoint(ctx, face.landmarks.rightEye, this.canvas.width, this.canvas.height, 'Right Eye');
        }
        if (face.landmarks.nose) {
          this.drawPoint(ctx, face.landmarks.nose, this.canvas.width, this.canvas.height, 'Nose');
        }
        if (face.landmarks.mouth) {
          this.drawPoint(ctx, face.landmarks.mouth, this.canvas.width, this.canvas.height, 'Mouth');
        }
      }

      // Draw face info
      let infoY = y + height + 20;
      ctx.fillStyle = '#ffffff';
      ctx.font = '14px Arial';

      if (face.angles) {
        ctx.fillText(`Yaw: ${face.angles.yaw.toFixed(1)}°`, x, infoY);
        infoY += 20;
        ctx.fillText(`Pitch: ${face.angles.pitch.toFixed(1)}°`, x, infoY);
        infoY += 20;
        ctx.fillText(`Roll: ${face.angles.roll.toFixed(1)}°`, x, infoY);
        infoY += 20;
      }

      if (face.smilingProbability !== undefined) {
        const smilePercent = (face.smilingProbability * 100).toFixed(0);
        ctx.fillText(`Smile: ${smilePercent}%`, x, infoY);
        infoY += 20;
      }

      if (face.leftEyeOpenProbability !== undefined && face.rightEyeOpenProbability !== undefined) {
        const leftEyePercent = (face.leftEyeOpenProbability * 100).toFixed(0);
        const rightEyePercent = (face.rightEyeOpenProbability * 100).toFixed(0);
        ctx.fillText(`Eyes: L${leftEyePercent}% R${rightEyePercent}%`, x, infoY);
      }
    }
  }

  private drawPoint(ctx: CanvasRenderingContext2D, point: { x: number; y: number }, width: number, height: number, label: string) {
    const px = point.x * width;
    const py = point.y * height;

    ctx.beginPath();
    ctx.arc(px, py, 4, 0, 2 * Math.PI);
    ctx.fill();

    ctx.fillStyle = '#ffffff';
    ctx.font = '12px Arial';
    ctx.fillText(label, px + 8, py);

    ctx.fillStyle = '#ff0000';
  }

  toggleDetection() {
    if (this.isDetecting()) {
      this.stopDetection();
    } else {
      this.startDetection();
    }
  }

  private async showAlert(header: string, message: string) {
    const alert = await this.alertController.create({
      header,
      message,
      buttons: ['OK'],
    });
    await alert.present();
  }
}
