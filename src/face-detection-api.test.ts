import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const definitionsSource = readFileSync(resolve(import.meta.dir, 'definitions.ts'), 'utf8');

describe('face detection API surface', () => {
  test('definitions expose realtime face detection methods and events', () => {
    expect(definitionsSource.includes('startFaceDetection(options?: FaceDetectionOptions)')).toBe(true);
    expect(definitionsSource.includes('stopFaceDetection()')).toBe(true);
    expect(definitionsSource.includes("eventName: 'faceDetected'")).toBe(true);
    expect(definitionsSource.includes("eventName: 'faceDetectionError'")).toBe(true);
    expect(definitionsSource.includes('faceDetection?: boolean | FaceDetectionOptions')).toBe(true);
  });
});
