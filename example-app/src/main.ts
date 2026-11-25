import { CapacitorUpdater } from '@capgo/capacitor-updater';
import { bootstrapApplication } from '@angular/platform-browser';
import {
  PreloadAllModules,
  RouteReuseStrategy,
  provideRouter,
  withPreloading,
} from '@angular/router';
import {
  IonicRouteStrategy,
  provideIonicAngular,
} from '@ionic/angular/standalone';

import { AppComponent } from './app/app.component';
import { routes } from './app/app.routes';
import { Capacitor } from '@capacitor/core';
import { enableSupportIonicOverlays } from '@webview-native-ui/engine/ionic';

if (Capacitor.isNativePlatform()) {
  enableSupportIonicOverlays();
}

bootstrapApplication(AppComponent, {
  providers: [
    { provide: RouteReuseStrategy, useClass: IonicRouteStrategy },
    provideIonicAngular({
      useSetInputAPI: true,
    }),
    provideRouter(routes, withPreloading(PreloadAllModules)),
  ],
})
  .then(() => {
    if (Capacitor.isNativePlatform()) {
      CapacitorUpdater.notifyAppReady().catch((error) => {
        console.error('Capgo notifyAppReady failed', error);
      });
    }
  })
  .catch((error) => {
    console.error('Angular bootstrap failed', error);
  });
