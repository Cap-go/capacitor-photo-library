import { App } from '@capacitor/app';
import { Capacitor } from '@capacitor/core';
import { PhotoLibrary } from '@capgo/capacitor-photo-library';

const storagePrefix = '__capgo_photo_maestro_';
const VALID_AUTH_STATES = new Set(['notDetermined', 'denied', 'authorized', 'limited']);
const harnessSessionId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
let activeFlowGeneration = 0;

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
  localStorage.setItem(
    `${storagePrefix}pending_payload`,
    JSON.stringify({ ...payload, sessionId: harnessSessionId }),
  );
}

function isPermissionRejectionMessage(message) {
  return /denied|permission|authorize|not authorized|access/i.test(message);
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
    if (!VALID_AUTH_STATES.has(auth.state)) {
      setMarker('permission-check', false, auth.state ?? 'missing');
      return;
    }
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
      setMarker('permission-denied', false, 'notDetermined');
      return;
    }
    if (auth.state === 'authorized' || auth.state === 'limited') {
      try {
        await PhotoLibrary.getLibrary({ limit: 1 });
        setMarker('permission-denied', false, 'getLibrary succeeded while authorized');
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        setMarker('permission-denied', false, `authorized but getLibrary failed: ${message}`);
      }
      return;
    }
    try {
      await PhotoLibrary.getLibrary({ limit: 1 });
      setMarker('permission-denied', false, 'getLibrary succeeded while denied');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setMarker('permission-denied', isPermissionRejectionMessage(message), message);
    }
  },

  async 'pick-media-cancel'() {
    setSummary('PHASE:pick-media-cancel:opening');
    await sleep(500);
    let settled = false;
    const settle = (ok, detail) => {
      if (settled) {
        return;
      }
      settled = true;
      setMarker('pick-media-cancel', ok, detail);
    };
    const pickPromise = PhotoLibrary.pickMedia({
      selectionLimit: 1,
      includeImages: true,
      includeVideos: false,
    })
      .then((result) => {
        if (result.assets.length !== 0) {
          throw new Error(`expected empty pick result on cancel, got ${result.assets.length}`);
        }
        settle(true, 'assets=0');
      })
      .catch((error) => {
        const message = String(error?.message ?? error);
        const cancelled =
          /cancel/i.test(message) || /dismiss/i.test(message) || /User canceled/i.test(message);
        settle(cancelled, cancelled ? 'cancelled' : message);
      });
    const deadline = Date.now() + 120_000;
    while (Date.now() < deadline && !settled) {
      await sleep(250);
    }
    if (!settled) {
      throw new Error('pick-media-cancel timed out waiting for dismissal');
    }
    await pickPromise;
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
  const { flowId, payload } = pending;
  if (payload?.sessionId === harnessSessionId) {
    return false;
  }
  activeFlowGeneration += 1;
  const auth = await PhotoLibrary.checkAuthorization();
  setSummary(`AUTH:resume:${auth.state}`);
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    try {
      const lib = await PhotoLibrary.getLibrary({
        limit: 4,
        thumbnailWidth: 128,
        thumbnailHeight: 128,
      });
      if (lib.totalCount >= 1 && lib.assets.length >= 1) {
        clearPending();
        setMarker(flowId, true, 'resumed');
        return true;
      }
    } catch {
      // Retry until deadline when the library is still warming up.
    }
    await sleep(500);
  }
  setMarker(flowId, false, 'resume returned no assets');
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
    button.addEventListener('pointerdown', () => {
      setSummary(`EVENT:RUN:${flowId}`);
    });
    button.addEventListener('click', () => {
      void runFlow(flowId).catch((error) => {
        setMarker(flowId, false, String(error?.message ?? error));
      });
    });
    flowButtons.appendChild(button);
  }
}

export async function initMaestroHarness() {
  harnessReady.textContent = 'Harness: booting';
  installFlowButtons();
  harnessReady.textContent = 'Harness: ready';
  setSummary('Harness: ready');

  await resumePendingFlowIfNeeded();

  const autoFlow =
    typeof window.__capgoMaestroFlow === 'string' ? window.__capgoMaestroFlow.trim() : '';
  if (autoFlow && Object.prototype.hasOwnProperty.call(flows, autoFlow)) {
    await runFlow(autoFlow);
  }

  App.addListener('appStateChange', (state) => {
    appendLog(`APP:${state.isActive ? 'active' : 'background'}`);
    if (state.isActive) {
      resumePendingFlowIfNeeded().catch((error) => {
        setSummary(`APP:resume-error:${error?.message ?? error}`);
      });
    }
  });
}