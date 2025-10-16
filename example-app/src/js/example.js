import { Capacitor } from '@capacitor/core';
import { PhotoLibrary } from '@capgo/capacitor-photo-library';

const authStatusEl = document.getElementById('authStatus');
const albumListEl = document.getElementById('albumList');
const librarySummaryEl = document.getElementById('librarySummary');
const statusTextEl = document.getElementById('statusText');
const responseOutputEl = document.getElementById('responseOutput');
const assetsContainerEl = document.getElementById('assetsContainer');

const assetIdInput = document.getElementById('assetIdInput');

const offsetInput = document.getElementById('offsetInput');
const limitInput = document.getElementById('limitInput');
const thumbWidthInput = document.getElementById('thumbWidthInput');
const thumbHeightInput = document.getElementById('thumbHeightInput');
const includeImagesInput = document.getElementById('includeImagesInput');
const includeVideosInput = document.getElementById('includeVideosInput');
const includeAlbumsInput = document.getElementById('includeAlbumsInput');
const includeFullInput = document.getElementById('includeFullInput');

const thumbActionWidthInput = document.getElementById('thumbActionWidth');
const thumbActionHeightInput = document.getElementById('thumbActionHeight');
const thumbActionQualityInput = document.getElementById('thumbActionQuality');
const selectionLimitInput = document.getElementById('selectionLimitInput');

const checkAuthButton = document.getElementById('checkAuthButton');
const requestAuthButton = document.getElementById('requestAuthButton');
const loadAlbumsButton = document.getElementById('loadAlbumsButton');
const getLibraryButton = document.getElementById('getLibraryButton');
const getPhotoUrlButton = document.getElementById('getPhotoUrlButton');
const getThumbnailButton = document.getElementById('getThumbnailButton');
const pickMediaButton = document.getElementById('pickMediaButton');

const setStatus = (message) => {
  if (statusTextEl) {
    statusTextEl.textContent = `Status: ${message}`;
  }
};

const setResponse = (payload) => {
  if (responseOutputEl) {
    responseOutputEl.textContent = JSON.stringify(payload, null, 2);
  }
};

const toNumberOrUndefined = (value) => {
  const parsed = Number(value);
  return Number.isNaN(parsed) ? undefined : parsed;
};

const renderAlbums = (albums = []) => {
  if (!albumListEl) return;
  albumListEl.innerHTML = '';
  if (!albums.length) {
    const empty = document.createElement('li');
    empty.textContent = 'No albums returned.';
    albumListEl.appendChild(empty);
    return;
  }

  albums.forEach((album) => {
    const item = document.createElement('li');
    item.textContent = `${album.title} (${album.assetCount}) – ${album.id}`;
    albumListEl.appendChild(item);
  });
};

const renderAssets = (assets = []) => {
  if (!assetsContainerEl) return;
  assetsContainerEl.innerHTML = '';
  if (!assets.length) {
    assetsContainerEl.textContent = 'No assets to display.';
    return;
  }

  assets.forEach((asset) => {
    const card = document.createElement('div');
    card.className = 'asset-card';

    const heading = document.createElement('strong');
    heading.textContent = `${asset.type?.toUpperCase() ?? 'ASSET'} – ${asset.fileName ?? asset.id}`;
    card.appendChild(heading);

    if (asset.thumbnail?.webPath || asset.thumbnail?.path) {
      const img = document.createElement('img');
      const src = asset.thumbnail.webPath || Capacitor.convertFileSrc(asset.thumbnail.path);
      img.src = src;
      img.alt = asset.fileName ?? asset.id;
      card.appendChild(img);
    }

    const meta = document.createElement('div');
    meta.innerHTML = `
      <div><strong>ID:</strong> ${asset.id}</div>
      <div><strong>Dimensions:</strong> ${asset.width} × ${asset.height}</div>
      ${asset.duration ? `<div><strong>Duration:</strong> ${asset.duration}s</div>` : ''}
      ${asset.creationDate ? `<div><strong>Created:</strong> ${asset.creationDate}</div>` : ''}
    `;
    card.appendChild(meta);

    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = 'Use this asset id';
    button.addEventListener('click', () => {
      if (assetIdInput) {
        assetIdInput.value = asset.id;
      }
      setResponse({ asset });
    });
    card.appendChild(button);

    assetsContainerEl.appendChild(card);
  });
};

checkAuthButton?.addEventListener('click', async () => {
  try {
    setStatus('Checking authorization...');
    const result = await PhotoLibrary.checkAuthorization();
    authStatusEl.textContent = `Authorization state: ${result.state}`;
    setResponse(result);
    setStatus('Authorization checked');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    authStatusEl.textContent = `Error: ${message}`;
    setResponse({ error: message });
    setStatus('Check authorization failed');
  }
});

