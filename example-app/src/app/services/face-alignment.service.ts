import { Injectable } from '@angular/core';
import { DetectedFace } from '@capgo/camera-preview';

export interface AlignmentValidationConfig {
  maxRollDegrees?: number;
  maxPitchDegrees?: number;
  maxYawDegrees?: number;
  minFaceSize?: number;
  maxFaceSize?: number;
  minCenterX?: number;
  maxCenterX?: number;
  minCenterY?: number;
  maxCenterY?: number;
}

export interface AlignmentResult {
  isValid: boolean;
  isRollValid: boolean;
  isPitchValid: boolean;
  isYawValid: boolean;
  isSizeValid: boolean;
  isCenteringValid: boolean;
  primaryFeedback: string;
  allFeedback: string[];
}

@Injectable({
  providedIn: 'root'
})
export class FaceAlignmentService {
  private config: Required<AlignmentValidationConfig> = {
    maxRollDegrees: 15.0,
    maxPitchDegrees: 15.0,
    maxYawDegrees: 20.0,
    minFaceSize: 0.20, // 20% of frame
    maxFaceSize: 0.80, // 80% of frame
    minCenterX: 0.35, // 35-65% horizontally
    maxCenterX: 0.65,
    minCenterY: 0.30, // 30-70% vertically
    maxCenterY: 0.70
  };

  constructor() {}

  /**
   * Update validation configuration
   */
  setConfig(config: AlignmentValidationConfig): void {
    this.config = { ...this.config, ...config };
  }

  /**
   * Validate face alignment
   */
  validateFace(face: DetectedFace): AlignmentResult {
    const result: AlignmentResult = {
      isValid: false,
      isRollValid: false,
      isPitchValid: false,
      isYawValid: false,
      isSizeValid: false,
      isCenteringValid: false,
      primaryFeedback: '',
      allFeedback: []
    };

    // Validate roll (head tilt)
    const rollAngle = face.rollAngle ?? 0;
    if (Math.abs(rollAngle) > this.config.maxRollDegrees) {
      result.isRollValid = false;
      const feedback = rollAngle > 0 
        ? 'Tilt your head less to the right' 
        : 'Tilt your head less to the left';
      result.allFeedback.push(feedback);
    } else {
      result.isRollValid = true;
    }

    // Validate pitch (head nod)
    const pitchAngle = face.pitchAngle ?? 0;
    if (Math.abs(pitchAngle) > this.config.maxPitchDegrees) {
      result.isPitchValid = false;
      const feedback = pitchAngle > 0 
        ? 'Look down less' 
        : 'Look up less';
      result.allFeedback.push(feedback);
    } else {
      result.isPitchValid = true;
    }

    // Validate yaw (head turn)
    const yawAngle = face.yawAngle ?? 0;
    if (Math.abs(yawAngle) > this.config.maxYawDegrees) {
      result.isYawValid = false;
      const feedback = yawAngle > 0 
        ? 'Turn your head less to the right' 
        : 'Turn your head less to the left';
      result.allFeedback.push(feedback);
    } else {
      result.isYawValid = true;
    }

    // Validate face size
    const faceSize = Math.max(face.bounds.width, face.bounds.height);
    if (faceSize < this.config.minFaceSize) {
      result.isSizeValid = false;
      result.allFeedback.push('Move closer to the camera');
    } else if (faceSize > this.config.maxFaceSize) {
      result.isSizeValid = false;
      result.allFeedback.push('Move farther from the camera');
    } else {
      result.isSizeValid = true;
    }

    // Validate face centering
    const centerX = face.bounds.x + face.bounds.width / 2.0;
    const centerY = face.bounds.y + face.bounds.height / 2.0;

    if (centerX < this.config.minCenterX) {
      result.isCenteringValid = false;
      result.allFeedback.push('Move right');
    } else if (centerX > this.config.maxCenterX) {
      result.isCenteringValid = false;
      result.allFeedback.push('Move left');
    } else if (centerY < this.config.minCenterY) {
      result.isCenteringValid = false;
      result.allFeedback.push('Move down');
    } else if (centerY > this.config.maxCenterY) {
      result.isCenteringValid = false;
      result.allFeedback.push('Move up');
    } else {
      result.isCenteringValid = true;
    }

    // Overall validation
    result.isValid = result.isRollValid && result.isPitchValid && 
                     result.isYawValid && result.isSizeValid && result.isCenteringValid;

    // Set primary feedback
    result.primaryFeedback = result.allFeedback.length > 0 
      ? result.allFeedback[0] 
      : 'Face aligned perfectly';

    return result;
  }
}
