export type PhotoLibraryAuthorizationState = 'authorized' | 'limited' | 'denied' | 'notDetermined';

export interface PhotoLibraryPermissions {
  read?: PhotoLibraryAuthorizationState;
}

export interface GetLibraryOptions {
  /**
   * Number of assets to skip from the beginning of the query.
   */
  offset?: number;
  /**
   * Maximum number of assets to return. Omit to return everything that matches.
   */
  limit?: number;
  /**
   * Include images in the result. Defaults to `true`.
   */
  includeImages?: boolean;
  /**
   * Include videos in the result. Defaults to `false`.
   */
  includeVideos?: boolean;
  /**
   * Include information about the albums each asset belongs to. Defaults to `false`.
   */
  includeAlbumData?: boolean;
  /**
   * Include assets stored in the cloud (iCloud / Google Photos). Defaults to `true`.
   */
  includeCloudData?: boolean;
  /**
   * If `true`, use the original filenames reported by the OS when available.
   */
  useOriginalFileNames?: boolean;
  /**
   * Width of the generated thumbnails. Defaults to `512`.
   */
  thumbnailWidth?: number;
  /**
   * Height of the generated thumbnails. Defaults to `384`.
   */
  thumbnailHeight?: number;
  /**
   * JPEG quality for generated thumbnails (0-1). Defaults to `0.5`.
   */
  thumbnailQuality?: number;
  /**
   * When `true`, copies the full sized asset into the app cache and returns its URL.
   * Defaults to `false`.
   */
  includeFullResolutionData?: boolean;
}

export interface PhotoLibraryFile {
  /** Absolute path on the native file system. */
  path: string;
  /**
   * URL that can be used inside a web view. Usually produced by `Capacitor.convertFileSrc(path)`.
   */
  webPath: string;
  mimeType: string;
  /** Size in bytes if known, otherwise `-1`. */
  size: number;
}

export type PhotoAssetType = 'image' | 'video';

export interface PhotoLibraryAsset {
  id: string;
  fileName: string;
  type: PhotoAssetType;
  width: number;
  height: number;
  duration?: number;
  creationDate?: string;
  modificationDate?: string;
  latitude?: number;
  longitude?: number;
  mimeType: string;
  /** Size in bytes reported by the OS for the underlying asset, if available. */
  size?: number;
  albumIds?: string[];
  thumbnail?: PhotoLibraryFile;
  file?: PhotoLibraryFile;
}

export interface GetLibraryResult {
  assets: PhotoLibraryAsset[];
  /**
   * Total number of assets matching the query in the library. `assets.length` can be less
   * than this value when pagination is used.
   */
  totalCount: number;
  /** Whether more assets are available when using pagination. */
  hasMore: boolean;
}

export interface PhotoLibraryAlbum {
  id: string;
  title: string;
  assetCount: number;
}

export interface PickMediaOptions {
  /**
   * Maximum number of items the user can select. Use `0` to allow unlimited selection.
   * Defaults to `1`.
   */
  selectionLimit?: number;
  /** Allow the user to select images. Defaults to `true`. */
  includeImages?: boolean;
  /** Allow the user to select videos. Defaults to `false`. */
  includeVideos?: boolean;
  /** Width of the generated thumbnails for picked items. Defaults to `256`. */
  thumbnailWidth?: number;
  /** Height of the generated thumbnails for picked items. Defaults to `256`. */
  thumbnailHeight?: number;
  /** JPEG quality for generated thumbnails (0-1). Defaults to `0.7`. */
  thumbnailQuality?: number;
}

export interface PickMediaResult {
  assets: PhotoLibraryAsset[];
}

export interface PhotoLibraryPlugin {
  /** Returns the current authorization status without prompting the user. */
  checkAuthorization(): Promise<{ state: PhotoLibraryAuthorizationState }>;
  /** Requests access to the photo library if needed. */
  requestAuthorization(): Promise<{ state: PhotoLibraryAuthorizationState }>;
  /** Retrieves the available albums. */
  getAlbums(): Promise<{ albums: PhotoLibraryAlbum[] }>;
  /** Retrieves library assets along with URLs that can be displayed in the web view. */
  getLibrary(options?: GetLibraryOptions): Promise<GetLibraryResult>;
  /**
   * Retrieves a displayable URL for the full resolution version of the asset.
   * If you already called `getLibrary` with `includeFullResolutionData`, you normally
   * do not need this method.
   */
  getPhotoUrl(options: { id: string }): Promise<PhotoLibraryFile>;
  /** Retrieves a displayable URL for a resized thumbnail of the asset. */
  getThumbnailUrl(options: {
    id: string;
    width?: number;
    height?: number;
    quality?: number;
  }): Promise<PhotoLibraryFile>;
  /**
   * Opens the native system picker so the user can select media without granting full photo library access.
   * The selected files are copied into the application cache and returned with portable URLs.
   */
  pickMedia(options?: PickMediaOptions): Promise<PickMediaResult>;

  /**
   * Get the native Capacitor plugin version
   *
   * @returns {Promise<{ id: string }>} an Promise with version for this device
   * @throws An error if the something went wrong
   */
  getPluginVersion(): Promise<{ version: string }>;
}
