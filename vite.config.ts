import { resolve } from 'node:path';
import { defineConfig } from 'vite';

// The NUI builds straight into the resource, so a server owner only copies resource/smashandclash.
// Three pages: index.html is the player's panel and HUD (NUI), atlas.html paints the card faces
// and sprites the 3D table samples, fx.html shows a character's strike drawing (both DUI).
export default defineConfig({
  root: resolve(__dirname, 'nui'),
  base: './',
  build: {
    outDir: resolve(__dirname, 'resource/smashandclash/html'),
    emptyOutDir: true,
    target: 'chrome103',
    assetsInlineLimit: 0,
    rollupOptions: {
      input: {
        index: resolve(__dirname, 'nui/index.html'),
        atlas: resolve(__dirname, 'nui/atlas.html'),
        fx: resolve(__dirname, 'nui/fx.html'),
      },
    },
  },
  // the dev page previews the table with the resource's own board.lua
  server: { port: 5394, strictPort: true, fs: { allow: [__dirname] } },
});
