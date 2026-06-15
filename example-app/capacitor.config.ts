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
    SplashScreen: {
      launchAutoHide: false,
    },
    CapacitorUpdater: {
      appId: 'app.capgo.camera.preview',
      autoUpdate: true,
      autoSplashscreen: true,
      directUpdate: 'always',
      version: pkg.version,
    },
  },
};

export default config;
