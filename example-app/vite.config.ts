import { defineConfig, loadEnv, type Plugin } from 'vite';

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
    define: {
      'import.meta.env.VITE_CAPGO_MAESTRO_BUILD': JSON.stringify(env.VITE_CAPGO_MAESTRO_BUILD ?? ''),
    },
  };
});