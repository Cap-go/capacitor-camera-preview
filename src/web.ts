import { WebPlugin } from "@capacitor/core";

import type {
  CameraDevice,
  CameraLens,
  CameraOpacityOptions,
  CameraPosition,
  CameraPreviewFlashMode,
  CameraPreviewOptions,
  CameraPreviewPictureOptions,
  CameraPreviewPlugin,
  CameraSampleOptions,
  FlashMode,
} from "./definitions";

export class CameraPreviewWeb extends WebPlugin implements CameraPreviewPlugin {
  /**
   *  track which camera is used based on start options
   *  used in capture
   */
  private isBackCamera = false;
  private currentDeviceId: string | null = null;

  constructor() {
    super();
  }

  async getSupportedPictureSizes(): Promise<any> {
    throw new Error(
      "getSupportedPictureSizes not supported under the web platform",
    );
  }

  async start(options: CameraPreviewOptions): Promise<void> {
    await navigator.mediaDevices
      .getUserMedia({
        audio: !options.disableAudio,
        video: true,
      })
      .then((stream: MediaStream) => {
        // Stop any existing stream so we can request media with different constraints based on user input
        stream.getTracks().forEach((track) => track.stop());
      })
      .catch((error) => {
        Promise.reject(error);
      });

    const video = document.getElementById("video");
    const parent = document.getElementById(options?.parent || "");

    if (!video) {
      const videoElement = document.createElement("video");
      videoElement.id = "video";
      videoElement.setAttribute("class", options?.className || "");

      // Don't flip video feed if camera is rear facing
      if (options.position !== "rear") {
        videoElement.setAttribute(
          "style",
          "-webkit-transform: scaleX(-1); transform: scaleX(-1);",
        );
      }

      const userAgent = navigator.userAgent.toLowerCase();
      const isSafari =
        userAgent.includes("safari") && !userAgent.includes("chrome");

      // Safari on iOS needs to have the autoplay, muted and playsinline attributes set for video.play() to be successful
      // Without these attributes videoElement.play() will throw a NotAllowedError
      // https://developer.apple.com/documentation/webkit/delivering_video_content_for_safari
      if (isSafari) {
        videoElement.setAttribute("autoplay", "true");
        videoElement.setAttribute("muted", "true");
        videoElement.setAttribute("playsinline", "true");
      }

      parent?.appendChild(videoElement);

      if (navigator?.mediaDevices?.getUserMedia) {
        const constraints: MediaStreamConstraints = {
          video: {
            width: { ideal: options.width },
            height: { ideal: options.height },
          },
        };

        if (options.deviceId) {
          (constraints.video as MediaTrackConstraints).deviceId = { exact: options.deviceId };
          this.currentDeviceId = options.deviceId;
          // Try to determine camera position from device
          const devices = await navigator.mediaDevices.enumerateDevices();
          const device = devices.find(d => d.deviceId === options.deviceId);
          this.isBackCamera = device?.label.toLowerCase().includes('back') || device?.label.toLowerCase().includes('rear') || false;
        } else if (options.position === "rear") {
          (constraints.video as MediaTrackConstraints).facingMode = "environment";
          this.isBackCamera = true;
        } else {
          this.isBackCamera = false;
        }

        const self = this;
        await navigator.mediaDevices.getUserMedia(constraints).then(
          (stream) => {
            if (document.getElementById("video")) {
              // video.src = window.URL.createObjectURL(stream);
              videoElement.srcObject = stream;
              videoElement.play();
              Promise.resolve({});
            } else {
              self.stopStream(stream);
              Promise.reject(new Error("camera already stopped"));
            }
          },
          (err) => {
            Promise.reject(new Error(err));
          },
        );
      }
    } else {
      Promise.reject(new Error("camera already started"));
    }
  }

  private stopStream(stream: any) {
    if (stream) {
      const tracks = stream.getTracks();

      for (const track of tracks) track.stop();
    }
  }

  async stop(): Promise<any> {
    const video = document.getElementById("video") as HTMLVideoElement;
    if (video) {
      video.pause();

      this.stopStream(video.srcObject);

      video.remove();
    }
  }

  async capture(options: CameraPreviewPictureOptions): Promise<any> {
    return new Promise((resolve, reject) => {
      const video = document.getElementById("video") as HTMLVideoElement;
      if (!video?.srcObject) {
        reject(new Error("camera is not running"));
        return;
      }

      // video.width = video.offsetWidth;

      let base64EncodedImage;

      if (video && video.videoWidth > 0 && video.videoHeight > 0) {
        const canvas = document.createElement("canvas");
        const context = canvas.getContext("2d");
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;

        // flip horizontally back camera isn't used
        if (!this.isBackCamera) {
          context?.translate(video.videoWidth, 0);
          context?.scale(-1, 1);
        }
        context?.drawImage(video, 0, 0, video.videoWidth, video.videoHeight);

        if ((options.format || "jpeg") === "jpeg") {
          base64EncodedImage = canvas
            .toDataURL("image/jpeg", (options.quality || 85) / 100.0)
            .replace("data:image/jpeg;base64,", "");
        } else {
          base64EncodedImage = canvas
            .toDataURL("image/png")
            .replace("data:image/png;base64,", "");
        }
      }

      resolve({
        value: base64EncodedImage,
      });
    });
  }

