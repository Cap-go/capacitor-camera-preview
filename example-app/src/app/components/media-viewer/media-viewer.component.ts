import { Component, inject, input, ElementRef, AfterViewInit, OnDestroy } from '@angular/core';
import { JsonPipe } from '@angular/common';
import { IonContent, IonHeader, IonToolbar, IonButtons, IonButton, IonIcon, GestureController } from '@ionic/angular/standalone';
import { ModalController } from '@ionic/angular/standalone';
import { MediaItem } from '../../services/gallery.service';
import { Gesture } from '@ionic/core';

@Component({
  selector: 'app-media-viewer',
  templateUrl: './media-viewer.component.html',
  styleUrls: ['./media-viewer.component.scss'],
  imports: [
    JsonPipe,
    IonContent,
    IonHeader,
    IonToolbar,
    IonButtons,
    IonButton,
    IonIcon,
  ],
  standalone: true,
})
export class MediaViewerComponent implements AfterViewInit, OnDestroy {
  public readonly item = input.required<MediaItem>();
  protected readonly modalCtrl = inject(ModalController);
  protected readonly gestureCtrl = inject(GestureController);
  protected readonly el = inject(ElementRef);
  #swipeGesture?: Gesture;

  ngAfterViewInit() {
    this.setupSwipeGesture();
    this.setupBackdropClick();
  }

  ngOnDestroy() {
    this.#swipeGesture?.destroy();
  }

  protected close() {
    this.modalCtrl.dismiss();
  }

  private setupSwipeGesture() {
    const content = this.el.nativeElement.querySelector('ion-content') as HTMLElement | null;
    if (!content) return;

    this.#swipeGesture = this.gestureCtrl.create({
      el: content,
      gestureName: 'swipe-down',
      direction: 'y',
      onStart: () => {
        content.style.transition = 'none';
      },
      onMove: (ev) => {
        if (ev.deltaY > 0) {
          content.style.transform = `translateY(${ev.deltaY}px)`;
          const opacity = 1 - (ev.deltaY / 500);
          content.style.opacity = Math.max(0.1, opacity).toString();
        }
      },
      onEnd: (ev) => {
        content.style.transition = '0.3s ease-out';
        if (ev.deltaY > 150) {
          // If swipe is long enough, close the modal
          content.style.transform = `translateY(100%)`;
          content.style.opacity = '0';
          this.close();
        } else {
          // Otherwise, snap back
          content.style.transform = '';
          content.style.opacity = '1';
        }
      }
    });

    this.#swipeGesture.enable();
  }

  private setupBackdropClick() {
    const container = this.el.nativeElement.querySelector('.media-container') as HTMLElement | null;
    if (!container) return;

    container.addEventListener('click', (event) => {
      // Only close if clicking the container background, not the media itself
      if (event.target === container) {
        this.close();
      }
    });
  }
}
