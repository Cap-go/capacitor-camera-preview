import { CapacitorUpdater } from '@capgo/capacitor-updater';
import { Capacitor } from '@capacitor/core';
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
