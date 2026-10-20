import { beforeEach, describe, expect, test } from 'bun:test';
import { Window } from 'happy-dom';

import { CameraPreviewWeb } from './web';

type RecorderCapture = {
  stream: MediaStream;
  options?: MediaRecorderOptions;
};

describe('CameraPreviewWeb videoBitrate', () => {
  let window: Window;
  let lastRecorder: RecorderCapture | undefined;

  beforeEach(() => {
    window = new Window();
    globalThis.window = window as unknown as Window & typeof globalThis.window;
    globalThis.document = window.document;
    lastRecorder = undefined;

    class MockMediaRecorder {
      static isTypeSupported() {
        return true;
      }

      state = 'inactive';
      mimeType = 'video/webm';
      ondataavailable: ((event: BlobEvent) => void) | null = null;
      onstop: (() => void) | null = null;
      onerror: ((event: Event) => void) | null = null;

      constructor(stream: MediaStream, options?: MediaRecorderOptions) {
        lastRecorder = { stream, options };
      }

      start() {
        this.state = 'recording';
      }

      stop() {
        this.state = 'inactive';
      }
    }

    globalThis.MediaRecorder = MockMediaRecorder as unknown as typeof MediaRecorder;
  });

  function attachRunningPreview(plugin: CameraPreviewWeb) {
    const track = { stop: () => undefined };
    const stream = {
      getTracks: () => [track],
    } as MediaStream;

    const video = document.createElement('video');
    video.id = 'capgo_video';
    Object.defineProperty(video, 'srcObject', {
      configurable: true,
      value: stream,
    });
    document.body.appendChild(video);

    (plugin as unknown as { videoElement: HTMLVideoElement | null }).videoElement = video;
    (plugin as unknown as { isStarted: boolean }).isStarted = true;
    return stream;
  }

  test('startRecordVideo uses start-level videoBitrate when the call omits it', async () => {
    const plugin = new CameraPreviewWeb();
    attachRunningPreview(plugin);
    (plugin as unknown as { startVideoBitrate: number | null }).startVideoBitrate = 2_500_000;

    await plugin.startRecordVideo({});

    expect(lastRecorder?.options?.videoBitsPerSecond).toBe(2_500_000);
  });

  test('startRecordVideo prefers per-call videoBitrate over the start-level default', async () => {
    const plugin = new CameraPreviewWeb();
    attachRunningPreview(plugin);
    (plugin as unknown as { startVideoBitrate: number | null }).startVideoBitrate = 2_500_000;

    await plugin.startRecordVideo({ videoBitrate: 1_000_000 });

    expect(lastRecorder?.options?.videoBitsPerSecond).toBe(1_000_000);
  });

  test('startRecordVideo falls back to start-level bitrate when per-call value is invalid', async () => {
    const plugin = new CameraPreviewWeb();
    attachRunningPreview(plugin);
    (plugin as unknown as { startVideoBitrate: number | null }).startVideoBitrate = 2_500_000;

    await plugin.startRecordVideo({ videoBitrate: 0 });

    expect(lastRecorder?.options?.videoBitsPerSecond).toBe(2_500_000);
  });

  test('stop clears the stored start-level videoBitrate', async () => {
    const plugin = new CameraPreviewWeb();
    const stream = attachRunningPreview(plugin);
    (plugin as unknown as { startVideoBitrate: number | null }).startVideoBitrate = 2_500_000;

    await plugin.stop();

    expect((plugin as unknown as { startVideoBitrate: number | null }).startVideoBitrate).toBeNull();
    expect((plugin as unknown as { videoElement: HTMLVideoElement | null }).videoElement).toBeNull();
    stream.getTracks().forEach((track) => track.stop());
  });
});
