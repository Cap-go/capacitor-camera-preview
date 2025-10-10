import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'app.capgo.camera.preview',
  appName: 'Camera Preview Example',
  webDir: 'www',
  android: {
    adjustMarginsForEdgeToEdge: 'auto',
  },
};

export default config;
