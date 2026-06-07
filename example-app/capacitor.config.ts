import type { CapacitorConfig } from '@capacitor/cli';
import pkg from './package.json';

const config: CapacitorConfig = {
  appId: 'app.capgo.camera.preview',
  appName: 'Camera Preview Example',
  webDir: 'www',
  android: {
    adjustMarginsForEdgeToEdge: 'auto',
  },
  plugins: {
    CapacitorUpdater: {
      appId: 'app.capgo.camera.preview',
      autoUpdate: true,
      autoSplashscreen: true,
      directUpdate: 'always',
      defaultChannel: 'production',
      version: pkg.version,
    },
  },
};

export default config;