  async captureSample(_options: CameraSampleOptions): Promise<any> {
    return this.capture(_options);
  }

  async stopRecordVideo(): Promise<any> {
    throw new Error("stopRecordVideo not supported under the web platform");
  }

  async startRecordVideo(_options: CameraPreviewOptions): Promise<any> {
    console.log("startRecordVideo", _options);
    throw new Error("startRecordVideo not supported under the web platform");
  }

  async getSupportedFlashModes(): Promise<{
    result: CameraPreviewFlashMode[];
  }> {
    throw new Error(
      "getSupportedFlashModes not supported under the web platform",
    );
  }

  async getHorizontalFov(): Promise<{
    result: any;
  }> {
    throw new Error("getHorizontalFov not supported under the web platform");
  }

  async setFlashMode(_options: {
    flashMode: CameraPreviewFlashMode | string;
  }): Promise<void> {
    throw new Error(
      `setFlashMode not supported under the web platform${_options}`,
    );
  }

  async flip(): Promise<void> {
    const video = document.getElementById("video") as HTMLVideoElement;
    if (!video?.srcObject) {
      throw new Error("camera is not running");
    }

    // Stop current stream
    this.stopStream(video.srcObject);

    // Toggle camera position
    this.isBackCamera = !this.isBackCamera;

    // Get new constraints
    const constraints: MediaStreamConstraints = {
      video: {
        facingMode: this.isBackCamera ? "environment" : "user",
        width: { ideal: video.videoWidth || 640 },
        height: { ideal: video.videoHeight || 480 },
      },
    };

    try {
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      video.srcObject = stream;

      // Update current device ID from the new stream
      const videoTrack = stream.getVideoTracks()[0];
      if (videoTrack) {
        this.currentDeviceId = videoTrack.getSettings().deviceId || null;
      }

      // Update video transform based on camera
      if (this.isBackCamera) {
        video.style.transform = "none";
        video.style.webkitTransform = "none";
      } else {
        video.style.transform = "scaleX(-1)";
        video.style.webkitTransform = "scaleX(-1)";
      }

      await video.play();
    } catch (error) {
      throw new Error(`Failed to flip camera: ${error}`);
    }
  }

  async setOpacity(_options: CameraOpacityOptions): Promise<any> {
    const video = document.getElementById("video") as HTMLVideoElement;
    if (!!video && !!_options.opacity)
      video.style.setProperty("opacity", _options.opacity.toString());
  }

  async isRunning(): Promise<{ isRunning: boolean }> {
    const video = document.getElementById("video") as HTMLVideoElement;
    return { isRunning: !!video && !!video.srcObject };
  }

  async getAvailableDevices(): Promise<{ devices: CameraDevice[] }> {
    if (!navigator.mediaDevices?.enumerateDevices) {
      throw new Error("getAvailableDevices not supported under the web platform");
    }

    const devices = await navigator.mediaDevices.enumerateDevices();
    const videoDevices = devices
      .filter(device => device.kind === 'videoinput')
      .map((device, index) => {
        const label = device.label || `Camera ${index + 1}`;
        const labelLower = label.toLowerCase();

        // Determine position
        const position = (labelLower.includes('back') || labelLower.includes('rear')) ? 'rear' as CameraPosition : 'front' as CameraPosition;

        // Determine device type based on label
        let deviceType: 'wideAngle' | 'ultraWide' | 'telephoto' | 'trueDepth' = 'wideAngle';
        if (labelLower.includes('ultra') || labelLower.includes('0.5')) {
          deviceType = 'ultraWide';
        } else if (labelLower.includes('telephoto') || labelLower.includes('tele') || labelLower.includes('2x') || labelLower.includes('3x')) {
          deviceType = 'telephoto';
        } else if (labelLower.includes('depth') || labelLower.includes('truedepth')) {
          deviceType = 'trueDepth';
        } else if (labelLower.includes('wide')) {
          deviceType = 'wideAngle';
        }

        return {
          deviceId: device.deviceId,
          label,
          position,
          deviceType
        };
      });

    return { devices: videoDevices };
  }

