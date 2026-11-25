import type { CameraPreviewOptions } from './definitions';

export const NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE =
  'nativeUIProjectionSelector is required when nativeUIProjection is true';

export function nativeUIProjectionMissingSelectorMessage(
  options: Pick<CameraPreviewOptions, 'nativeUIProjection' | 'nativeUIProjectionSelector'>,
): string | undefined {
  if (options.nativeUIProjection === true) {
    const selector = options.nativeUIProjectionSelector;
    if (selector == null || selector.trim() === '') {
      return NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE;
    }
  }
  return undefined;
}
