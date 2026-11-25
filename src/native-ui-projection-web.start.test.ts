import { beforeEach, describe, expect, test } from 'bun:test';
import { Window } from 'happy-dom';

import { NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE } from './native-ui-projection-start-validation';
import { CameraPreviewWeb } from './web';

describe('CameraPreviewWeb.start nativeUIProjection validation', () => {
  let window: Window;

  beforeEach(() => {
    window = new Window();
    globalThis.window = window as unknown as Window & typeof globalThis.window;
    globalThis.document = window.document;
  });

  test('rejects enabled projection without a selector before opening the camera', async () => {
    const plugin = new CameraPreviewWeb();
    const container = document.createElement('div');
    container.id = 'cameraView';
    document.body.appendChild(container);

    await expect(
      plugin.start({
        nativeUIProjection: true,
        parent: 'cameraView',
      }),
    ).rejects.toThrow(NATIVE_UI_PROJECTION_MISSING_SELECTOR_MESSAGE);
  });
});