  async getZoom(): Promise<{ min: number; max: number; current: number }> {
    const video = document.getElementById("video") as HTMLVideoElement;
    if (!video?.srcObject) {
      throw new Error("camera is not running");
    }

    const stream = video.srcObject as MediaStream;
    const videoTrack = stream.getVideoTracks()[0];

    if (!videoTrack) {
      throw new Error("no video track found");
    }

    const capabilities = videoTrack.getCapabilities() as any;
    const settings = videoTrack.getSettings() as any;

    if (!capabilities.zoom) {
      throw new Error("zoom not supported by this device");
    }

    return {
      min: capabilities.zoom.min || 1,
      max: capabilities.zoom.max || 1,
      current: settings.zoom || 1,
    };
  }

  async setZoom(options: { level: number; ramp?: boolean }): Promise<void> {
    const video = document.getElementById("video") as HTMLVideoElement;
    if (!video?.srcObject) {
      throw new Error("camera is not running");
    }

    const stream = video.srcObject as MediaStream;
    const videoTrack = stream.getVideoTracks()[0];

    if (!videoTrack) {
      throw new Error("no video track found");
    }

    const capabilities = videoTrack.getCapabilities() as any;

    if (!capabilities.zoom) {
      throw new Error("zoom not supported by this device");
    }

    const zoomLevel = Math.max(
      capabilities.zoom.min || 1,
      Math.min(capabilities.zoom.max || 1, options.level)
    );

    try {
      await videoTrack.applyConstraints({
        advanced: [{ zoom: zoomLevel } as any]
      });
    } catch (error) {
      throw new Error(`Failed to set zoom: ${error}`);
    }
  }

  async setZoomWithUltraWide(options: { level: number; ramp?: boolean }): Promise<void> {
    // For web, ultra-wide switching isn't available, so we clamp to regular zoom range
    const clampedLevel = Math.max(1.0, options.level);

    console.warn(`setZoomWithUltraWide: Requested level ${options.level} clamped to ${clampedLevel} (ultra-wide switching not available on web)`);

    await this.setZoom({ level: clampedLevel, ramp: options.ramp });
  }

  async getFlashMode(): Promise<{ flashMode: FlashMode }> {
    throw new Error("getFlashMode not supported under the web platform");
  }

  async getDeviceId(): Promise<{ deviceId: string }> {
    return { deviceId: this.currentDeviceId || "" };
  }

  async setDeviceId(options: { deviceId: string }): Promise<void> {
    const video = document.getElementById("video") as HTMLVideoElement;
    if (!video?.srcObject) {
      throw new Error("camera is not running");
    }

    // Stop current stream
    this.stopStream(video.srcObject);

    // Update current device ID
    this.currentDeviceId = options.deviceId;

    // Get new constraints with specific device ID
    const constraints: MediaStreamConstraints = {
      video: {
        deviceId: { exact: options.deviceId },
        width: { ideal: video.videoWidth || 640 },
        height: { ideal: video.videoHeight || 480 },
      },
    };

    try {
      // Try to determine camera position from device
      const devices = await navigator.mediaDevices.enumerateDevices();
      const device = devices.find(d => d.deviceId === options.deviceId);
      this.isBackCamera = device?.label.toLowerCase().includes('back') || device?.label.toLowerCase().includes('rear') || false;

      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      video.srcObject = stream;

      // Update video transform based on camera
      if (this.isBackCamera) {
        video.style.transform = "none";
        video.style.webkitTransform = "none";
      } else {
        video.style.transform = "scaleX(-1)";
        video.style.webkitTransform = "scaleX(-1)";
      }

      await video.play();
    } catch (error) {
      throw new Error(`Failed to swap to device ${options.deviceId}: ${error}`);
    }
  }

  async getAvailableLenses(): Promise<{ lenses: CameraLens[] }> {
    const devices = await this.getAvailableDevices();

    // For web, convert devices to lenses
    const lenses: CameraLens[] = devices.devices.map((device) => ({
      id: device.deviceId,
      label: device.label,
      position: device.position,
      deviceType: device.deviceType || 'wideAngle',
      focalLength: 4.25, // Approximate web camera focal length
      minZoom: 1.0,
      maxZoom: 1.0, // Web cameras typically don't support hardware zoom
      baseZoomRatio: device.deviceType === 'ultraWide' ? 0.5 :
                     device.deviceType === 'telephoto' ? 2.0 : 1.0,
      isActive: device.deviceId === this.currentDeviceId
    }));

    return { lenses };
  }

  async getCurrentLens(): Promise<{ lens: CameraLens }> {
    const lenses = await this.getAvailableLenses();
    const currentLens = lenses.lenses.find(lens => lens.isActive);

    if (!currentLens) {
      throw new Error("No current lens found");
    }

    return { lens: currentLens };
  }
}
