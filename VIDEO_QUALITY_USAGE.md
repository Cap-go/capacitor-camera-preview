# Video Quality Control Feature

## Overview

The `videoQuality` parameter allows you to control the quality of video recordings on both iOS and Android platforms. This feature is particularly useful when you need to balance video quality with file size and performance considerations.

## Available Options

The `videoQuality` parameter accepts three values:

- **`'low'`** - Lowest quality, smallest file size
  - **iOS**: VGA (640x480) resolution
  - **Android**: SD (480p) resolution
  
- **`'medium'`** - Medium quality, balanced file size
  - **iOS**: HD (1280x720) resolution  
  - **Android**: HD (720p) resolution
  
- **`'high'`** - Highest quality, largest file size (default)
  - **iOS**: Full HD (1920x1080) or 4K (3840x2160) depending on aspect ratio
  - **Android**: Full HD (1080p) resolution

## Usage Example

### Basic Usage

```typescript
import { CameraPreview } from '@capgo/camera-preview';

// Start camera with medium quality video
await CameraPreview.start({
  position: 'rear',
  enableVideoMode: true,  // Required for video recording
  videoQuality: 'medium', // Set video quality
});

// Start recording
await CameraPreview.startRecordVideo({});

// Stop recording
const result = await CameraPreview.stopRecordVideo();
console.log('Video saved to:', result.videoFilePath);
```

### Advanced Usage with Multiple Options

```typescript
import { CameraPreview, type CameraPreviewOptions } from '@capgo/camera-preview';

const cameraOptions: CameraPreviewOptions = {
  position: 'rear',
  aspectRatio: '16:9',
  enableVideoMode: true,
  videoQuality: 'low',      // For smaller file sizes
  disableAudio: false,       // Enable audio recording
  storeToFile: true,         // Store to file instead of base64
  toBack: true,
};

try {
  // Start the camera with video mode enabled
  await CameraPreview.start(cameraOptions);
  
  // Start recording video
  await CameraPreview.startRecordVideo({});
  
  // Record for some time...
  await new Promise(resolve => setTimeout(resolve, 5000));
  
  // Stop recording
  const { videoFilePath } = await CameraPreview.stopRecordVideo();
  console.log('Video recorded:', videoFilePath);
  
} catch (error) {
  console.error('Video recording failed:', error);
}
```

### Switching Quality Dynamically

```typescript
// You can restart the camera with different quality settings
await CameraPreview.stop();

await CameraPreview.start({
  position: 'rear',
  enableVideoMode: true,
  videoQuality: 'high',  // Switch to high quality
});
```

## Platform-Specific Behavior

### iOS

- The `videoQuality` parameter affects the entire camera session preset
- Quality settings use AVCaptureSession presets:
  - `low` → `.vga640x480` (fallback: `.low`)
  - `medium` → `.hd1280x720` (fallback: `.medium`)
  - `high` → `.hd1920x1080` or `.hd4K3840x2160` (fallback: `.photo` or `.high`)
- The actual resolution may vary based on device capabilities

### Android

- The `videoQuality` parameter configures CameraX's `QualitySelector`
- Quality settings use intelligent fallback strategies:
  - `low` → Targets SD (480p), falls back to lower if needed
  - `medium` → Targets HD (720p), falls back to SD
  - `high` → Targets FHD (1080p), falls back through HD to SD
- **Important**: `enableVideoMode` must be set to `true` for video recording to work

## File Size Comparison

Based on a typical 5-second video recording:

| Quality | iOS File Size | Android File Size | Resolution |
|---------|---------------|-------------------|------------|
| Low     | ~2-3 MB       | ~2-3 MB          | 480p       |
| Medium  | ~4-6 MB       | ~4-6 MB          | 720p       |
| High    | ~8-10 MB      | ~8-10 MB         | 1080p      |

*Note: Actual file sizes will vary based on content complexity, motion, and device capabilities.*

## Best Practices

1. **For social media sharing**: Use `'medium'` or `'low'` quality to reduce upload times
2. **For archival purposes**: Use `'high'` quality for best results
3. **For bandwidth-constrained situations**: Use `'low'` quality
4. **For performance**: Lower quality settings may improve camera initialization time

## Troubleshooting

### Video is too large

If your videos are too large, try using `'medium'` or `'low'` quality:

```typescript
await CameraPreview.start({
  enableVideoMode: true,
  videoQuality: 'low',  // Smaller file size
});
```

### Video recording not working on Android

Make sure `enableVideoMode` is set to `true`:

```typescript
await CameraPreview.start({
  enableVideoMode: true,  // Required!
  videoQuality: 'medium',
});
```

### Quality doesn't match expectation

The actual quality may vary based on:
- Device camera capabilities
- Available storage space
- System resources
- Aspect ratio settings

## See Also

- [Main README](./README.md)
- [API Documentation](./README.md#api)
- [Example App](./example-app)
