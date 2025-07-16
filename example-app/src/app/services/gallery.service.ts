import { Injectable, Signal, signal } from '@angular/core';

@Injectable({
  providedIn: 'root',
})
export class GalleryService {
  readonly #photos = signal<Array<string>>([]);
  public photos = this.#photos.asReadonly();

  public addPhoto(photo: string) {
    this.#photos.update((curr) => [...curr, `data:image/jpeg;base64,${photo}`]);
  }
}
