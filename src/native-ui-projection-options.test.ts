import { describe, expect, it } from 'bun:test';

import type { CameraPreviewOptions } from './definitions';

describe('nativeUIProjection option types', () => {
  it('leaves nativeUIProjection undefined when omitted from option objects', () => {
    const options: CameraPreviewOptions = { position: 'rear' };
    expect(options.nativeUIProjection).toBeUndefined();
    expect(options.nativeUIProjectionSelector).toBeUndefined();
  });

  it('accepts explicit selector fields when enabled in option objects', () => {
    const options: CameraPreviewOptions = {
      nativeUIProjection: true,
      nativeUIProjectionSelector: '#camera-preview-projection',
    };
    expect(options.nativeUIProjection).toBe(true);
    expect(options.nativeUIProjectionSelector).toBe('#camera-preview-projection');
  });
});