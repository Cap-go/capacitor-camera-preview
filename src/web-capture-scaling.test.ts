import { describe, expect, test } from 'bun:test';

import { getWebCaptureImageDrawRects } from './web-capture-scaling';

describe('getWebCaptureImageDrawRects', () => {
  test('scales the full video frame into the capture canvas (regression #452)', () => {
    const videoWidth = 1920;
    const videoHeight = 1080;
    const captureWidth = 640;
    const captureHeight = 360;

    const rects = getWebCaptureImageDrawRects(videoWidth, videoHeight, captureWidth, captureHeight);

    expect(rects.sx).toBe(0);
    expect(rects.sy).toBe(0);
    expect(rects.sWidth).toBe(videoWidth);
    expect(rects.sHeight).toBe(videoHeight);
    expect(rects.dWidth).toBe(captureWidth);
    expect(rects.dHeight).toBe(captureHeight);
  });

  test('uses full source dimensions when output matches native resolution', () => {
    const rects = getWebCaptureImageDrawRects(1280, 720, 1280, 720);

    expect(rects.sWidth).toBe(1280);
    expect(rects.sHeight).toBe(720);
    expect(rects.dWidth).toBe(1280);
    expect(rects.dHeight).toBe(720);
  });
});
