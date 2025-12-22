import { Component, OnDestroy, OnInit, signal, computed, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { IonContent, IonHeader, IonTitle, IonToolbar, IonBackButton, IonButtons, IonBadge, IonChip, IonIcon } from '@ionic/angular/standalone';
import { CapacitorCameraViewService } from '../../core/capacitor-camera-preview.service';
import { DetectedFace, FaceDetectionResult } from '@capgo/camera-preview';
import { FaceGuidanceOverlayComponent, FaceGuidanceState } from '../../components/face-guidance-overlay/face-guidance-overlay.component';
import { addIcons } from 'ionicons';
import { checkmarkCircle, alertCircle, flash, flashOff, camera, cameraReverse, closeCircle } from 'ionicons/icons';

@Component({
  selector: 'app-face-detection-demo',
  templateUrl: './face-detection-demo.page.html',
  styleUrls: ['./face-detection-demo.page.scss'],
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, 
    IonContent, 
    IonHeader, 
    IonTitle, 
    IonToolbar, 
    IonBackButton, 
    IonButtons,
    IonBadge,
    IonChip,
    IonIcon,
    FaceGuidanceOverlayComponent
  ],
})
export class FaceDetectionDemoPage implements OnInit, OnDestroy {
  /**
   * Indicates if the camera has started
   */
  protected cameraStarted = signal<boolean>(false);
  /**
   * Indicates if face detection is active
   */
  protected faceDetectionActive = signal<boolean>(false);
  /**
   * List of currently detected faces
   */
  protected detectedFaces = signal<DetectedFace[]>([]);
  /**
   * Width of the camera frame
   */
  protected frameWidth = signal<number>(0);
  /**
   * Height of the camera frame
   */
  protected frameHeight = signal<number>(0);
  /**
   * Frames per second (FPS) of face detection
   */
  protected fps = signal<number>(0);
  /**
   * Number of processed frames
   */
  protected processedFrames = signal<number>(0);
  

  
  // UI state
  /**
   * Controls visibility of the face guidance overlay
   */
  protected showGuidanceOverlay = signal<boolean>(true);
  /**
   * Controls visibility of the debug overlay
   */
  protected showDebugOverlay = signal<boolean>(false);
  /**
   * Controls visibility of facial landmarks
   */
  protected showLandmarks = signal<boolean>(true);
  
  // Bottom sheet state - now percentage based from top
  /**
   * Current position of the bottom sheet as a percentage from the top (50% = half screen)
   */
  protected sheetTopPercent = signal<number>(50);
  /**
   * Minimum allowed top percentage for the sheet
   */
  protected sheetMinPercent = 5;
  /**
   * Maximum allowed top percentage for the sheet
   */
  protected sheetMaxPercent = 85;
  /**
   * Indicates if the sheet is currently being dragged
   */
  protected sheetDragging = signal<boolean>(false);
  private dragStartY = 0;
  private dragStartTopPercent = 0;

  private frameCount = 0;
  private totalFrameCount = 0;
  private skippedFrameCount = 0;
  private lastFpsUpdate = Date.now();
  
  // Cached screen dimensions for performance
  private screenWidth = window.innerWidth;
  private screenHeight = window.innerHeight;
  private rafId: number | null = null;
  private pendingUpdate = false;
  
  // Computed guidance state for overlay
  protected guidanceState = computed<FaceGuidanceState>(() => {
    const faces = this.detectedFaces();
    
    if (faces.length === 0) {
      return {
        isAligned: false,
        feedback: 'Position your face in the oval',
        faceDetected: false
      };
    }
    
    return {
      isAligned: true,
      feedback: 'Face detected',
      faceDetected: true
    };
  });

  constructor(
    private cameraService: CapacitorCameraViewService
  ) {
    // Register icons
    addIcons({ checkmarkCircle, alertCircle, flash, flashOff, camera, cameraReverse, closeCircle });
  }

  async ngOnInit() {
    // Add transparent class to body for camera to show through
    document.body.classList.add('face-detection-active');
    // Initialize sheet position to half screen (50%)
    this.sheetTopPercent.set(50);
    
    // Cache screen dimensions and update on resize
    this.updateScreenDimensions();
    window.addEventListener('resize', this.handleResize);
    
    await this.startCameraWithFaceDetection();
  }
  
