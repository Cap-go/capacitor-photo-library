import { App } from '@capacitor/app';
import { PhotoLibrary } from '@capgo/capacitor-photo-library';

const storagePrefix = '__capgo_photo_maestro_';
let activeFlowGeneration = 0;
let autoFlowStarted = false;

function requireElement(id) {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`Expected #${id}`);
  }
  return element;
}

const harnessReady = requireElement('harness-ready');
const e2eSummary = requireElement('e2e-summary');
const e2eLog = requireElement('e2e-log');
const flowButtons = requireElement('e2e-flow-buttons');

function appendLog(line) {
  const stamp = new Date().toISOString();
  e2eLog.textContent = `${e2eLog.textContent}\n${stamp} ${line}`.trim();
}

function setSummary(text) {
  e2eSummary.textContent = text;
  if (/^(PHASE|Marker|ASSERT|EVENT|STATE|APP|AUTH):/.test(text)) {
    harnessReady.textContent = text;
  }
  appendLog(text);
}

function setMarker(flowId, ok, detail = '') {
  const status = ok ? 'success' : 'failure';
  const suffix = detail ? `:${detail}` : '';
  setSummary(`Marker: ${flowId}:${status}${suffix}`);
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function persistPending(flowId, payload) {
  localStorage.setItem(`${storagePrefix}pending_flow`, flowId);
  localStorage.setItem(`${storagePrefix}pending_payload`, JSON.stringify(payload));
}

function clearPending() {
  localStorage.removeItem(`${storagePrefix}pending_flow`);
  localStorage.removeItem(`${storagePrefix}pending_payload`);
}

function readPending() {
  const flowId = localStorage.getItem(`${storagePrefix}pending_flow`);
  const raw = localStorage.getItem(`${storagePrefix}pending_payload`);
  if (!flowId || !raw) {
    return null;
  }
  return { flowId, payload: JSON.parse(raw) };
}

async function assertLibraryHasSeededMedia() {
  const lib = await PhotoLibrary.getLibrary({
    limit: 8,
    thumbnailWidth: 128,
    thumbnailHeight: 128,
    includeVideos: false,
  });
  if (lib.totalCount < 1 || lib.assets.length < 1) {
    throw new Error(`expected seeded library media, totalCount=${lib.totalCount}`);
  }
  return lib;
}

const flows = {
  async 'permission-check'() {
    const auth = await PhotoLibrary.checkAuthorization();
    setSummary(`AUTH:${auth.state}`);
    setMarker('permission-check', true, auth.state);
  },

  async 'permission-grant-library'() {
    const auth = await PhotoLibrary.requestAuthorization();
    setSummary(`AUTH:${auth.state}`);
    if (auth.state === 'denied') {
      throw new Error('authorization denied after request');
    }
    const albums = await PhotoLibrary.getAlbums();
    if (!Array.isArray(albums.albums)) {
      throw new Error('albums payload invalid');
    }
    const lib = await assertLibraryHasSeededMedia();
    setMarker('permission-grant-library', true, `albums=${albums.albums.length}:assets=${lib.assets.length}`);
  },

  async 'permission-denied'() {
    const auth = await PhotoLibrary.checkAuthorization();
    setSummary(`AUTH:${auth.state}`);
    if (auth.state === 'notDetermined') {
      setMarker('permission-denied', true, 'notDetermined');
      return;
    }
    try {
      await PhotoLibrary.getLibrary({ limit: 1 });
      if (auth.state === 'authorized' || auth.state === 'limited') {
        throw new Error('getLibrary succeeded while testing denial');
      }
      setMarker('permission-denied', true, `state=${auth.state}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setMarker('permission-denied', true, message);
    }
  },

  async 'pick-media-cancel'() {
    setSummary('PHASE:pick-media-cancel:opening');
    void PhotoLibrary.pickMedia({ selectionLimit: 1, includeImages: true, includeVideos: false })
      .then((result) => {
        if (result.assets.length !== 0) {
          throw new Error(`expected empty pick result on cancel, got ${result.assets.length}`);
        }
        setMarker('pick-media-cancel', true, 'assets=0');
      })
      .catch((error) => {
        setMarker('pick-media-cancel', false, String(error?.message ?? error));
      });
    await sleep(250);
  },

  async 'kill-relaunch-mid-library'() {
    const generation = ++activeFlowGeneration;
    persistPending('kill-relaunch-mid-library', { resume: true });
    setSummary('PHASE:kill-relaunch-mid-library:fetching');
    void PhotoLibrary.getLibrary({
      limit: 40,
      includeFullResolutionData: true,
      thumbnailWidth: 384,
      thumbnailHeight: 384,
    })
      .then(async (lib) => {
        if (generation !== activeFlowGeneration) {
          return;
        }
        if (lib.assets.length < 1) {
          throw new Error('library fetch returned no assets');
        }
        if (readPending()?.flowId === 'kill-relaunch-mid-library') {
          setSummary(`STATE:kill-relaunch-mid-library:fetched:${lib.assets.length}`);
          return;
        }
        clearPending();
        setMarker('kill-relaunch-mid-library', true, `assets=${lib.assets.length}`);
      })
      .catch((error) => {
        if (generation !== activeFlowGeneration) {
          return;
        }
        setMarker('kill-relaunch-mid-library', false, String(error?.message ?? error));
      });
    await sleep(2_500);
  },

  async 'low-memory-mid-library'() {
    const generation = ++activeFlowGeneration;
    persistPending('low-memory-mid-library', { resume: true });
    setSummary('PHASE:low-memory-mid-library:fetching');
    void PhotoLibrary.getLibrary({
      limit: 40,
      includeFullResolutionData: true,
      thumbnailWidth: 384,
      thumbnailHeight: 384,
    })
      .then(async (lib) => {
        if (generation !== activeFlowGeneration) {
          return;
        }
        if (lib.assets.length < 1) {
          throw new Error('library fetch returned no assets');
        }
        if (readPending()?.flowId === 'low-memory-mid-library') {
          setSummary(`STATE:low-memory-mid-library:fetched:${lib.assets.length}`);
          return;
        }
        clearPending();
        setMarker('low-memory-mid-library', true, `assets=${lib.assets.length}`);
      })
      .catch((error) => {
        if (generation !== activeFlowGeneration) {
          return;
        }
        setMarker('low-memory-mid-library', false, String(error?.message ?? error));
      });
    await sleep(2_500);
  },
};

async function resumePendingFlowIfNeeded() {
  const pending = readPending();
  if (!pending) {
    return false;
  }
  const { flowId } = pending;
  activeFlowGeneration += 1;
  try {
    const auth = await PhotoLibrary.checkAuthorization();
    setSummary(`AUTH:resume:${auth.state}`);
    await PhotoLibrary.getLibrary({ limit: 4, thumbnailWidth: 128, thumbnailHeight: 128 });
    clearPending();
    setMarker(flowId, true, 'resumed');
  } catch (error) {
    setMarker(flowId, false, String(error?.message ?? error));
  }
  return true;
}

async function runFlow(flowId) {
  appendLog(`RUN:${flowId}`);
  const runner = flows[flowId];
  if (!runner) {
    throw new Error(`Unknown flow ${flowId}`);
  }
  await runner();
}

function installFlowButtons() {
  const flowIds = Object.keys(flows);
  flowButtons.innerHTML = '';
  for (const flowId of flowIds) {
    const button = document.createElement('button');
    button.type = 'button';
    button.id = `e2e-flow-${flowId}`;
    button.setAttribute('data-testid', `e2e-flow-${flowId}`);
    button.textContent = flowId;
    button.addEventListener('click', () => {
      setSummary(`EVENT:RUN:${flowId}`);
      void runFlow(flowId).catch((error) => {
        setMarker(flowId, false, String(error?.message ?? error));
      });
    });
    flowButtons.appendChild(button);
  }
}

async function runAutoFlowIfRequested() {
  const autoFlow =
    (typeof window.__capgoMaestroAutoFlow === 'string' && window.__capgoMaestroAutoFlow) ||
    localStorage.getItem(`${storagePrefix}autorun`);
  if (!autoFlow || !flows[autoFlow]) {
    return false;
  }
  delete window.__capgoMaestroAutoFlow;
  localStorage.removeItem(`${storagePrefix}autorun`);
  setSummary(`EVENT:RUN:${autoFlow}`);
  await sleep(350);
  await runFlow(autoFlow);
  return true;
}

export async function initMaestroHarness() {
  harnessReady.textContent = 'Harness: booting';
  installFlowButtons();
  harnessReady.textContent = 'Harness: ready';
  setSummary('Harness: ready');

  const resumed = await resumePendingFlowIfNeeded();
  if (!resumed) {
    await runAutoFlowIfRequested();
  }
  window.addEventListener(
    'capgo-maestro-autoflow',
    () => {
      if (!readPending()) {
        void runAutoFlowIfRequested();
      }
    },
    { once: true },
  );

  App.addListener('appStateChange', (state) => {
    appendLog(`APP:${state.isActive ? 'active' : 'background'}`);
    if (state.isActive) {
      resumePendingFlowIfNeeded().catch((error) => {
        setSummary(`APP:resume-error:${error?.message ?? error}`);
      });
    }
  });
}