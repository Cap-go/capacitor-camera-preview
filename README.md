# Capacitor Camera Preview Plugin

<a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>


![NPM Version](https://img.shields.io/npm/v/%40capgo%2Fcamera-preview)
![NPM Downloads](https://img.shields.io/npm/dy/%40capgo%2Fcamera-preview)
![GitHub Repo stars](https://img.shields.io/github/stars/Cap-go/capacitor-camera-preview)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/Cap-go/capacitor-camera-preview/.github%2Fworkflows%2Fbuild.yml)
![GitHub License](https://img.shields.io/github/license/Cap-go/capacitor-camera-preview)
![Maintenance](https://img.shields.io/maintenance/yes/2025)

<p>
  Capacitor plugin that allows camera interaction from Javascript and HTML<br>(based on cordova-plugin-camera-preview).
</p>
<br>

This plugin is compatible Capacitor 7 and above.

Use v6 for Capacitor 6 and below.

**PR's are greatly appreciated.**

-- [@riderx](https://github.com/riderx), current maintainers

Remember to add the style below on your app's HTML or body element:

```css
:root {
  --ion-background-color: transparent !important;
}
```

Take into account that this will make transparent all ion-content on application, if you want to show camera preview only in one page, just add a custom class to your ion-content and make it transparent:

```css
.my-custom-camera-preview-content {
  --background: transparent;
}
```

If the camera preview is not displaying after applying the above styles, apply transparent background color to the root div element of the parent component
Ex: VueJS >> App.vue component
```html
<template>
  <ion-app id="app">
    <ion-router-outlet />
  </ion-app>
</template>

<style>
#app {
  background-color: transparent !important;
}
<style>
```

If it don't work in dark mode here is issue who explain how to fix it: https://github.com/capacitor-community/camera-preview/issues/199

<!-- # Features

<ul>
  <li>Start a camera preview from HTML code.</li>
  <li>Maintain HTML interactivity.</li>
  <li>Drag the preview box.</li>
  <li>Set camera color effect.</li>
  <li>Send the preview box to back of the HTML content.</li>
  <li>Set a custom position for the camera preview box.</li>
  <li>Set a custom size for the preview box.</li>
  <li>Set a custom alpha for the preview box.</li>
  <li>Set the focus mode, zoom, color effects, exposure mode, white balance mode and exposure compensation</li>
  <li>Tap to focus</li>
</ul> -->

## Good to know

Video and photo taken with the plugin are never removed, so do not forget to remove them after used to not bloat the user phone.

use https://capacitorjs.com/docs/apis/filesystem#deletefile for that


## Touch & Gestures (JS‑Driven)

- Native tap‑to‑focus and pinch‑to‑zoom gesture handling are intentionally disabled on both Android and iOS.
- Handle all user interactions in your HTML/JS layer, then call the plugin methods:
  - Focus: `await CameraPreview.setFocus({ x, y })` with normalized coordinates (0–1) relative to the preview bounds.
  - Zoom: `await CameraPreview.setZoom({ level })` using your own gesture/UI logic.
- Rationale: native gesture recognizers can conflict with your HTML touch handlers and block UI interactions. Keeping gestures in JS guarantees your UI receives touches as intended.
- The `enableZoom` start option is removed. Use JS gestures + `setZoom(...)`.
- Tip: When using `toBack: true`, the WebView is in front of the camera and receives touches; design your overlay UI there and drive focus/zoom through the JS API.

## Fast base64 from file path (no bridge)

When using `storeToFile: true`, you can avoid sending large base64 strings over the Capacitor bridge:

```ts
import { CameraPreview, getBase64FromFilePath } from '@capgo/camera-preview'

await CameraPreview.start({ storeToFile: true });
// Take a picture and get a file path
const { value: filePath } = await CameraPreview.capture({ quality: 85 })

// Convert the file to base64 entirely on the JS side (fast, no bridge)
const base64 = await getBase64FromFilePath(filePath)

// Optionally cleanup the temp file natively
await CameraPreview.deleteFile({ path: filePath })
```


## Exposure controls (iOS & Android)

This plugin exposes camera exposure controls on iOS and Android:

- Exposure modes: `"AUTO" | "LOCK" | "CONTINUOUS" | "CUSTOM"`
- Exposure compensation (EV bias): get range `{ min, max, step }`, read current value, and set new value

Platform notes:

- iOS: The camera starts in `CONTINUOUS` by default. Switching to `AUTO` or `CONTINUOUS` resets EV to 0. The `step` value is approximated to 0.1 since iOS does not expose the bias step.
- Android: AE lock/unlock and mode are handled via CameraX + Camera2 interop. The `step` value comes from CameraX `ExposureState` and may vary per device.

Example (TypeScript):

```ts
import { CameraPreview } from '@capgo/camera-preview';

// Query supported modes
const { modes } = await CameraPreview.getExposureModes();
console.log('Supported exposure modes:', modes);

// Get current mode
const { mode } = await CameraPreview.getExposureMode();
console.log('Current exposure mode:', mode);

// Set mode (AUTO | LOCK | CONTINUOUS | CUSTOM)
await CameraPreview.setExposureMode({ mode: 'CONTINUOUS' });

// Get EV range (with step)
const { min, max, step } = await CameraPreview.getExposureCompensationRange();
console.log('EV range:', { min, max, step });

// Read current EV
const { value: currentEV } = await CameraPreview.getExposureCompensation();
console.log('Current EV:', currentEV);

// Increment EV by one step and clamp to range
const nextEV = Math.max(min, Math.min(max, currentEV + step));
await CameraPreview.setExposureCompensation({ value: nextEV });
```

Example app (Ionic):

- Exposure mode toggle (sun icon) cycles through modes.
- EV controls (+/−) are placed in a top‑right floating action bar, outside the preview area.


# Installation

```
yarn add @capgo/camera-preview

or

npm install @capgo/camera-preview
```

Then run

```
npx cap sync
```

## Optional Configuration

To use certain features of this plugin, you will need to add the following permissions/keys to your native project configurations.

### Android

In your `android/app/src/main/AndroidManifest.xml`:

- **Audio Recording** (`disableAudio: false`):
  ```xml
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  ```

- **Saving to Gallery** (`saveToGallery: true`):
  ```xml
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
  ```

- **Location in EXIF Data** (`withExifLocation: true`):
  ```xml
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  ```

### iOS

In your `ios/App/App/Info.plist`, you must provide descriptions for the permissions your app requires. The keys are added automatically, but you need to provide the `string` values.

- **Audio Recording** (`disableAudio: false`):
  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>To record audio with videos</string>
  ```

- **Saving to Gallery** (`saveToGallery: true`):
  ```xml
  <key>NSPhotoLibraryUsageDescription</key>
  <string>To save photos to your gallery</string>
  ```

- **Location in EXIF Data** (`withExifLocation: true`):
  ```xml
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>To add location data to your photos</string>
  ```

## Extra Android installation steps

**Important** `camera-preview` 3+ requires Gradle 7.
Open `android/app/src/main/AndroidManifest.xml` and above the closing `</manifest>` tag add this line to request the CAMERA permission:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />

```

For more help consult the [Capacitor docs](https://capacitorjs.com/docs/android/configuration#configuring-androidmanifestxml).

## Extra iOS installation steps

You will need to add two permissions to `Info.plist`. Follow the [Capacitor docs](https://capacitorjs.com/docs/ios/configuration#configuring-infoplist) and add permissions with the raw keys `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`. `NSMicrophoneUsageDescription` is only required, if audio will be used. Otherwise set the `disableAudio` option to `true`, which also disables the microphone permission request.

## Extra Web installation steps

Add `import '@capgo/camera-preview'` to you entry script in ionic on `app.module.ts`, so capacitor can register the web platform from the plugin

### Exemple with Capacitor uploader:

Documentation for the [uploader](https://github.com/Cap-go/capacitor-uploader)

```typescript
  import { CameraPreview } from '@capgo/camera-preview'
  import { Uploader } from '@capgo/capacitor-uploader';


  async function record() {
    await CameraPreview.startRecordVideo({ storeToFile: true })
    await new Promise(resolve => setTimeout(resolve, 5000))
    const fileUrl = await CameraPreview.stopRecordVideo()
    console.log(fileUrl.videoFilePath)
    await uploadVideo(fileUrl.videoFilePath)
  }

  async function uploadVideo(filePath: string) {
    Uploader.addListener('events', (event) => {
      switch (event.name) {
        case 'uploading':
          console.log(`Upload progress: ${event.payload.percent}%`);
          break;
        case 'completed':
          console.log('Upload completed successfully');
          console.log('Server response status code:', event.payload.statusCode);
          break;
        case 'failed':
          console.error('Upload failed:', event.payload.error);
          break;
      }
    });
    try {
      const result = await Uploader.startUpload({
        filePath,
        serverUrl: 'S#_PRESIGNED_URL',
        method: 'PUT',
        headers: {
          'Content-Type': 'video/mp4',
        },
        mimeType: 'video/mp4',
      });
      console.log('Video uploaded successfully:', result.id);
    } catch (error) {
      console.error('Error uploading video:', error);
      throw error;
    }
  }
```

### API

<docgen-index>

* [`start(...)`](#start)
* [`stop()`](#stop)
* [`capture(...)`](#capture)
* [`captureSample(...)`](#capturesample)
* [`getSupportedFlashModes()`](#getsupportedflashmodes)
* [`setAspectRatio(...)`](#setaspectratio)
* [`getAspectRatio()`](#getaspectratio)
* [`setGridMode(...)`](#setgridmode)
* [`getGridMode()`](#getgridmode)
* [`checkPermissions(...)`](#checkpermissions)
* [`requestPermissions(...)`](#requestpermissions)
* [`getHorizontalFov()`](#gethorizontalfov)
* [`getSupportedPictureSizes()`](#getsupportedpicturesizes)
* [`setFlashMode(...)`](#setflashmode)
* [`flip()`](#flip)
* [`setOpacity(...)`](#setopacity)
* [`stopRecordVideo()`](#stoprecordvideo)
* [`startRecordVideo(...)`](#startrecordvideo)
* [`isRunning()`](#isrunning)
* [`getAvailableDevices()`](#getavailabledevices)
* [`getZoom()`](#getzoom)
* [`getZoomButtonValues()`](#getzoombuttonvalues)
* [`setZoom(...)`](#setzoom)
* [`getFlashMode()`](#getflashmode)
* [`removeAllListeners()`](#removealllisteners)
* [`setDeviceId(...)`](#setdeviceid)
* [`getDeviceId()`](#getdeviceid)
* [`getPreviewSize()`](#getpreviewsize)
* [`setPreviewSize(...)`](#setpreviewsize)
* [`setFocus(...)`](#setfocus)
* [`addListener('screenResize', ...)`](#addlistenerscreenresize-)
* [`addListener('orientationChange', ...)`](#addlistenerorientationchange-)
* [`deleteFile(...)`](#deletefile)
* [`getSafeAreaInsets()`](#getsafeareainsets)
* [`getOrientation()`](#getorientation)
* [`getExposureModes()`](#getexposuremodes)
* [`getExposureMode()`](#getexposuremode)
* [`setExposureMode(...)`](#setexposuremode)
* [`getExposureCompensationRange()`](#getexposurecompensationrange)
* [`getExposureCompensation()`](#getexposurecompensation)
* [`setExposureCompensation(...)`](#setexposurecompensation)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)
* [Enums](#enums)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

The main interface for the CameraPreview plugin.

### start(...)

```typescript
start(options: CameraPreviewOptions) => Promise<{ width: number; height: number; x: number; y: number; }>
```

Starts the camera preview.

| Param         | Type                                                                  | Description                                 |
| ------------- | --------------------------------------------------------------------- | ------------------------------------------- |
| **`options`** | <code><a href="#camerapreviewoptions">CameraPreviewOptions</a></code> | - The configuration for the camera preview. |

**Returns:** <code>Promise&lt;{ width: number; height: number; x: number; y: number; }&gt;</code>

**Since:** 0.0.1

--------------------


### stop()

```typescript
stop() => Promise<void>
```

Stops the camera preview.

**Since:** 0.0.1

--------------------


### capture(...)

```typescript
capture(options: CameraPreviewPictureOptions) => Promise<{ value: string; exif: ExifData; }>
```

Captures a picture from the camera.

If `storeToFile` was set to `true` when starting the preview, the returned
`value` will be an absolute file path on the device instead of a base64 string. Use getBase64FromFilePath to get the base64 string from the file path.

| Param         | Type                                                                                | Description                              |
| ------------- | ----------------------------------------------------------------------------------- | ---------------------------------------- |
| **`options`** | <code><a href="#camerapreviewpictureoptions">CameraPreviewPictureOptions</a></code> | - The options for capturing the picture. |

**Returns:** <code>Promise&lt;{ value: string; exif: <a href="#exifdata">ExifData</a>; }&gt;</code>

**Since:** 0.0.1

--------------------


### captureSample(...)

```typescript
captureSample(options: CameraSampleOptions) => Promise<{ value: string; }>
```

Captures a single frame from the camera preview stream.

| Param         | Type                                                                | Description                             |
| ------------- | ------------------------------------------------------------------- | --------------------------------------- |
| **`options`** | <code><a href="#camerasampleoptions">CameraSampleOptions</a></code> | - The options for capturing the sample. |

**Returns:** <code>Promise&lt;{ value: string; }&gt;</code>

**Since:** 0.0.1

--------------------


### getSupportedFlashModes()

```typescript
getSupportedFlashModes() => Promise<{ result: CameraPreviewFlashMode[]; }>
```

Gets the flash modes supported by the active camera.

**Returns:** <code>Promise&lt;{ result: CameraPreviewFlashMode[]; }&gt;</code>

**Since:** 0.0.1

--------------------


### setAspectRatio(...)

```typescript
setAspectRatio(options: { aspectRatio: "4:3" | "16:9"; x?: number; y?: number; }) => Promise<{ width: number; height: number; x: number; y: number; }>
```

Set the aspect ratio of the camera preview.

| Param         | Type                                                                   | Description                                                                                                                                                                                                                                                                                                           |
| ------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`options`** | <code>{ aspectRatio: '4:3' \| '16:9'; x?: number; y?: number; }</code> | - The desired aspect ratio and optional position. - aspectRatio: The desired aspect ratio ('4:3' or '16:9') - x: Optional x coordinate for positioning. If not provided, view will be auto-centered horizontally. - y: Optional y coordinate for positioning. If not provided, view will be auto-centered vertically. |

**Returns:** <code>Promise&lt;{ width: number; height: number; x: number; y: number; }&gt;</code>

**Since:** 7.5.0

--------------------


### getAspectRatio()

```typescript
getAspectRatio() => Promise<{ aspectRatio: "4:3" | "16:9"; }>
```

Gets the current aspect ratio of the camera preview.

**Returns:** <code>Promise&lt;{ aspectRatio: '4:3' | '16:9'; }&gt;</code>

**Since:** 7.5.0

--------------------


### setGridMode(...)

```typescript
setGridMode(options: { gridMode: GridMode; }) => Promise<void>
```

Sets the grid mode of the camera preview overlay.

| Param         | Type                                                         | Description                                        |
| ------------- | ------------------------------------------------------------ | -------------------------------------------------- |
| **`options`** | <code>{ gridMode: <a href="#gridmode">GridMode</a>; }</code> | - The desired grid mode ('none', '3x3', or '4x4'). |

**Since:** 8.0.0

--------------------


### getGridMode()

```typescript
getGridMode() => Promise<{ gridMode: GridMode; }>
```

Gets the current grid mode of the camera preview overlay.

**Returns:** <code>Promise&lt;{ gridMode: <a href="#gridmode">GridMode</a>; }&gt;</code>

**Since:** 8.0.0

--------------------


### checkPermissions(...)

```typescript
checkPermissions(options?: Pick<PermissionRequestOptions, "disableAudio"> | undefined) => Promise<CameraPermissionStatus>
```

Checks the current camera (and optionally microphone) permission status without prompting the system dialog.

| Param         | Type                                                                                                                          | Description                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **`options`** | <code><a href="#pick">Pick</a>&lt;<a href="#permissionrequestoptions">PermissionRequestOptions</a>, 'disableAudio'&gt;</code> | Set `disableAudio` to `false` to also include microphone status (defaults to `true`). |

**Returns:** <code>Promise&lt;<a href="#camerapermissionstatus">CameraPermissionStatus</a>&gt;</code>

**Since:** 8.7.0

--------------------


### requestPermissions(...)

```typescript
requestPermissions(options?: PermissionRequestOptions | undefined) => Promise<CameraPermissionStatus>
```

Requests camera (and optional microphone) permissions. If permissions are already granted or denied,
the current status is returned without prompting. When `showSettingsAlert` is true and permissions are denied,
a platform specific alert guiding the user to the app settings will be presented.

| Param         | Type                                                                          | Description                                           |
| ------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------- |
| **`options`** | <code><a href="#permissionrequestoptions">PermissionRequestOptions</a></code> | - Configuration for the permission request behaviour. |

**Returns:** <code>Promise&lt;<a href="#camerapermissionstatus">CameraPermissionStatus</a>&gt;</code>

**Since:** 8.7.0

--------------------


### getHorizontalFov()

```typescript
getHorizontalFov() => Promise<{ result: number; }>
```

Gets the horizontal field of view (FoV) for the active camera.
Note: This can be an estimate on some devices.

**Returns:** <code>Promise&lt;{ result: number; }&gt;</code>

**Since:** 0.0.1

--------------------


### getSupportedPictureSizes()

```typescript
getSupportedPictureSizes() => Promise<{ supportedPictureSizes: SupportedPictureSizes[]; }>
```

Gets the supported picture sizes for all cameras.

**Returns:** <code>Promise&lt;{ supportedPictureSizes: SupportedPictureSizes[]; }&gt;</code>

**Since:** 7.4.0

--------------------


### setFlashMode(...)

```typescript
setFlashMode(options: { flashMode: CameraPreviewFlashMode | string; }) => Promise<void>
```

Sets the flash mode for the active camera.

| Param         | Type                                | Description               |
| ------------- | ----------------------------------- | ------------------------- |
| **`options`** | <code>{ flashMode: string; }</code> | - The desired flash mode. |

**Since:** 0.0.1

--------------------


### flip()

```typescript
flip() => Promise<void>
```

Toggles between the front and rear cameras.

**Since:** 0.0.1

--------------------


### setOpacity(...)

```typescript
setOpacity(options: CameraOpacityOptions) => Promise<void>
```

Sets the opacity of the camera preview.

| Param         | Type                                                                  | Description            |
| ------------- | --------------------------------------------------------------------- | ---------------------- |
| **`options`** | <code><a href="#cameraopacityoptions">CameraOpacityOptions</a></code> | - The opacity options. |

**Since:** 0.0.1

--------------------


### stopRecordVideo()

```typescript
stopRecordVideo() => Promise<{ videoFilePath: string; }>
```

Stops an ongoing video recording.

**Returns:** <code>Promise&lt;{ videoFilePath: string; }&gt;</code>

**Since:** 0.0.1

--------------------


### startRecordVideo(...)

```typescript
startRecordVideo(options: CameraPreviewOptions) => Promise<void>
```

Starts recording a video.

| Param         | Type                                                                  | Description                                  |
| ------------- | --------------------------------------------------------------------- | -------------------------------------------- |
| **`options`** | <code><a href="#camerapreviewoptions">CameraPreviewOptions</a></code> | - The options for video recording. Only iOS. |

**Since:** 0.0.1

--------------------


### isRunning()

```typescript
isRunning() => Promise<{ isRunning: boolean; }>
```

Checks if the camera preview is currently running.

**Returns:** <code>Promise&lt;{ isRunning: boolean; }&gt;</code>

**Since:** 7.5.0

--------------------


### getAvailableDevices()

```typescript
getAvailableDevices() => Promise<{ devices: CameraDevice[]; }>
```

Gets all available camera devices.

**Returns:** <code>Promise&lt;{ devices: CameraDevice[]; }&gt;</code>

**Since:** 7.5.0

--------------------


### getZoom()

```typescript
getZoom() => Promise<{ min: number; max: number; current: number; lens: LensInfo; }>
```

Gets the current zoom state, including min/max and current lens info.

**Returns:** <code>Promise&lt;{ min: number; max: number; current: number; lens: <a href="#lensinfo">LensInfo</a>; }&gt;</code>

**Since:** 7.5.0

--------------------


### getZoomButtonValues()

```typescript
getZoomButtonValues() => Promise<{ values: number[]; }>
```

Returns zoom button values for quick switching.
- iOS/Android: includes 0.5 if ultra-wide available; 1 and 2 if wide available; 3 if telephoto available
- Web: unsupported

**Returns:** <code>Promise&lt;{ values: number[]; }&gt;</code>

**Since:** 7.5.0

--------------------


### setZoom(...)

```typescript
setZoom(options: { level: number; ramp?: boolean; autoFocus?: boolean; }) => Promise<void>
```

Sets the zoom level of the camera.

| Param         | Type                                                                 | Description                                                                         |
| ------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| **`options`** | <code>{ level: number; ramp?: boolean; autoFocus?: boolean; }</code> | - The desired zoom level. `ramp` is currently unused. `autoFocus` defaults to true. |

**Since:** 7.5.0

--------------------


### getFlashMode()

```typescript
getFlashMode() => Promise<{ flashMode: FlashMode; }>
```

Gets the current flash mode.

**Returns:** <code>Promise&lt;{ flashMode: <a href="#camerapreviewflashmode">CameraPreviewFlashMode</a>; }&gt;</code>

**Since:** 7.5.0

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Removes all registered listeners.

**Since:** 7.5.0

--------------------


### setDeviceId(...)

```typescript
setDeviceId(options: { deviceId: string; }) => Promise<void>
```

Switches the active camera to the one with the specified `deviceId`.

| Param         | Type                               | Description                          |
| ------------- | ---------------------------------- | ------------------------------------ |
| **`options`** | <code>{ deviceId: string; }</code> | - The ID of the device to switch to. |

**Since:** 7.5.0

--------------------


### getDeviceId()

```typescript
getDeviceId() => Promise<{ deviceId: string; }>
```

Gets the ID of the currently active camera device.

**Returns:** <code>Promise&lt;{ deviceId: string; }&gt;</code>

**Since:** 7.5.0

--------------------


### getPreviewSize()

```typescript
getPreviewSize() => Promise<{ x: number; y: number; width: number; height: number; }>
```

Gets the current preview size and position.

**Returns:** <code>Promise&lt;{ x: number; y: number; width: number; height: number; }&gt;</code>

**Since:** 7.5.0

--------------------


### setPreviewSize(...)

```typescript
setPreviewSize(options: { x?: number; y?: number; width: number; height: number; }) => Promise<{ width: number; height: number; x: number; y: number; }>
```

Sets the preview size and position.

| Param         | Type                                                                    | Description                      |
| ------------- | ----------------------------------------------------------------------- | -------------------------------- |
| **`options`** | <code>{ x?: number; y?: number; width: number; height: number; }</code> | The new position and dimensions. |

**Returns:** <code>Promise&lt;{ width: number; height: number; x: number; y: number; }&gt;</code>

**Since:** 7.5.0

--------------------


### setFocus(...)

```typescript
setFocus(options: { x: number; y: number; }) => Promise<void>
```

Sets the camera focus to a specific point in the preview.

Note: The plugin does not attach any native tap-to-focus gesture handlers. Handle taps in
your HTML/JS (e.g., on the overlaying UI), then pass normalized coordinates here.

| Param         | Type                                   | Description          |
| ------------- | -------------------------------------- | -------------------- |
| **`options`** | <code>{ x: number; y: number; }</code> | - The focus options. |

**Since:** 7.5.0

--------------------


### addListener('screenResize', ...)

```typescript
addListener(eventName: "screenResize", listenerFunc: (data: { width: number; height: number; x: number; y: number; }) => void) => Promise<PluginListenerHandle>
```

Adds a listener for screen resize events.

| Param              | Type                                                                                     | Description                                         |
| ------------------ | ---------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **`eventName`**    | <code>'screenResize'</code>                                                              | - The event name to listen for.                     |
| **`listenerFunc`** | <code>(data: { width: number; height: number; x: number; y: number; }) =&gt; void</code> | - The function to call when the event is triggered. |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

**Since:** 7.5.0

--------------------


### addListener('orientationChange', ...)

```typescript
addListener(eventName: "orientationChange", listenerFunc: (data: { orientation: DeviceOrientation; }) => void) => Promise<PluginListenerHandle>
```

Adds a listener for orientation change events.

| Param              | Type                                                                                                 | Description                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **`eventName`**    | <code>'orientationChange'</code>                                                                     | - The event name to listen for.                     |
| **`listenerFunc`** | <code>(data: { orientation: <a href="#deviceorientation">DeviceOrientation</a>; }) =&gt; void</code> | - The function to call when the event is triggered. |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

**Since:** 7.5.0

--------------------


### deleteFile(...)

```typescript
deleteFile(options: { path: string; }) => Promise<{ success: boolean; }>
```

Deletes a file at the given absolute path on the device.
Use this to quickly clean up temporary images created with `storeToFile`.
On web, this is not supported and will throw.

| Param         | Type                           |
| ------------- | ------------------------------ |
| **`options`** | <code>{ path: string; }</code> |

**Returns:** <code>Promise&lt;{ success: boolean; }&gt;</code>

**Since:** 7.5.0

--------------------


### getSafeAreaInsets()

```typescript
getSafeAreaInsets() => Promise<SafeAreaInsets>
```

Gets the safe area insets for devices.
Returns the orientation-aware notch/camera cutout inset and the current orientation.
In portrait mode: returns top inset (notch at top).
In landscape mode: returns left inset (notch moved to side).
This specifically targets the cutout area (notch, punch hole, etc.) that all modern phones have.

Android: Values returned in dp (logical pixels).
iOS: Values returned in physical pixels, excluding status bar (only pure notch/cutout size).

**Returns:** <code>Promise&lt;<a href="#safeareainsets">SafeAreaInsets</a>&gt;</code>

--------------------


### getOrientation()

```typescript
getOrientation() => Promise<{ orientation: DeviceOrientation; }>
```

Gets the current device orientation in a cross-platform format.

**Returns:** <code>Promise&lt;{ orientation: <a href="#deviceorientation">DeviceOrientation</a>; }&gt;</code>

**Since:** 7.5.0

--------------------


### getExposureModes()

```typescript
getExposureModes() => Promise<{ modes: ExposureMode[]; }>
```

Returns the exposure modes supported by the active camera.
Modes can include: 'locked', 'auto', 'continuous', 'custom'.

**Returns:** <code>Promise&lt;{ modes: ExposureMode[]; }&gt;</code>

--------------------


### getExposureMode()

```typescript
getExposureMode() => Promise<{ mode: ExposureMode; }>
```

Returns the current exposure mode.

**Returns:** <code>Promise&lt;{ mode: <a href="#exposuremode">ExposureMode</a>; }&gt;</code>

--------------------


### setExposureMode(...)

```typescript
setExposureMode(options: { mode: ExposureMode; }) => Promise<void>
```

Sets the exposure mode.

| Param         | Type                                                             |
| ------------- | ---------------------------------------------------------------- |
| **`options`** | <code>{ mode: <a href="#exposuremode">ExposureMode</a>; }</code> |

--------------------


### getExposureCompensationRange()

```typescript
getExposureCompensationRange() => Promise<{ min: number; max: number; step: number; }>
```

Returns the exposure compensation (EV bias) supported range.

**Returns:** <code>Promise&lt;{ min: number; max: number; step: number; }&gt;</code>

--------------------


### getExposureCompensation()

```typescript
getExposureCompensation() => Promise<{ value: number; }>
```

Returns the current exposure compensation (EV bias).

**Returns:** <code>Promise&lt;{ value: number; }&gt;</code>

--------------------


### setExposureCompensation(...)

```typescript
setExposureCompensation(options: { value: number; }) => Promise<void>
```

Sets the exposure compensation (EV bias). Value will be clamped to range.

| Param         | Type                            |
| ------------- | ------------------------------- |
| **`options`** | <code>{ value: number; }</code> |

--------------------


### Interfaces


#### CameraPreviewOptions

Defines the configuration options for starting the camera preview.

| Prop                               | Type                                                            | Description                                                                                                                                                                                             | Default               | Since  |
| ---------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- | ------ |
| **`parent`**                       | <code>string</code>                                             | The parent element to attach the video preview to.                                                                                                                                                      |                       |        |
| **`className`**                    | <code>string</code>                                             | A CSS class name to add to the preview element.                                                                                                                                                         |                       |        |
| **`width`**                        | <code>number</code>                                             | The width of the preview in pixels. Defaults to the screen width.                                                                                                                                       |                       |        |
| **`height`**                       | <code>number</code>                                             | The height of the preview in pixels. Defaults to the screen height.                                                                                                                                     |                       |        |
| **`x`**                            | <code>number</code>                                             | The horizontal origin of the preview, in pixels.                                                                                                                                                        |                       |        |
| **`y`**                            | <code>number</code>                                             | The vertical origin of the preview, in pixels.                                                                                                                                                          |                       |        |
| **`aspectRatio`**                  | <code>'4:3' \| '16:9'</code>                                    | The aspect ratio of the camera preview, '4:3' or '16:9' or 'fill'. Cannot be set if width or height is provided, otherwise the call will be rejected. Use setPreviewSize to adjust size after starting. |                       | 2.0.0  |
| **`gridMode`**                     | <code><a href="#gridmode">GridMode</a></code>                   | The grid overlay to display on the camera preview.                                                                                                                                                      | <code>"none"</code>   | 2.1.0  |
| **`includeSafeAreaInsets`**        | <code>boolean</code>                                            | Adjusts the y-position to account for safe areas (e.g., notches).                                                                                                                                       | <code>false</code>    |        |
| **`toBack`**                       | <code>boolean</code>                                            | If true, places the preview behind the webview.                                                                                                                                                         | <code>true</code>     |        |
| **`paddingBottom`**                | <code>number</code>                                             | Bottom padding for the preview, in pixels.                                                                                                                                                              |                       |        |
| **`rotateWhenOrientationChanged`** | <code>boolean</code>                                            | Whether to rotate the preview when the device orientation changes.                                                                                                                                      | <code>true</code>     |        |
| **`position`**                     | <code>string</code>                                             | The camera to use.                                                                                                                                                                                      | <code>"rear"</code>   |        |
| **`storeToFile`**                  | <code>boolean</code>                                            | If true, saves the captured image to a file and returns the file path. If false, returns a base64 encoded string.                                                                                       | <code>false</code>    |        |
| **`disableExifHeaderStripping`**   | <code>boolean</code>                                            | If true, prevents the plugin from rotating the image based on EXIF data.                                                                                                                                | <code>false</code>    |        |
| **`disableAudio`**                 | <code>boolean</code>                                            | If true, disables the audio stream, preventing audio permission requests.                                                                                                                               | <code>true</code>     |        |
| **`lockAndroidOrientation`**       | <code>boolean</code>                                            | If true, locks the device orientation while the camera is active.                                                                                                                                       | <code>false</code>    |        |
| **`enableOpacity`**                | <code>boolean</code>                                            | If true, allows the camera preview's opacity to be changed.                                                                                                                                             | <code>false</code>    |        |
| **`disableFocusIndicator`**        | <code>boolean</code>                                            | If true, disables the visual focus indicator when tapping to focus.                                                                                                                                     | <code>false</code>    |        |
| **`deviceId`**                     | <code>string</code>                                             | The `deviceId` of the camera to use. If provided, `position` is ignored.                                                                                                                                |                       |        |
| **`initialZoomLevel`**             | <code>number</code>                                             | The initial zoom level when starting the camera preview. If the requested zoom level is not available, the native plugin will reject.                                                                   | <code>1.0</code>      | 2.2.0  |
| **`positioning`**                  | <code><a href="#camerapositioning">CameraPositioning</a></code> | The vertical positioning of the camera preview.                                                                                                                                                         | <code>"center"</code> | 2.3.0  |
| **`enableVideoMode`**              | <code>boolean</code>                                            | If true, enables video capture capabilities when the camera starts.                                                                                                                                     | <code>false</code>    | 7.11.0 |


#### ExifData

Represents EXIF data extracted from an image.


#### CameraPreviewPictureOptions

Defines the options for capturing a picture.

| Prop                             | Type                                                    | Description                                                                                                                                                                                                                                                                                                                                                                           | Default              | Since  |
| -------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- | ------ |
| **`height`**                     | <code>number</code>                                     | The maximum height of the picture in pixels. The image will be resized to fit within this height while maintaining aspect ratio. If not specified the captured image will match the preview's visible area.                                                                                                                                                                           |                      |        |
| **`width`**                      | <code>number</code>                                     | The maximum width of the picture in pixels. The image will be resized to fit within this width while maintaining aspect ratio. If not specified the captured image will match the preview's visible area.                                                                                                                                                                             |                      |        |
| **`quality`**                    | <code>number</code>                                     | The quality of the captured image, from 0 to 100. Does not apply to `png` format.                                                                                                                                                                                                                                                                                                     | <code>85</code>      |        |
| **`format`**                     | <code><a href="#pictureformat">PictureFormat</a></code> | The format of the captured image.                                                                                                                                                                                                                                                                                                                                                     | <code>"jpeg"</code>  |        |
| **`saveToGallery`**              | <code>boolean</code>                                    | If true, the captured image will be saved to the user's gallery.                                                                                                                                                                                                                                                                                                                      | <code>false</code>   | 7.5.0  |
| **`withExifLocation`**           | <code>boolean</code>                                    | If true, the plugin will attempt to add GPS location data to the image's EXIF metadata. This may prompt the user for location permissions.                                                                                                                                                                                                                                            | <code>false</code>   | 7.6.0  |
| **`embedTimestamp`**             | <code>boolean</code>                                    | If true, the plugin will embed a timestamp in the top-right corner of the image.                                                                                                                                                                                                                                                                                                      | <code>false</code>   | 7.17.0 |
| **`embedLocation`**              | <code>boolean</code>                                    | If true, the plugin will embed the current location in the top-right corner of the image. Requires `withExifLocation` to be enabled.                                                                                                                                                                                                                                                  | <code>false</code>   | 7.18.0 |
| **`photoQualityPrioritization`** | <code>'speed' \| 'balanced' \| 'quality'</code>         | Sets the priority for photo quality vs. capture speed. - "speed": Prioritizes faster capture times, may reduce image quality. - "balanced": Aims for a balance between quality and speed. - "quality": Prioritizes image quality, may reduce capture speed. See https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/photoqualityprioritization for details. | <code>"speed"</code> | 7.21.0 |


#### CameraSampleOptions

Defines the options for capturing a sample frame from the camera preview.

| Prop          | Type                | Description                                        | Default         |
| ------------- | ------------------- | -------------------------------------------------- | --------------- |
| **`quality`** | <code>number</code> | The quality of the captured sample, from 0 to 100. | <code>85</code> |


#### CameraPermissionStatus

| Prop             | Type                                                        | Description                                                            |
| ---------------- | ----------------------------------------------------------- | ---------------------------------------------------------------------- |
| **`camera`**     | <code><a href="#permissionstate">PermissionState</a></code> | Current camera permission status.                                      |
| **`microphone`** | <code><a href="#permissionstate">PermissionState</a></code> | Optional - microphone permission status when audio capture is requested. |


#### PermissionRequestOptions

| Prop                          | Type                 |
| ----------------------------- | -------------------- |
| **`disableAudio`**            | <code>boolean</code> |
| **`showSettingsAlert`**       | <code>boolean</code> |
| **`title`**                   | <code>string</code>  |
| **`message`**                 | <code>string</code>  |
| **`openSettingsButtonTitle`** | <code>string</code>  |
| **`cancelButtonTitle`**       | <code>string</code>  |


#### SupportedPictureSizes

Represents the supported picture sizes for a camera facing a certain direction.

| Prop                        | Type                       | Description                                        |
| --------------------------- | -------------------------- | -------------------------------------------------- |
| **`facing`**                | <code>string</code>        | The camera direction ("front" or "rear").          |
| **`supportedPictureSizes`** | <code>PictureSize[]</code> | A list of supported picture sizes for this camera. |


#### PictureSize

Defines a standard picture size with width and height.

| Prop         | Type                | Description                          |
| ------------ | ------------------- | ------------------------------------ |
| **`width`**  | <code>number</code> | The width of the picture in pixels.  |
| **`height`** | <code>number</code> | The height of the picture in pixels. |


#### CameraOpacityOptions

Defines the options for setting the camera preview's opacity.

| Prop          | Type                | Description                                                                 | Default          |
| ------------- | ------------------- | --------------------------------------------------------------------------- | ---------------- |
| **`opacity`** | <code>number</code> | The opacity percentage, from 0.0 (fully transparent) to 1.0 (fully opaque). | <code>1.0</code> |


#### CameraDevice

Represents a physical camera on the device (e.g., the front-facing camera).

| Prop            | Type                                                      | Description                                                                               |
| --------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **`deviceId`**  | <code>string</code>                                       | A unique identifier for the camera device.                                                |
| **`label`**     | <code>string</code>                                       | A human-readable name for the camera device.                                              |
| **`position`**  | <code><a href="#cameraposition">CameraPosition</a></code> | The physical position of the camera on the device.                                        |
| **`lenses`**    | <code>CameraLens[]</code>                                 | A list of all available lenses for this camera device.                                    |
| **`minZoom`**   | <code>number</code>                                       | The overall minimum zoom factor available across all lenses on this device.               |
| **`maxZoom`**   | <code>number</code>                                       | The overall maximum zoom factor available across all lenses on this device.               |
| **`isLogical`** | <code>boolean</code>                                      | Identifies whether the device is a logical camera (composed of multiple physical lenses). |


#### CameraLens

Represents a single camera lens on a device. A {@link <a href="#cameradevice">CameraDevice</a>} can have multiple lenses.

| Prop                | Type                                              | Description                                                                  |
| ------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------- |
| **`label`**         | <code>string</code>                               | A human-readable name for the lens, e.g., "Ultra-Wide".                      |
| **`deviceType`**    | <code><a href="#devicetype">DeviceType</a></code> | The type of the camera lens.                                                 |
| **`focalLength`**   | <code>number</code>                               | The focal length of the lens in millimeters.                                 |
| **`baseZoomRatio`** | <code>number</code>                               | The base zoom factor for this lens (e.g., 0.5 for ultra-wide, 1.0 for wide). |
| **`minZoom`**       | <code>number</code>                               | The minimum zoom factor supported by this specific lens.                     |
| **`maxZoom`**       | <code>number</code>                               | The maximum zoom factor supported by this specific lens.                     |


#### LensInfo

Represents the detailed information of the currently active lens.

| Prop                | Type                                              | Description                                                      |
| ------------------- | ------------------------------------------------- | ---------------------------------------------------------------- |
| **`focalLength`**   | <code>number</code>                               | The focal length of the active lens in millimeters.              |
| **`deviceType`**    | <code><a href="#devicetype">DeviceType</a></code> | The device type of the active lens.                              |
| **`baseZoomRatio`** | <code>number</code>                               | The base zoom ratio of the active lens (e.g., 0.5x, 1.0x).       |
| **`digitalZoom`**   | <code>number</code>                               | The current digital zoom factor applied on top of the base zoom. |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |


#### SafeAreaInsets

Represents safe area insets for devices.
Android: Values are expressed in logical pixels (dp) to match JS layout units.
iOS: Values are expressed in physical pixels and exclude status bar.

| Prop              | Type                | Description                                                                                                                                                                                                                                      |
| ----------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **`orientation`** | <code>number</code> | Current device orientation (1 = portrait, 2 = landscape, 0 = unknown).                                                                                                                                                                           |
| **`top`**         | <code>number</code> | Orientation-aware notch/camera cutout inset (excluding status bar). In portrait mode: returns top inset (notch at top). In landscape mode: returns left inset (notch at side). Android: Value in dp, iOS: Value in pixels (status bar excluded). |


### Type Aliases


#### GridMode

<code>"none" | "3x3" | "4x4"</code>


#### CameraPosition

<code>"rear" | "front"</code>


#### CameraPositioning

<code>"center" | "top" | "bottom"</code>


#### PictureFormat

<code>"jpeg" | "png"</code>


#### CameraPreviewFlashMode

The available flash modes for the camera.
'torch' is a continuous light mode.

<code>"off" | "on" | "auto" | "torch"</code>


#### PermissionState

<code>'prompt' | 'prompt-with-rationale' | 'granted' | 'denied'</code>


#### Pick

From T, pick a set of properties whose keys are in the union K

<code>{
 [P in K]: T[P];
 }</code>


#### FlashMode

<code><a href="#camerapreviewflashmode">CameraPreviewFlashMode</a></code>


#### DeviceOrientation

Canonical device orientation values across platforms.

<code>"portrait" | "landscape-left" | "landscape-right" | "portrait-upside-down" | "unknown"</code>


#### ExposureMode

Reusable exposure mode type for cross-platform support.

<code>"AUTO" | "LOCK" | "CONTINUOUS" | "CUSTOM"</code>


### Enums


#### DeviceType

| Members          | Value                    |
| ---------------- | ------------------------ |
| **`ULTRA_WIDE`** | <code>"ultraWide"</code> |
| **`WIDE_ANGLE`** | <code>"wideAngle"</code> |
| **`TELEPHOTO`**  | <code>"telephoto"</code> |
| **`TRUE_DEPTH`** | <code>"trueDepth"</code> |
| **`DUAL`**       | <code>"dual"</code>      |
| **`DUAL_WIDE`**  | <code>"dualWide"</code>  |
| **`TRIPLE`**     | <code>"triple"</code>    |

</docgen-api>
