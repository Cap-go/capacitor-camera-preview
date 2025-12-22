import { Component, Input, signal } from '@angular/core';
import { CommonModule } from '@angular/common';

export interface FaceGuidanceState {
  isAligned: boolean;
  feedback: string;
  faceDetected: boolean;
}

@Component({
  selector: 'app-face-guidance-overlay',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="face-guidance-overlay">
      <!-- Face centering guide (oval) -->
      <div class="face-guide-oval" [class.aligned]="state().isAligned"></div>
      
      <!-- Feedback message -->
      @if (state().faceDetected) {
        <div class="feedback-message" [class.success]="state().isAligned">
          {{ state().feedback }}
        </div>
      } @else {
        <div class="feedback-message warning">
          Position your face in the oval
        </div>
      }
      
      <!-- Success indicator -->
      @if (state().isAligned) {
        <div class="success-indicator">
          <svg viewBox="0 0 24 24" class="checkmark">
            <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/>
          </svg>
          <span>Perfect!</span>
        </div>
      }
    </div>
  `,
  styles: [`
    .face-guidance-overlay {
      position: fixed;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      pointer-events: none;
      z-index: 10000;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
    }
    
    .face-guide-oval {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      width: 70vw;
      max-width: 350px;
      height: 85vh;
      max-height: 450px;
      border: 3px dashed rgba(255, 255, 255, 0.6);
      border-radius: 50%;
      transition: all 0.3s ease;
    }
    
    .face-guide-oval.aligned {
      border-color: rgba(76, 217, 100, 0.9);
      border-style: solid;
      box-shadow: 0 0 20px rgba(76, 217, 100, 0.5);
      animation: pulse 1.5s ease-in-out infinite;
    }
    
    @keyframes pulse {
      0%, 100% {
        box-shadow: 0 0 20px rgba(76, 217, 100, 0.5);
      }
      50% {
        box-shadow: 0 0 30px rgba(76, 217, 100, 0.8);
      }
    }
    
    .feedback-message {
      position: absolute;
      top: 20%;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(0, 0, 0, 0.75);
      color: white;
      padding: 12px 24px;
      border-radius: 24px;
      font-size: 16px;
      font-weight: 500;
      text-align: center;
      min-width: 200px;
      backdrop-filter: blur(10px);
      pointer-events: none;
      transition: all 0.3s ease;
    }
    
    .feedback-message.success {
      background: rgba(76, 217, 100, 0.9);
      color: white;
    }
    
    .feedback-message.warning {
      background: rgba(255, 149, 0, 0.9);
      color: white;
    }
    
    .countdown-timer {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: rgba(0, 0, 0, 0.8);
      border-radius: 50%;
      width: 120px;
      height: 120px;
      animation: countdown-pulse 1s ease-in-out;
    }
    
    @keyframes countdown-pulse {
      0% {
        transform: translate(-50%, -50%) scale(1);
        opacity: 1;
      }
      50% {
        transform: translate(-50%, -50%) scale(1.1);
      }
      100% {
        transform: translate(-50%, -50%) scale(1);
        opacity: 1;
      }
    }
    
    .countdown-number {
      font-size: 48px;
      font-weight: bold;
      color: white;
      line-height: 1;
    }
    
    .countdown-text {
      font-size: 14px;
      color: rgba(255, 255, 255, 0.8);
      margin-top: 4px;
    }
    
    .success-indicator {
      position: absolute;
      top: 15%;
      left: 50%;
      transform: translateX(-50%);
      display: flex;
      align-items: center;
      gap: 8px;
      background: rgba(76, 217, 100, 0.95);
      color: white;
      padding: 10px 20px;
      border-radius: 24px;
      font-size: 18px;
      font-weight: 600;
      animation: slide-in 0.3s ease-out;
    }
    
    @keyframes slide-in {
      from {
        transform: translateX(-50%) translateY(-20px);
        opacity: 0;
      }
      to {
        transform: translateX(-50%) translateY(0);
        opacity: 1;
      }
    }
    
    .checkmark {
      width: 24px;
      height: 24px;
      fill: white;
    }
  `]
})
export class FaceGuidanceOverlayComponent {
  @Input()
  set guidance(value: FaceGuidanceState) {
    this.state.set(value);
  }
  
  protected state = signal<FaceGuidanceState>({
    isAligned: false,
    feedback: 'Position your face in the oval',
    faceDetected: false
  });
}
