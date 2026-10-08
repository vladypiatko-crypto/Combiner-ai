import { defineConfig } from 'vitest/config';

// `base: './'` keeps every asset path relative, so the same build works on
// GitHub Pages (/<repo>/), Netlify, Cloudflare Pages or a phone's local server.
export default defineConfig({
  base: './',
  build: {
    target: 'es2022',
    chunkSizeWarningLimit: 900,
  },
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
});
