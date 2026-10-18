/** Source and destination rects for scaling a video frame into the capture canvas. */
export function getWebCaptureImageDrawRects(
  videoWidth: number,
  videoHeight: number,
  captureWidth: number,
  captureHeight: number,
): {
  sx: number;
  sy: number;
  sWidth: number;
  sHeight: number;
  dx: number;
  dy: number;
  dWidth: number;
  dHeight: number;
} {
  return {
    sx: 0,
    sy: 0,
    sWidth: videoWidth,
    sHeight: videoHeight,
    dx: 0,
    dy: 0,
    dWidth: captureWidth,
    dHeight: captureHeight,
  };
}
