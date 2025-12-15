import { Component, OnInit, OnDestroy, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  IonButton,
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar,
  IonIcon,
  IonLabel,
  IonToggle,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardTitle,
  ModalController,
} from '@ionic/angular/standalone';
import { CameraPreview, FaceDetectionResult, DetectedFace } from '@capgo/camera-preview';

@Component({
  selector: 'app-face-filter-demo',
  templateUrl: './face-filter-demo.component.html',
  styleUrls: ['./face-filter-demo.component.scss'],
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    IonButton,
    IonContent,
    IonHeader,
    IonTitle,
    IonToolbar,
    IonIcon,
    IonLabel,
    IonToggle,
    IonCard,
    IonCardContent,
    IonCardHeader,
    IonCardTitle,
  ],
})
export class FaceFilterDemoComponent implements OnInit, OnDestroy {
  protected detectedFaces = signal<DetectedFace[]>([]);
  protected isFaceDetectionActive = signal(false);
  protected faceCount = signal(0);
  protected showLandmarks = signal(true);
  private faceDetectionListener: any;

  constructor(private modalController: ModalController) {}

  async ngOnInit() {
    try {
      // Request permissions
      const permissions = await CameraPreview.requestPermissions();
      if (permissions.camera !== 'granted') {
        console.error('Camera permission denied');
        return;
      }

      // Start camera
      await CameraPreview.start({
        position: 'front',
        width: window.innerWidth,
        height: window.innerHeight,
        toBack: false,
        disableAudio: true,
      });

      // Start face detection
      await this.startFaceDetection();

    } catch (error) {
      console.error('Failed to start camera:', error);
    }
  }

  async ngOnDestroy() {
    try {
      await this.stopFaceDetection();
      await CameraPreview.stop();
    } catch (error) {
      console.error('Failed to stop camera:', error);
    }
  }

  async startFaceDetection() {
    try {
      // Start face detection with options
      await CameraPreview.startFaceDetection({
        performanceMode: 'fast',
        trackingEnabled: true,
        detectLandmarks: true,
        detectClassifications: true,
        maxFaces: 3,
        minFaceSize: 0.15,
      });

      // Listen for face detection results
      this.faceDetectionListener = await CameraPreview.addListener(
        'faceDetection',
        (result: FaceDetectionResult) => {
          this.detectedFaces.set(result.faces);
          this.faceCount.set(result.faces.length);

          // Log first face info
          if (result.faces.length > 0) {
            const face = result.faces[0];
            console.log('Face detected:', {
              trackingId: face.trackingId,
              bounds: face.bounds,
              rollAngle: face.rollAngle,
              yawAngle: face.yawAngle,
              smilingProbability: face.smilingProbability,
            });
          }
        }
      );

      this.isFaceDetectionActive.set(true);
      console.log('Face detection started');

    } catch (error) {
      console.error('Failed to start face detection:', error);
    }
  }

  async stopFaceDetection() {
    try {
      await CameraPreview.stopFaceDetection();
      if (this.faceDetectionListener) {
        await this.faceDetectionListener.remove();
      }
      this.isFaceDetectionActive.set(false);
      this.detectedFaces.set([]);
      this.faceCount.set(0);
      console.log('Face detection stopped');
    } catch (error) {
      console.error('Failed to stop face detection:', error);
    }
  }

  toggleFaceDetection() {
    if (this.isFaceDetectionActive()) {
      this.stopFaceDetection();
    } else {
      this.startFaceDetection();
    }
  }

  async close() {
    await this.modalController.dismiss();
  }

  /**
   * Get CSS transform for positioning a filter overlay on a detected face
   */
  getFaceTransform(face: DetectedFace): string {
    // Convert normalized coordinates to percentage
    const x = face.bounds.x * 100;
    const y = face.bounds.y * 100;
    const width = face.bounds.width * 100;
    const height = face.bounds.height * 100;

    // Apply rotation if available
    const rotation = face.rollAngle ? `rotate(${face.rollAngle}deg)` : '';

    return `translate(${x}%, ${y}%) ${rotation}`;
  }

  /**
   * Get CSS size for a filter overlay
   */
  getFaceSize(face: DetectedFace): { width: string; height: string } {
    return {
      width: `${face.bounds.width * 100}%`,
      height: `${face.bounds.height * 100}%`,
    };
  }

  /**
   * Get landmark position as percentage
   */
  getLandmarkPosition(x: number, y: number): { left: string; top: string } {
    return {
      left: `${x * 100}%`,
      top: `${y * 100}%`,
    };
  }
}