  /**
   * Handles window resize events to update cached screen dimensions
   */
  private handleResize = () => {
    this.updateScreenDimensions();
  };
  
  /**
   * Updates cached screen width and height for overlay calculations
   */
  private updateScreenDimensions() {
    this.screenWidth = window.innerWidth;
    this.screenHeight = window.innerHeight;
  }

  async ngOnDestroy() {
    document.body.classList.remove('face-detection-active');
    window.removeEventListener('resize', this.handleResize);
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
    }
    await this.cleanup();
  }

  ionViewWillEnter() {
    document.body.classList.add('face-detection-active');
  }

  ionViewWillLeave() {
    document.body.classList.remove('face-detection-active');
  }

  /**
   * Initializes the camera and starts face detection with optimal settings.
   * Sets up a listener for face detection results and updates UI state efficiently.
   * Handles frame skipping, motion detection, and power management natively.
   * @returns {Promise<void>}
   */
  private async startCameraWithFaceDetection() {
    try {
      // Start camera in background (toBack: true) with optimized settings
      // Resolution is automatically set to 720p in native code
      // Frame rate is automatically set to 20-25 FPS in native code
      await this.cameraService.start({
        position: 'front',
        x: 0,
        y: 0,
        width: window.innerWidth,
        height: window.innerHeight,
        toBack: true,
        disableAudio: true,
      });

      this.cameraStarted.set(true);

      // Add face detection listener with optimization tracking
      await this.cameraService.addFaceDetectionListener((result: FaceDetectionResult) => {
        this.totalFrameCount++;
        // Use requestAnimationFrame to batch UI updates for performance
        if (!this.pendingUpdate) {
          this.pendingUpdate = true;
          this.rafId = requestAnimationFrame(() => {
            this.pendingUpdate = false;
            // Update detected faces and frame info
            this.detectedFaces.set(result.faces);
            this.frameWidth.set(result.frameWidth);
            this.frameHeight.set(result.frameHeight);
            // Update FPS and processed frame count
            this.updateFps();
            this.processedFrames.set(this.processedFrames() + 1);
          });
        }
      });

      // Start face detection with optimized settings
      // Native code will automatically:
      // - Process every 3rd frame (frame skipping)
      // - Skip static frames (motion detection)
      // - Pause when app backgrounds
      // - Throttle on thermal events
      await this.cameraService.startFaceDetection({
        performanceMode: 'fast', // Uses optimized ML Kit/Vision settings
        trackingEnabled: true,
        detectLandmarks: true,
        maxFaces: 5,
        minFaceSize: 0.15,
      });

      this.faceDetectionActive.set(true);
      console.log('🚀 Face detection started');
    } catch (error) {
      console.error('Failed to start camera with face detection:', error);
    }
  }
  
  /**
   * Updates the FPS (frames per second) metric for the UI.
   * Called once per frame, updates every second.
   */
  private updateFps() {
    this.frameCount++;
    const now = Date.now();
    const elapsed = now - this.lastFpsUpdate;
    if (elapsed >= 1000) {
      this.fps.set(Math.round((this.frameCount * 1000) / elapsed));
      this.frameCount = 0;
      this.lastFpsUpdate = now;
    }
  }
  
  // UI toggle methods
  /**
   * Toggles the face guidance overlay on/off.
   */
  protected toggleGuidanceOverlay() {
    this.showGuidanceOverlay.set(!this.showGuidanceOverlay());
  }

  /**
   * Toggles the debug overlay on/off.
   */
  protected toggleDebugOverlay() {
    this.showDebugOverlay.set(!this.showDebugOverlay());
  }

  /**
   * Toggles the display of facial landmarks.
   */
  protected toggleLandmarks() {
    this.showLandmarks.set(!this.showLandmarks());
  }
  
  

  /**
   * Cleans up camera and face detection resources when leaving the page.
   * Ensures listeners and camera are properly stopped.
   * @returns {Promise<void>}
   */
  private async cleanup() {
    try {
      if (this.faceDetectionActive()) {
        await this.cameraService.stopFaceDetection();
        await this.cameraService.removeFaceDetectionListener();
      }
      if (this.cameraStarted()) {
        await this.cameraService.stop();
      }
    } catch (error) {
      console.error('Cleanup error:', error);
    }
  }

  /**
   * Returns the CSS style object for a face bounding box overlay.
   * @param face The detected face object
   * @returns CSS style object for the bounding box
   */
  protected getFaceBoxStyle(face: DetectedFace) {
    // Use cached dimensions for better performance
    const left = face.bounds.x * this.screenWidth;
    const top = face.bounds.y * this.screenHeight;
    const width = face.bounds.width * this.screenWidth;
    const height = face.bounds.height * this.screenHeight;

    return {
      position: 'absolute',
      left: `${left}px`,
      top: `${top}px`,
      width: `${width}px`,
      height: `${height}px`,
      border: '2px solid #00ff00',
      'border-radius': '8px',
      'box-shadow': '0 0 10px rgba(0, 255, 0, 0.5)',
    };
  }

  /**
   * Returns the CSS style object for a facial landmark overlay.
   * @param x Normalized x coordinate (0-1)
   * @param y Normalized y coordinate (0-1)
   * @returns CSS style object for the landmark dot
   */
  protected getLandmarkStyle(x: number, y: number) {
    // Use cached dimensions and pre-calculate positions for better performance
    const left = x * this.screenWidth - 4;
    const top = y * this.screenHeight - 4;

    return {
      position: 'absolute',
      left: `${left}px`,
      top: `${top}px`,
      width: '8px',
      height: '8px',
      'background-color': '#ff0000',
      'border-radius': '50%',
      'box-shadow': '0 0 6px rgba(255, 0, 0, 0.8)',
    };
  }

  // Bottom sheet gestures
  /**
   * Handles touch start event for the draggable bottom sheet.
   * @param ev Touch event
   */
  protected onSheetTouchStart(ev: TouchEvent) {
    const touch = ev.touches[0];
    this.dragStartY = touch.clientY;
    this.dragStartTopPercent = this.sheetTopPercent();
    this.sheetDragging.set(true);
  }

  /**
   * Handles touch move event for the draggable bottom sheet.
   * @param ev Touch event
   */
  protected onSheetTouchMove(ev: TouchEvent) {
    if (!this.sheetDragging()) return;
    ev.preventDefault();
    const touch = ev.touches[0];
    const deltaY = touch.clientY - this.dragStartY;
    const screenHeight = window.innerHeight;
    const deltaPercent = (deltaY / screenHeight) * 100;
    let nextPercent = this.dragStartTopPercent + deltaPercent;
    // Clamp between min and max
    nextPercent = Math.max(this.sheetMinPercent, Math.min(this.sheetMaxPercent, nextPercent));
    this.sheetTopPercent.set(nextPercent);
  }

  /**
   * Handles touch end event for the draggable bottom sheet.
   */
  protected onSheetTouchEnd() {
    // Allow sheet to stay at any position (no snapping)
    this.sheetDragging.set(false);
  }

  // Pointer events fallback (for simulators/desktops)
  /**
   * Handles pointer down event for the draggable bottom sheet (desktop/simulator fallback).
   * @param ev Pointer event
   */
  protected onSheetPointerDown(ev: PointerEvent) {
    this.dragStartY = ev.clientY;
    this.dragStartTopPercent = this.sheetTopPercent();
    this.sheetDragging.set(true);
  }

  /**
   * Handles pointer move event for the draggable bottom sheet (desktop/simulator fallback).
   * @param ev Pointer event
   */
  protected onSheetPointerMove(ev: PointerEvent) {
    if (!this.sheetDragging()) return;
    ev.preventDefault();
    const deltaY = ev.clientY - this.dragStartY;
    const screenHeight = window.innerHeight;
    const deltaPercent = (deltaY / screenHeight) * 100;
    let nextPercent = this.dragStartTopPercent + deltaPercent;
    // Clamp between min and max
    nextPercent = Math.max(this.sheetMinPercent, Math.min(this.sheetMaxPercent, nextPercent));
    this.sheetTopPercent.set(nextPercent);
  }

  /**
   * Handles pointer up event for the draggable bottom sheet (desktop/simulator fallback).
   */
  protected onSheetPointerUp() {
    // Allow sheet to stay at any position (no snapping)
    this.sheetDragging.set(false);
  }

  /**
   * Returns the CSS style object for the draggable bottom sheet.
   * @returns CSS style object for the sheet
   */
  protected getSheetStyle() {
    return {
      top: `${this.sheetTopPercent()}%`,
    } as any;
  }
}
