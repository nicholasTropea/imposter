import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { functionsMixins } from "vite-plugin-functions-mixins";
import { VitePWA } from 'vite-plugin-pwa';

import Icons from 'unplugin-icons/vite';

export default defineConfig({
	plugins: [
		sveltekit(),
		
		Icons({
			compiler: 'svelte'
		}),
		
		functionsMixins({ deps: ['m3-svelte'] } ),

		// PWA
		VitePWA({
			registerType: 'autoUpdate',
			injectRegister: 'auto',
			manifest: {
				name: 'Imposter Words',
				short_name: 'Imposter',
				description: 'A social deduction word game',
				start_url: '/app',
				display: 'standalone',
				background_color: '#171309',
				theme_color: '#ffe394',
				icons: [
					{
						src: '/icons/icon-192.png',
						sizes: '192x192',
						type: 'image/png',
						purpose: 'any'
					},
					{
						src: '/icons/icon-512.png',
						sizes: '512x512',
						type: 'image/png',
						purpose: 'any maskable'
					}
				]
			},
			workbox: {
				globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
				runtimeCaching: [
					{
                        urlPattern: /^https:\/\/.*\.supabase\.co\/rest/,
                        handler: 'NetworkFirst',
                        options: {
                            cacheName: 'supabase-api',
                            expiration: {
                                maxEntries: 50,
                                maxAgeSeconds: 60 * 60 * 24 // 24h
                            }
                        }
					}
				]
			}
		})
	]
});