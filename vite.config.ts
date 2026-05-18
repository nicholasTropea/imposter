import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { functionsMixins } from "vite-plugin-functions-mixins";
import { SvelteKitPWA } from '@vite-pwa/sveltekit';

import Icons from 'unplugin-icons/vite';

export default defineConfig({
	plugins: [
		sveltekit(),
		
		Icons({
			compiler: 'svelte'
		}),
		
		functionsMixins({ deps: ['m3-svelte'] } ),

		// PWA
		SvelteKitPWA({
			registerType: 'autoUpdate',
			injectRegister: false,
			strategies: 'injectManifest',
			srcDir: 'src',
			filename: 'service-worker.ts',
			injectManifest: {
				globPatterns: ['**/*.{js,css,html,ico,png,svg,webp,woff2,woff}'],
				globIgnores: ['service-worker.js', 'offline.html']
			},
			manifest: {
				name: 'Imposter Words',
				short_name: 'Imposter',
				description: 'A social deduction word game',
				start_url: '/',
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
			devOptions: {
				enabled: true,
				type: 'module'
			}
		})
	]
});