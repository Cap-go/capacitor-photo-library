# @capgo/capacitor-photo-library
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin_photo_library"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin_photo_library"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>

Displays photo gallery as web page, or boring native screen which you cannot modify but require no authorization

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/photo-library/

## Compatibility

| Plugin version | Capacitor compatibility | Maintained |
| -------------- | ----------------------- | ---------- |
| v8.\*.\*       | v8.\*.\*                | ✅          |
| v7.\*.\*       | v7.\*.\*                | On demand   |
| v6.\*.\*       | v6.\*.\*                | ❌          |
| v5.\*.\*       | v5.\*.\*                | ❌          |

> **Note:** The major version of this plugin follows the major version of Capacitor. Use the version that matches your Capacitor installation (e.g., plugin v8 for Capacitor 8). Only the latest major version is actively maintained.

## Install

```bash
npm install @capgo/capacitor-photo-library
npx cap sync
```

## Usage

```ts
import { Capacitor } from '@capacitor/core';
import { PhotoLibrary } from '@capgo/capacitor-photo-library';

const { state } = await PhotoLibrary.requestAuthorization();
if (state === 'authorized' || state === 'limited') {
  const { assets, hasMore } = await PhotoLibrary.getLibrary({
    limit: 100,
    thumbnailWidth: 256,
    thumbnailHeight: 256,
  });

  const gallery = assets.map(asset => ({
    id: asset.id,
    fileName: asset.fileName,
    thumbnailUrl: asset.thumbnail
      ? asset.thumbnail.webPath ?? Capacitor.convertFileSrc(asset.thumbnail.path)
      : undefined,
    photoUrl: asset.file
      ? asset.file.webPath ?? Capacitor.convertFileSrc(asset.file.path)
      : undefined,
  }));

  console.log('Loaded', gallery.length, 'items. More available?', hasMore);
}

const picked = await PhotoLibrary.pickMedia({
  selectionLimit: 3,
  includeVideos: true,
});

console.log('User selected', picked.assets.length, 'items');
```

The native implementations cache exported files inside the application cache
directory. You can safely delete the `photoLibrary` folder under the cache if
you need to free up space.

## API

<docgen-index>

