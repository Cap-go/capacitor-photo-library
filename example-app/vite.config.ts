import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, loadEnv, type Plugin } from 'vite';

const exampleDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(exampleDir, '..');

function stripCrossoriginForCapacitor(): Plugin {
  return {
    name: 'strip-crossorigin-for-capacitor',
    transformIndexHtml(html) {
      return html.replace(/ crossorigin/g, '');
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    root: './src',
    plugins: [stripCrossoriginForCapacitor()],
    build: {
      outDir: '../dist',
      minify: false,
      emptyOutDir: true,
      target: 'chrome80',
      modulePreload: false,
    },
    resolve: {
      alias: {
        '@capgo/capacitor-photo-library': path.join(repoRoot, 'dist/esm/index.js'),
      },
    },
    define: {
      'import.meta.env.VITE_CAPGO_MAESTRO_BUILD': JSON.stringify(env.VITE_CAPGO_MAESTRO_BUILD ?? ''),
    },
  };
});