requestAuthButton?.addEventListener('click', async () => {
  try {
    setStatus('Requesting authorization...');
    const result = await PhotoLibrary.requestAuthorization();
    authStatusEl.textContent = `Authorization state: ${result.state}`;
    setResponse(result);
    setStatus('Authorization requested');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    authStatusEl.textContent = `Error: ${message}`;
    setResponse({ error: message });
    setStatus('Request authorization failed');
  }
});

loadAlbumsButton?.addEventListener('click', async () => {
  try {
    setStatus('Loading albums...');
    const result = await PhotoLibrary.getAlbums();
    renderAlbums(result.albums);
    setResponse(result);
    setStatus(`Loaded ${result.albums.length} albums`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    renderAlbums([]);
    setResponse({ error: message });
    setStatus('Load albums failed');
  }
});

const buildLibraryOptions = () => {
  const options = {
    includeImages: Boolean(includeImagesInput?.checked),
    includeVideos: Boolean(includeVideosInput?.checked),
    includeAlbumData: Boolean(includeAlbumsInput?.checked),
    includeFullResolutionData: Boolean(includeFullInput?.checked),
  };

  const offset = toNumberOrUndefined(offsetInput?.value);
  const limit = toNumberOrUndefined(limitInput?.value);
  const thumbWidth = toNumberOrUndefined(thumbWidthInput?.value);
  const thumbHeight = toNumberOrUndefined(thumbHeightInput?.value);

  if (offset !== undefined) options.offset = offset;
  if (limit !== undefined) options.limit = limit;
  if (thumbWidth !== undefined) options.thumbnailWidth = thumbWidth;
  if (thumbHeight !== undefined) options.thumbnailHeight = thumbHeight;

  return options;
};

getLibraryButton?.addEventListener('click', async () => {
  try {
    setStatus('Fetching assets...');
    const options = buildLibraryOptions();
    const result = await PhotoLibrary.getLibrary(options);
    librarySummaryEl.textContent = `Fetched ${result.assets.length} assets (Total count: ${result.totalCount}, has more: ${result.hasMore})`;
    renderAssets(result.assets);
    setResponse({ options, result });
    setStatus('Library fetched');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    librarySummaryEl.textContent = `Error: ${message}`;
    renderAssets([]);
    setResponse({ error: message });
    setStatus('Fetch assets failed');
  }
});

const getSelectedAssetId = () => {
  const value = assetIdInput?.value?.trim();
  if (!value) {
    throw new Error('Provide an asset ID first. Load assets and use "Use this asset id" to populate the field.');
  }
  return value;
};

getPhotoUrlButton?.addEventListener('click', async () => {
  try {
    const id = getSelectedAssetId();
    setStatus('Fetching full resolution URL...');
    const result = await PhotoLibrary.getPhotoUrl({ id });
    setResponse(result);
    setStatus('Retrieved full resolution URL');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setResponse({ error: message });
    setStatus('Get photo URL failed');
  }
});

getThumbnailButton?.addEventListener('click', async () => {
  try {
    const id = getSelectedAssetId();
    const width = toNumberOrUndefined(thumbActionWidthInput?.value);
    const height = toNumberOrUndefined(thumbActionHeightInput?.value);
    const quality = Number(thumbActionQualityInput?.value);

    const options = { id };
    if (width !== undefined) options.width = width;
    if (height !== undefined) options.height = height;
    if (!Number.isNaN(quality) && thumbActionQualityInput?.value !== '') {
      options.quality = quality;
    }

    setStatus('Fetching thumbnail URL...');
    const result = await PhotoLibrary.getThumbnailUrl(options);
    setResponse({ options, result });
    setStatus('Retrieved thumbnail URL');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setResponse({ error: message });
    setStatus('Get thumbnail URL failed');
  }
});

pickMediaButton?.addEventListener('click', async () => {
  try {
    const selectionLimit = toNumberOrUndefined(selectionLimitInput?.value);
    const options = {
      selectionLimit: selectionLimit ?? 0,
      includeImages: true,
      includeVideos: Boolean(includeVideosInput?.checked),
      thumbnailWidth: Number(thumbActionWidthInput?.value) || undefined,
      thumbnailHeight: Number(thumbActionHeightInput?.value) || undefined,
      thumbnailQuality: Number(thumbActionQualityInput?.value) || undefined,
    };

    setStatus('Launching picker...');
    const result = await PhotoLibrary.pickMedia(options);
    librarySummaryEl.textContent = `Picked ${result.assets.length} assets`;
    renderAssets(result.assets);
    setResponse({ options, result });
    setStatus('Picker complete');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setResponse({ error: message });
    setStatus('Pick media failed');
  }
});
