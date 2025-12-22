# Camera Preview Example App

This is a comprehensive example application demonstrating the capabilities of the [@capgo/camera-preview](https://www.npmjs.com/package/@capgo/camera-preview) Capacitor plugin.

## Overview

Built with **Ionic Angular**, this example app showcases all the features of the Capacitor Camera Preview plugin, including:

- 📸 Camera preview and photo capture
- 🎥 Video recording
- 🔍 Manual focus, zoom, and exposure controls
- 💡 Flash modes and camera switching
- 🎭 Real-time face detection with visual overlays
- 📊 Performance monitoring and statistics

## Prerequisites

- [Node.js](https://nodejs.org/) (v18 or higher recommended)
- [Bun](https://bun.sh/) (used in this project) or npm/yarn
- [Capacitor CLI](https://capacitorjs.com/docs/cli)
- For iOS development:
  - macOS
  - Xcode 14 or higher
  - CocoaPods
- For Android development:
  - Android Studio
  - JDK 17
  - Android SDK

## Installation

1. **Install dependencies:**
   ```bash
   bun install
   # or
   npm install
   ```

2. **Sync Capacitor:**
   ```bash
   bun run build
   # This runs: ng build && cap sync ios
   ```

3. **For Android:**
   ```bash
   npx cap sync android
   npx cap open android
   ```

4. **For iOS:**
   ```bash
   npx cap sync ios
   npx cap open ios
   ```

## Development

### Run in Browser (Limited Functionality)
```bash
bun start
# or
npm start
```
**Note:** Camera features require a native device/simulator.

### Build for Production
```bash
bun run build
```

### Run Tests
```bash
bun test
# or
npm test
```

### Linting
```bash
bun run lint
```

## Key Features Demonstrated

### 1. Camera View Page
The main camera interface showcasing:
- **Live Camera Preview** - Full-screen camera feed with HTML/JS overlays
- **Camera Controls:**
  - Switch between front/rear cameras
  - Adjust zoom level (0-100%)
  - Manual focus control
  - Exposure compensation
  - Flash modes (off/on/auto/torch)
- **Photo Capture** - Take photos with custom quality settings
- **Video Recording** - Start/stop video recording

### 2. Face Detection Demo Page
Advanced face detection capabilities:
- **Real-time Face Detection** - Detect up to 10 faces simultaneously
- **Visual Overlays:**
  - Bounding boxes around detected faces
  - Facial landmarks (eyes, nose, mouth)
  - Tracking IDs for each face
- **Performance Modes:**
  - **Fast Mode** - Real-time detection optimized for speed
  - **Accurate Mode** - High-quality detection with more details
- **Analytics:**
  - Smile probability
  - Eye open probabilities (left/right)
  - Head rotation angles (roll, yaw, pitch)
  - FPS monitoring

### 3. Configuration Options
Comprehensive settings for:
- Camera position and orientation
- Focus modes (auto, continuous, manual)
- Exposure settings
- Flash behavior
- Photo quality and format
- Video recording parameters
- Face detection sensitivity and features

## Project Structure

```
example-app/
├── src/
│   ├── app/
│   │   ├── components/       # Reusable UI components
│   │   ├── core/             # Core services and utilities
│   │   ├── pages/            # Main application pages
│   │   │   ├── camera-view/        # Camera control page
│   │   │   ├── face-detection-demo/ # Face detection demo
│   │   │   └── ...
│   │   └── services/         # Camera and utility services
│   ├── assets/               # Images and static files
│   ├── environments/         # Environment configurations
│   └── ...
├── android/                  # Android native project
├── ios/                      # iOS native project
├── capacitor.config.ts       # Capacitor configuration
└── package.json              # Dependencies and scripts
```

## Camera Permissions

The app will automatically request camera permissions on first launch. Ensure the following permissions are configured:

### iOS (Info.plist)
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to demonstrate camera preview features</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for video recording</string>
```

### Android (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

## Face Detection Requirements

Face detection features require:
- **iOS:** iOS 13.0 or higher (uses Vision framework)
- **Android:** Google Play Services with ML Kit Face Detection

The plugin will gracefully handle devices without face detection support.

## Testing Face Detection

1. Navigate to the **Camera** tab
2. Scroll to the **"Face Detection 🎭"** card
3. Enable face detection with the checkbox
4. Select performance mode (fast/accurate)
5. Configure options:
   - Enable facial landmarks detection
   - Enable face tracking
   - Adjust maximum faces to detect
6. Click **"Test Face Detection"** to verify functionality

Or use the dedicated **Face Detection Demo** page for a full-screen experience.

## Troubleshooting

### Camera not showing
- Ensure camera permissions are granted
- Try switching between front/rear cameras
- Check device camera is not in use by another app

### Face detection not working
- Verify device meets minimum OS requirements
- Ensure good lighting conditions
- Try switching to "accurate" mode for better detection

### Build errors
- Clear node_modules and reinstall: `rm -rf node_modules && bun install`
- Clean Capacitor cache: `npx cap sync --clean`
- For iOS: `cd ios/App && pod install`

## Related Documentation

- [Plugin README](../README.md) - Main plugin documentation
- [Face Detection Guide](../FACE_DETECTION_GUIDE.md) - Comprehensive face detection guide
- [Face Detection Implementation](./FACE_DETECTION_IMPLEMENTATION.md) - App-specific implementation details
- [Capacitor Documentation](https://capacitorjs.com/docs)
- [Ionic Framework Documentation](https://ionicframework.com/docs)

## Contributing

This example app is part of the [@capgo/camera-preview](https://github.com/Cap-go/capacitor-camera-preview) plugin. Contributions are welcome!

## License

MIT License - See [LICENSE](../LICENSE) file for details.

## Support

- 📖 [Documentation](https://github.com/Cap-go/capacitor-camera-preview)
- 🐛 [Issue Tracker](https://github.com/Cap-go/capacitor-camera-preview/issues)
- 💬 [Discussions](https://github.com/Cap-go/capacitor-camera-preview/discussions)
- 🌐 [Capgo Platform](https://capgo.app/)
