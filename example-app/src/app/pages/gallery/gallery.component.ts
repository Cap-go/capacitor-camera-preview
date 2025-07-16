import { Component, inject } from '@angular/core';
import {
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar,
} from '@ionic/angular/standalone';
import { GalleryService } from '../../services/gallery.service';

@Component({
  selector: 'app-gallery',
  templateUrl: './gallery.component.html',
  imports: [IonHeader, IonToolbar, IonTitle, IonContent],
})
export class GalleryComponent {
  protected readonly galleryService = inject(GalleryService);
}
