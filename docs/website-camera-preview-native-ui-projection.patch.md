# Cap-go/website patch: camera-preview native UI projection

Target page: `docs/plugins/camera-preview/` (or equivalent MDX source).

## Section to add after preview placement / overlay guidance

### Native UI projection (optional)

`@capgo/camera-preview` can register the live preview with [`@webview-native-ui/engine`](https://github.com/webview-native-ui/engine/) when you pass `nativeUIProjection: true` in `start()`.

While a Web or Ionic overlay covers the preview region, the **live native stream freezes visually** and the engine draws a **snapshot** into the DOM element matched by `nativeUIProjectionSelector`. When the overlay dismisses, the interactive native preview resumes at the current size and position.

Default is `false` (no engine registration, same behavior as before).

```ts
import { enableSupportIonicOverlays } from '@webview-native-ui/engine/ionic';
import { CameraPreview } from '@capgo/camera-preview';

enableSupportIonicOverlays(); // once at startup for Ionic apps

await CameraPreview.start({
  toBack: true,
  nativeUIProjection: true,
  nativeUIProjectionSelector: '#camera-preview-projection',
});
```

**iOS CocoaPods:** add `pod 'WebViewNativeUIEngine', :path => '../../node_modules/@webview-native-ui/engine'` in the App target.

**Android:** Gradle resolves `io.github.webview-native-ui:engine:1.0.11` through the plugin; keep npm and native versions aligned at `1.0.11`.