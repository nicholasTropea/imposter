import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { functionsMixins } from "vite-plugin-functions-mixins";

import Icons from 'unplugin-icons/vite';

export default defineConfig({
	plugins: [
		sveltekit(),
		Icons({
			compiler: 'svelte'
		}),
		functionsMixins({ deps: ["m3-svelte"] })
	]
});
