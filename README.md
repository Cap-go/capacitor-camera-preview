# Capacitor Camera Preview Plugin

<a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin"> ➡️ Get Instant updates for your App with Capgo 🚀</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin"> Fix your annoying bug now, Hire a Capacitor expert 💪</a></h2>
</div>

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
* [`setZoom(...)`](#setzoom)
* [`getFlashMode()`](#getflashmode)
* [`removeAllListeners()`](#removealllisteners)
* [`setDeviceId(...)`](#setdeviceid)
* [`getDeviceId()`](#getdeviceid)
* [`getAvailableLenses()`](#getavailablelenses)
* [`getCurrentLens()`](#getcurrentlens)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### start(...)

```typescript
start(options: CameraPreviewOptions) => Promise<void>
```

Start the camera preview instance.

| Param         | Type                                                                  | Description                                  |
| ------------- | --------------------------------------------------------------------- | -------------------------------------------- |
| **`options`** | <code><a href="#camerapreviewoptions">CameraPreviewOptions</a></code> | the options to start the camera preview with |

**Since:** 0.0.1

--------------------


### stop()

```typescript
stop() => Promise<void>
```

Stop the camera preview instance.

**Since:** 0.0.1

--------------------


### capture(...)

```typescript
capture(options: CameraPreviewPictureOptions) => Promise<{ value: string; }>
```

Switch camera.

| Param         | Type                                                                                | Description                           |
| ------------- | ----------------------------------------------------------------------------------- | ------------------------------------- |
| **`options`** | <code><a href="#camerapreviewpictureoptions">CameraPreviewPictureOptions</a></code> | the options to switch the camera with |

**Returns:** <code>Promise&lt;{ value: string; }&gt;</code>

**Since:** 0.0.1

--------------------


### captureSample(...)

```typescript
captureSample(options: CameraSampleOptions) => Promise<{ value: string; }>
```

Capture a sample image.

| Param         | Type                                                                | Description                                  |
| ------------- | ------------------------------------------------------------------- | -------------------------------------------- |
| **`options`** | <code><a href="#camerasampleoptions">CameraSampleOptions</a></code> | the options to capture the sample image with |

**Returns:** <code>Promise&lt;{ value: string; }&gt;</code>

**Since:** 0.0.1

--------------------


### getSupportedFlashModes()

```typescript
getSupportedFlashModes() => Promise<{ result: CameraPreviewFlashMode[]; }>
```

Get supported flash modes.

**Returns:** <code>Promise&lt;{ result: CameraPreviewFlashMode[]; }&gt;</code>

**Since:** 0.0.1

--------------------


### getHorizontalFov()

```typescript
getHorizontalFov() => Promise<{ result: any; }>
```

Get horizontal field of view.

**Returns:** <code>Promise&lt;{ result: any; }&gt;</code>

**Since:** 0.0.1

--------------------


### getSupportedPictureSizes()

```typescript
getSupportedPictureSizes() => Promise<{ supportedPictureSizes: { facing: string; supportedPictureSizes: { width: number; height: number; }[]; }[]; }>
```

Gets the supported picture sizes for a given device.

**Returns:** <code>Promise&lt;{ supportedPictureSizes: { facing: string; supportedPictureSizes: { width: number; height: number; }[]; }[]; }&gt;</code>

--------------------


### setFlashMode(...)

```typescript
setFlashMode(options: { flashMode: CameraPreviewFlashMode | string; }) => Promise<void>
```

Set flash mode.

| Param         | Type                                | Description                            |
| ------------- | ----------------------------------- | -------------------------------------- |
| **`options`** | <code>{ flashMode: string; }</code> | the options to set the flash mode with |

**Since:** 0.0.1

--------------------


### flip()

```typescript
flip() => Promise<void>
```

Flip camera.

**Since:** 0.0.1

--------------------


### setOpacity(...)

```typescript
setOpacity(options: CameraOpacityOptions) => Promise<void>
```

Set opacity.

| Param         | Type                                                                  | Description                                |
| ------------- | --------------------------------------------------------------------- | ------------------------------------------ |
| **`options`** | <code><a href="#cameraopacityoptions">CameraOpacityOptions</a></code> | the options to set the camera opacity with |

**Since:** 0.0.1

--------------------


### stopRecordVideo()

```typescript
stopRecordVideo() => Promise<{ videoFilePath: string; }>
```

Stop recording video.

**Returns:** <code>Promise&lt;{ videoFilePath: string; }&gt;</code>

**Since:** 0.0.1

--------------------


### startRecordVideo(...)

```typescript
startRecordVideo(options: CameraPreviewOptions) => Promise<void>
```

Start recording video.

| Param         | Type                                                                  | Description                               |
| ------------- | --------------------------------------------------------------------- | ----------------------------------------- |
| **`options`** | <code><a href="#camerapreviewoptions">CameraPreviewOptions</a></code> | the options to start recording video with |

**Since:** 0.0.1

--------------------


### isRunning()

```typescript
isRunning() => Promise<{ isRunning: boolean; }>
```

Check if camera preview is running.

**Returns:** <code>Promise&lt;{ isRunning: boolean; }&gt;</code>

**Since:** 7.4.0

--------------------


### getAvailableDevices()

```typescript
getAvailableDevices() => Promise<{ devices: CameraDevice[]; }>
```

Get available camera devices.

**Returns:** <code>Promise&lt;{ devices: CameraDevice[]; }&gt;</code>

**Since:** 7.4.0

--------------------


### getZoom()

```typescript
getZoom() => Promise<{ min: number; max: number; current: number; }>
```

Get zoom capabilities and current level.

**Returns:** <code>Promise&lt;{ min: number; max: number; current: number; }&gt;</code>

**Since:** 7.4.0

--------------------


### setZoom(...)

```typescript
setZoom(options: { level: number; ramp?: boolean; }) => Promise<void>
```

Set zoom level.

| Param         | Type                                            | Description                  |
| ------------- | ----------------------------------------------- | ---------------------------- |
| **`options`** | <code>{ level: number; ramp?: boolean; }</code> | the options to set zoom with |

**Since:** 7.4.0

--------------------


### getFlashMode()

```typescript
getFlashMode() => Promise<{ flashMode: FlashMode; }>
```

Get current flash mode.

**Returns:** <code>Promise&lt;{ flashMode: <a href="#camerapreviewflashmode">CameraPreviewFlashMode</a>; }&gt;</code>

**Since:** 7.4.0

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Remove all listeners for this plugin.

**Since:** 7.4.0

--------------------


### setDeviceId(...)

```typescript
setDeviceId(options: { deviceId: string; }) => Promise<void>
```

Swap the deviceId.

| Param         | Type                               | Description                           |
| ------------- | ---------------------------------- | ------------------------------------- |
| **`options`** | <code>{ deviceId: string; }</code> | the options to swap the deviceId with |

**Since:** 7.4.0

--------------------


### getDeviceId()

```typescript
getDeviceId() => Promise<{ deviceId: string; }>
```

Get the current deviceId.

**Returns:** <code>Promise&lt;{ deviceId: string; }&gt;</code>

**Since:** 7.4.0

--------------------


### getAvailableLenses()

```typescript
getAvailableLenses() => Promise<{ lenses: CameraLens[]; }>
```

Get available camera lenses for the current camera position.

**Returns:** <code>Promise&lt;{ lenses: CameraLens[]; }&gt;</code>

**Since:** 7.5.0

--------------------


### getCurrentLens()

```typescript
getCurrentLens() => Promise<{ lens: CameraLens; }>
```

Get the currently active lens.

**Returns:** <code>Promise&lt;{ lens: <a href="#cameralens">CameraLens</a>; }&gt;</code>

**Since:** 7.5.0

--------------------


### Interfaces


#### CameraPreviewOptions

| Prop                               | Type                 | Description                                                                                                                                                   |
| ---------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`parent`**                       | <code>string</code>  | Parent element to attach the video preview element to (applicable to the web platform only)                                                                   |
| **`className`**                    | <code>string</code>  | Class name to add to the video preview element (applicable to the web platform only)                                                                          |
| **`width`**                        | <code>number</code>  | The preview width in pixels, default window.screen.width                                                                                                      |
| **`height`**                       | <code>number</code>  | The preview height in pixels, default window.screen.height                                                                                                    |
| **`x`**                            | <code>number</code>  | The x origin, default 0 (applicable to the android and ios platforms only)                                                                                    |
| **`y`**                            | <code>number</code>  | The y origin, default 0 (applicable to the android and ios platforms only)                                                                                    |
| **`includeSafeAreaInsets`**        | <code>boolean</code> | Whether to include safe area insets in y-position calculation, default false (applicable to the ios platform only)                                            |
| **`toBack`**                       | <code>boolean</code> | Brings your html in front of your preview, default false (applicable to the android only)                                                                     |
| **`paddingBottom`**                | <code>number</code>  | The preview bottom padding in pixes. Useful to keep the appropriate preview sizes when orientation changes (applicable to the android and ios platforms only) |
| **`rotateWhenOrientationChanged`** | <code>boolean</code> | Rotate preview when orientation changes (applicable to the ios platforms only; default value is true)                                                         |
| **`position`**                     | <code>string</code>  | Choose the camera to use 'front' or 'rear', default 'front'                                                                                                   |
| **`storeToFile`**                  | <code>boolean</code> | Defaults to false - Capture images to a file and return the file path instead of returning base64 encoded data                                                |
| **`disableExifHeaderStripping`**   | <code>boolean</code> | Defaults to false - Android Only - Disable automatic rotation of the image, and let the browser deal with it (keep reading on how to achieve it)              |
| **`enableHighResolution`**         | <code>boolean</code> | Defaults to false - iOS only - Activate high resolution image capture so that output images are from the highest resolution possible on the device *          |
| **`disableAudio`**                 | <code>boolean</code> | Defaults to false - Disables audio stream to prevent permission requests and output switching                                                                 |
| **`lockAndroidOrientation`**       | <code>boolean</code> | Android Only - Locks device orientation when camera is showing.                                                                                               |
| **`enableOpacity`**                | <code>boolean</code> | Defaults to false - Android and Web only. Set if camera preview can change opacity.                                                                           |
| **`enableZoom`**                   | <code>boolean</code> | Defaults to false - Android only. Set if camera preview will support pinch to zoom.                                                                           |
| **`cameraMode`**                   | <code>boolean</code> | default to false - IOS only. Set the CameraPreview to use the video mode preset                                                                               |
| **`deviceId`**                     | <code>string</code>  | Defaults to false - IOS only. Set the CameraPreview to start with the deviceId                                                                                |


#### CameraPreviewPictureOptions

| Prop          | Type                                                    | Description                                                                          |
| ------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **`height`**  | <code>number</code>                                     | The picture height, optional, default 0 (Device default)                             |
| **`width`**   | <code>number</code>                                     | The picture width, optional, default 0 (Device default)                              |
| **`quality`** | <code>number</code>                                     | The picture quality, 0 - 100, default 85                                             |
| **`format`**  | <code><a href="#pictureformat">PictureFormat</a></code> | The picture format, jpeg or png, default jpeg on `Web`. quality has no effect on png |


#### CameraSampleOptions

| Prop          | Type                | Description                              |
| ------------- | ------------------- | ---------------------------------------- |
| **`quality`** | <code>number</code> | The picture quality, 0 - 100, default 85 |


#### CameraOpacityOptions

| Prop          | Type                | Description                                           |
| ------------- | ------------------- | ----------------------------------------------------- |
| **`opacity`** | <code>number</code> | The percent opacity to set for camera view, default 1 |


#### CameraDevice

| Prop             | Type                                                          | Description                                                                  |
| ---------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| **`deviceId`**   | <code>string</code>                                           | Device identifier                                                            |
| **`label`**      | <code>string</code>                                           | Human readable device name                                                   |
| **`position`**   | <code><a href="#cameraposition">CameraPosition</a></code>     | Camera position                                                              |
| **`deviceType`** | <code><a href="#cameradevicetype">CameraDeviceType</a></code> | The type of the camera device (e.g., wide, ultra-wide, telephoto) - iOS only |


#### CameraLens

| Prop                | Type                                                          | Description                                      |
| ------------------- | ------------------------------------------------------------- | ------------------------------------------------ |
| **`id`**            | <code>string</code>                                           | Lens identifier (usually the physical camera ID) |
| **`label`**         | <code>string</code>                                           | Human readable lens name                         |
| **`position`**      | <code><a href="#cameraposition">CameraPosition</a></code>     | Camera position                                  |
| **`deviceType`**    | <code><a href="#cameradevicetype">CameraDeviceType</a></code> | The type of the camera lens                      |
| **`focalLength`**   | <code>number</code>                                           | Focal length in millimeters                      |
| **`minZoom`**       | <code>number</code>                                           | Minimum zoom factor for this lens                |
| **`maxZoom`**       | <code>number</code>                                           | Maximum zoom factor for this lens                |
| **`baseZoomRatio`** | <code>number</code>                                           | Base zoom ratio (e.g., 0.5x, 1x, 2x, 3x)         |
| **`isActive`**      | <code>boolean</code>                                          | Whether this lens is currently active            |


### Type Aliases


#### CameraPosition

<code>"rear" | "front"</code>


#### PictureFormat

<code>"jpeg" | "png"</code>


#### CameraPreviewFlashMode

<code>"off" | "on" | "auto" | "red-eye" | "torch"</code>


#### CameraDeviceType

Available camera device types for iOS.
Maps to AVCaptureDevice DeviceTypes in iOS.

<code>'wideAngle' | 'ultraWide' | 'telephoto' | 'dual' | 'dualWide' | 'triple' | 'trueDepth' | 'multi'</code>


#### FlashMode

<code><a href="#camerapreviewflashmode">CameraPreviewFlashMode</a></code>

</docgen-api>
