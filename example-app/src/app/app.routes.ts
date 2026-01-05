import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () =>
      import('./components/tabs/tabs.component').then((m) => m.TabsComponent),
    children: [
      {
        path: 'camera',
        loadComponent: () =>
          import('./pages/camera-view/camera-view.page').then(
            (m) => m.CameraViewPage,
          ),
      },
      {
        path: 'face-detection',
        loadComponent: () =>
          import('./pages/face-detection/face-detection.page').then(
            (m) => m.FaceDetectionPage,
          ),
      },
      {
        path: 'gallery',
        loadComponent: () =>
          import('./pages/gallery/gallery.component').then(
            (m) => m.GalleryComponent,
          ),
      },
      {
        path: '',
        redirectTo: '/camera',
        pathMatch: 'full',
      },
    ],
  },
  {
    path: '**',
    redirectTo: '/camera',
  },
];
