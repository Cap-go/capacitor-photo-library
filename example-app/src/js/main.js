import { Capacitor } from '@capacitor/core';

function reportHarnessError(error) {
  const message = String(error?.message ?? error);
  const harnessReady = document.getElementById('harness-ready');
  const e2eSummary = document.getElementById('e2e-summary');
  if (harnessReady) {
    harnessReady.textContent = `Harness: error ${message}`;
  }
  if (e2eSummary) {
    e2eSummary.textContent = `Harness: error ${message}`;
  }
  console.error('Maestro harness failed', error);
}

async function bootstrap() {
  const isMaestroE2E =
    import.meta.env.VITE_CAPGO_MAESTRO_BUILD === 'true' || window.__capgoMaestroIsE2E === true;

  if (isMaestroE2E) {
    document.getElementById('maestro-panel')?.classList.remove('hidden');
    document.getElementById('manual-panel')?.classList.add('hidden');
    if (Capacitor.isNativePlatform()) {
      try {
        const { CapacitorUpdater } = await import('@capgo/capacitor-updater');
        await CapacitorUpdater.notifyAppReady();
      } catch (error) {
        console.warn('Capgo notifyAppReady failed in Maestro harness', error);
      }
    }
    const { initMaestroHarness } = await import('./maestro-harness.js');
    try {
      await initMaestroHarness();
    } catch (error) {
      reportHarnessError(error);
    }
    return;
  }

  await import('./example.js');
}

void bootstrap();