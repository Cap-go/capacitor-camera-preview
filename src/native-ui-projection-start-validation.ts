import type { CameraPreviewOptions } from './definitions';

export const NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE =
  'nativeUIProjectionSelector is required when nativeUIProjection is true';

function isBlankCssWhitespace(value: string | undefined | null): boolean {
  if (value == null || value.length === 0) {
    return true;
  }
  for (const char of value) {
    if (char !== ' ' && char !== '\t' && char !== '\n' && char !== '\f' && char !== '\r') {
      return false;
    }
  }
  return true;
}

export function nativeUIProjectionMissingSelectorMessage(
  options: Pick<CameraPreviewOptions, 'nativeUIProjection' | 'nativeUIProjectionSelector'>,
): string | undefined {
  if (options.nativeUIProjection === true && isBlankCssWhitespace(options.nativeUIProjectionSelector)) {
    return NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE;
  }
  return undefined;
}
