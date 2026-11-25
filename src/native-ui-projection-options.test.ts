import { describe, expect, it } from 'bun:test';

import type { CameraPreviewOptions } from './definitions';
import {
  NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE,
  nativeUIProjectionMissingSelectorMessage,
} from './native-ui-projection-start-validation';

describe('nativeUIProjection start validation', () => {
  it('leaves validation undefined when projection is omitted or disabled', () => {
    expect(nativeUIProjectionMissingSelectorMessage({ position: 'rear' } as CameraPreviewOptions)).toBeUndefined();
    expect(
      nativeUIProjectionMissingSelectorMessage({
        nativeUIProjection: false,
      }),
    ).toBeUndefined();
  });

  it('rejects enabled projection without a selector', () => {
    expect(nativeUIProjectionMissingSelectorMessage({ nativeUIProjection: true })).toBe(
      NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE,
    );
    expect(
      nativeUIProjectionMissingSelectorMessage({
        nativeUIProjection: true,
        nativeUIProjectionSelector: '  ',
      }),
    ).toBe(NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE);
  });

  it('accepts enabled projection with a non-empty selector', () => {
    expect(
      nativeUIProjectionMissingSelectorMessage({
        nativeUIProjection: true,
        nativeUIProjectionSelector: '#camera-preview-projection',
      }),
    ).toBeUndefined();
  });
});
