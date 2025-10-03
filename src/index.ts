import { registerPlugin } from '@capacitor/core';

import type { PhotoLibraryPlugin } from './definitions';

const PhotoLibrary = registerPlugin<PhotoLibraryPlugin>('PhotoLibrary', {
  web: () => import('./web').then((m) => new m.PhotoLibraryWeb()),
});

export * from './definitions';
export { PhotoLibrary };
