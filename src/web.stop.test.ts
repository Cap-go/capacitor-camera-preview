import { beforeEach, describe, expect, test } from 'bun:test';
import { Window } from 'happy-dom';

import { CameraPreviewWeb } from './web';

describe('CameraPreviewWeb.stop', () => {
  let window: Window;

  beforeEach(() => {
    window = new Window();
    globalThis.window = window as unknown as Window & typeof globalThis.window;
    globalThis.document = window.document;
    globalThis.requestAnimationFrame = (callback: FrameRequestCallback) => {
      callback(0);
      return 0;
    };
  });

  test('stops media tracks and clears isStarted when the preview video is no longer in the DOM', async () => {
    const plugin = new CameraPreviewWeb();
    let trackStopped = false;
    const track = {
      stop: () => {
        trackStopped = true;
      },
    };
    const stream = {
      getTracks: () => [track],
    };

    const container = document.createElement('div');
    document.body.appendChild(container);

    const video = document.createElement('video');
    video.id = 'capgo_video';
    Object.defineProperty(video, 'srcObject', {
      configurable: true,
      value: stream,
    });
    container.appendChild(video);

    (plugin as unknown as { videoElement: HTMLVideoElement | null }).videoElement = video;
    (plugin as unknown as { isStarted: boolean }).isStarted = true;

    container.remove();

    expect(document.getElementById('capgo_video')).toBeNull();

    await plugin.stop();

    expect(trackStopped).toBe(true);
    expect((plugin as unknown as { isStarted: boolean }).isStarted).toBe(false);
    expect((plugin as unknown as { videoElement: HTMLVideoElement | null }).videoElement).toBeNull();
  });

  test('removes the preview video from the DOM when it is still connected', async () => {
    const plugin = new CameraPreviewWeb();
    const track = { stop: () => undefined };
    const stream = {
      getTracks: () => [track],
    };

    const video = document.createElement('video');
    video.id = 'capgo_video';
    Object.defineProperty(video, 'srcObject', {
      configurable: true,
      value: stream,
    });
    document.body.appendChild(video);

    (plugin as unknown as { videoElement: HTMLVideoElement | null }).videoElement = video;
    (plugin as unknown as { isStarted: boolean }).isStarted = true;

    await plugin.stop();

    expect(document.getElementById('capgo_video')).toBeNull();
    expect((plugin as unknown as { isStarted: boolean }).isStarted).toBe(false);
  });
});
