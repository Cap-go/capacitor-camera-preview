import { describe, expect, it } from 'bun:test';
import type { CameraPreviewOptions } from './definitions';

describe('nativeUIProjection options', () => {
  it('defaults to off when omitted from start options', () => {
    const options: CameraPreviewOptions = { position: 'rear' };
    expect(options.nativeUIProjection).toBeUndefined();
    expect(options.nativeUIProjectionSelector).toBeUndefined();
  });

  it('accepts explicit selector when enabled', () => {
    const options: CameraPreviewOptions = {
      nativeUIProjection: true,
      nativeUIProjectionSelector: '#camera-preview-projection',
    };
    expect(options.nativeUIProjection).toBe(true);
    expect(options.nativeUIProjectionSelector).toBe('#camera-preview-projection');
  });
});