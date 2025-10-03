import { WebPlugin } from '@capacitor/core';

import type { PhotoLibraryPlugin } from './definitions';

export class PhotoLibraryWeb extends WebPlugin implements PhotoLibraryPlugin {
  async echo(options: { value: string }): Promise<{ value: string }> {
    console.log('ECHO', options);
    return options;
  }
}