* [`checkAuthorization()`](#checkauthorization)
* [`requestAuthorization()`](#requestauthorization)
* [`getAlbums()`](#getalbums)
* [`getLibrary(...)`](#getlibrary)
* [`getPhotoUrl(...)`](#getphotourl)
* [`getThumbnailUrl(...)`](#getthumbnailurl)
* [`pickMedia(...)`](#pickmedia)
* [`getPluginVersion()`](#getpluginversion)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### checkAuthorization()

```typescript
checkAuthorization() => Promise<{ state: PhotoLibraryAuthorizationState; }>
```

Returns the current authorization status without prompting the user.

**Returns:** <code>Promise&lt;{ state: <a href="#photolibraryauthorizationstate">PhotoLibraryAuthorizationState</a>; }&gt;</code>

--------------------


### requestAuthorization()

```typescript
requestAuthorization() => Promise<{ state: PhotoLibraryAuthorizationState; }>
```

Requests access to the photo library if needed.

**Returns:** <code>Promise&lt;{ state: <a href="#photolibraryauthorizationstate">PhotoLibraryAuthorizationState</a>; }&gt;</code>

--------------------


### getAlbums()

```typescript
getAlbums() => Promise<{ albums: PhotoLibraryAlbum[]; }>
```

Retrieves the available albums.

**Returns:** <code>Promise&lt;{ albums: PhotoLibraryAlbum[]; }&gt;</code>

--------------------


### getLibrary(...)

```typescript
getLibrary(options?: GetLibraryOptions | undefined) => Promise<GetLibraryResult>
```

Retrieves library assets along with URLs that can be displayed in the web view.

| Param         | Type                                                            |
| ------------- | --------------------------------------------------------------- |
| **`options`** | <code><a href="#getlibraryoptions">GetLibraryOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#getlibraryresult">GetLibraryResult</a>&gt;</code>

--------------------


### getPhotoUrl(...)

```typescript
getPhotoUrl(options: { id: string; }) => Promise<PhotoLibraryFile>
```

Retrieves a displayable URL for the full resolution version of the asset.
If you already called `getLibrary` with `includeFullResolutionData`, you normally
do not need this method.

| Param         | Type                         |
| ------------- | ---------------------------- |
| **`options`** | <code>{ id: string; }</code> |

**Returns:** <code>Promise&lt;<a href="#photolibraryfile">PhotoLibraryFile</a>&gt;</code>

--------------------


### getThumbnailUrl(...)

```typescript
getThumbnailUrl(options: { id: string; width?: number; height?: number; quality?: number; }) => Promise<PhotoLibraryFile>
```

Retrieves a displayable URL for a resized thumbnail of the asset.

| Param         | Type                                                                            |
| ------------- | ------------------------------------------------------------------------------- |
| **`options`** | <code>{ id: string; width?: number; height?: number; quality?: number; }</code> |

**Returns:** <code>Promise&lt;<a href="#photolibraryfile">PhotoLibraryFile</a>&gt;</code>

--------------------


### pickMedia(...)

```typescript
pickMedia(options?: PickMediaOptions | undefined) => Promise<PickMediaResult>
```

Opens the native system picker so the user can select media without granting full photo library access.
The selected files are copied into the application cache and returned with portable URLs.

| Param         | Type                                                          |
| ------------- | ------------------------------------------------------------- |
| **`options`** | <code><a href="#pickmediaoptions">PickMediaOptions</a></code> |

**Returns:** <code>Promise&lt;<a href="#pickmediaresult">PickMediaResult</a>&gt;</code>

--------------------


### getPluginVersion()

```typescript
getPluginVersion() => Promise<{ version: string; }>
```

Get the native Capacitor plugin version

**Returns:** <code>Promise&lt;{ version: string; }&gt;</code>

--------------------


### Interfaces


#### PhotoLibraryAlbum

| Prop             | Type                |
| ---------------- | ------------------- |
| **`id`**         | <code>string</code> |
| **`title`**      | <code>string</code> |
| **`assetCount`** | <code>number</code> |


#### GetLibraryResult

| Prop             | Type                             | Description                                                                                                                    |
| ---------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **`assets`**     | <code>PhotoLibraryAsset[]</code> |                                                                                                                                |
| **`totalCount`** | <code>number</code>              | Total number of assets matching the query in the library. `assets.length` can be less than this value when pagination is used. |
| **`hasMore`**    | <code>boolean</code>             | Whether more assets are available when using pagination.                                                                       |


#### PhotoLibraryAsset

| Prop                   | Type                                                          | Description                                                              |
| ---------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **`id`**               | <code>string</code>                                           |                                                                          |
| **`fileName`**         | <code>string</code>                                           |                                                                          |
| **`type`**             | <code><a href="#photoassettype">PhotoAssetType</a></code>     |                                                                          |
| **`width`**            | <code>number</code>                                           |                                                                          |
| **`height`**           | <code>number</code>                                           |                                                                          |
| **`duration`**         | <code>number</code>                                           |                                                                          |
| **`creationDate`**     | <code>string</code>                                           |                                                                          |
| **`modificationDate`** | <code>string</code>                                           |                                                                          |
| **`latitude`**         | <code>number</code>                                           |                                                                          |
| **`longitude`**        | <code>number</code>                                           |                                                                          |
| **`mimeType`**         | <code>string</code>                                           |                                                                          |
| **`size`**             | <code>number</code>                                           | Size in bytes reported by the OS for the underlying asset, if available. |
| **`albumIds`**         | <code>string[]</code>                                         |                                                                          |
| **`thumbnail`**        | <code><a href="#photolibraryfile">PhotoLibraryFile</a></code> |                                                                          |
| **`file`**             | <code><a href="#photolibraryfile">PhotoLibraryFile</a></code> |                                                                          |


#### PhotoLibraryFile

| Prop           | Type                | Description                                                                                   |
| -------------- | ------------------- | --------------------------------------------------------------------------------------------- |
| **`path`**     | <code>string</code> | Absolute path on the native file system.                                                      |
| **`webPath`**  | <code>string</code> | URL that can be used inside a web view. Usually produced by `Capacitor.convertFileSrc(path)`. |
| **`mimeType`** | <code>string</code> |                                                                                               |
| **`size`**     | <code>number</code> | Size in bytes if known, otherwise `-1`.                                                       |


#### GetLibraryOptions

| Prop                            | Type                 | Description                                                                                           |
| ------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------- |
| **`offset`**                    | <code>number</code>  | Number of assets to skip from the beginning of the query.                                             |
| **`limit`**                     | <code>number</code>  | Maximum number of assets to return. Omit to return everything that matches.                           |
| **`includeImages`**             | <code>boolean</code> | Include images in the result. Defaults to `true`.                                                     |
| **`includeVideos`**             | <code>boolean</code> | Include videos in the result. Defaults to `false`.                                                    |
| **`includeAlbumData`**          | <code>boolean</code> | Include information about the albums each asset belongs to. Defaults to `false`.                      |
| **`includeCloudData`**          | <code>boolean</code> | Include assets stored in the cloud (iCloud / Google Photos). Defaults to `true`.                      |
| **`useOriginalFileNames`**      | <code>boolean</code> | If `true`, use the original filenames reported by the OS when available.                              |
| **`thumbnailWidth`**            | <code>number</code>  | Width of the generated thumbnails. Defaults to `512`.                                                 |
| **`thumbnailHeight`**           | <code>number</code>  | Height of the generated thumbnails. Defaults to `384`.                                                |
| **`thumbnailQuality`**          | <code>number</code>  | JPEG quality for generated thumbnails (0-1). Defaults to `0.5`.                                       |
| **`includeFullResolutionData`** | <code>boolean</code> | When `true`, copies the full sized asset into the app cache and returns its URL. Defaults to `false`. |


#### PickMediaResult

| Prop         | Type                             |
| ------------ | -------------------------------- |
| **`assets`** | <code>PhotoLibraryAsset[]</code> |


#### PickMediaOptions

| Prop                   | Type                 | Description                                                                                         |
| ---------------------- | -------------------- | --------------------------------------------------------------------------------------------------- |
| **`selectionLimit`**   | <code>number</code>  | Maximum number of items the user can select. Use `0` to allow unlimited selection. Defaults to `1`. |
| **`includeImages`**    | <code>boolean</code> | Allow the user to select images. Defaults to `true`.                                                |
| **`includeVideos`**    | <code>boolean</code> | Allow the user to select videos. Defaults to `false`.                                               |
| **`thumbnailWidth`**   | <code>number</code>  | Width of the generated thumbnails for picked items. Defaults to `256`.                              |
| **`thumbnailHeight`**  | <code>number</code>  | Height of the generated thumbnails for picked items. Defaults to `256`.                             |
| **`thumbnailQuality`** | <code>number</code>  | JPEG quality for generated thumbnails (0-1). Defaults to `0.7`.                                     |


### Type Aliases


#### PhotoLibraryAuthorizationState

<code>'authorized' | 'limited' | 'denied' | 'notDetermined'</code>


#### PhotoAssetType

<code>'image' | 'video'</code>

</docgen-api>
