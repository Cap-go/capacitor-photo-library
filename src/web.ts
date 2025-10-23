import { WebPlugin } from '@capacitor/core';

import type {
  GetLibraryOptions,
  GetLibraryResult,
  PhotoLibraryAlbum,
  PhotoLibraryAuthorizationState,
  PhotoLibraryFile,
  PickMediaOptions,
  PickMediaResult,
  PhotoLibraryPlugin,
} from './definitions';

export class PhotoLibraryWeb extends WebPlugin implements PhotoLibraryPlugin {
  async checkAuthorization(): Promise<{ state: PhotoLibraryAuthorizationState }> {
    throw this.unimplemented('checkAuthorization');
  }

  async requestAuthorization(): Promise<{ state: PhotoLibraryAuthorizationState }> {
    throw this.unimplemented('requestAuthorization');
  }

  async getAlbums(): Promise<{ albums: PhotoLibraryAlbum[] }> {
    throw this.unimplemented('getAlbums');
  }

  async getLibrary(_options?: GetLibraryOptions): Promise<GetLibraryResult> {
    throw this.unimplemented('getLibrary');
  }

  async getPhotoUrl(_options: { id: string }): Promise<PhotoLibraryFile> {
    throw this.unimplemented('getPhotoUrl');
  }

  async getThumbnailUrl(_options: {
    id: string;
    width?: number | undefined;
    height?: number | undefined;
    quality?: number | undefined;
  }): Promise<PhotoLibraryFile> {
    throw this.unimplemented('getThumbnailUrl');
  }

  async pickMedia(_options?: PickMediaOptions): Promise<PickMediaResult> {
    throw this.unimplemented('pickMedia');
  }

  async getPluginVersion(): Promise<{ version: string }> {
    return { version: 'web' };
  }
}
