import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'
import type { VitePWAOptions } from 'vite-plugin-pwa'  // <- Add this

const pwaOptions = {
  strategies: 'generateSW',
  registerType: 'autoUpdate',
  injectRegister: false,
  minify: true,
  pwaAssets: {
    disabled: false,
    config: true,
  },
  // injectManifest: undefined,
  includeAssets: ['favicon.ico', 'apple-touch-icon.png'],
  includeManifestIcons: true,
  manifest: {
    name: 'imposter',
    short_name: 'imposter',
    description: 'An imposter progressive web app',
    theme_color: '#ffffff',
    display: 'standalone',  // Added
    start_url: '/',         // Added
    icons: [                // Add after generating assets
      { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png' },
      { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png' }
    ]
  },
  workbox: {
    globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
    cleanupOutdatedCaches: true,
    clientsClaim: true,
  },
  devOptions: {
    enabled: true,  // Enable for dev testing
    navigateFallback: 'index.html',
    suppressWarnings: true,
    type: 'module',
  }
}

export default defineConfig({
  plugins: [react(), VitePWA(pwaOptions as any)]
})
