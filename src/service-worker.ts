/// <reference lib="webworker" />

import { clientsClaim } from 'workbox-core';

import {
    precacheAndRoute,
    cleanupOutdatedCaches,
    createHandlerBoundToURL
} from 'workbox-precaching';

import { NavigationRoute, registerRoute } from 'workbox-routing';

declare let self: ServiceWorkerGlobalScope & {
	__WB_MANIFEST: Array<{ url: string; revision?: string | null}>;
};

self.skipWaiting();
clientsClaim();

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();

// Handle navigations with the App Shell (root page)
registerRoute(
    new NavigationRoute(
        async (params) => {
            try {
                // Try to serve the cached root page ('/')
                return await createHandlerBoundToURL('/')(params);
            } catch (error) {
                // Fallback to index.html if '/' is not in manifest for some reason
                try {
                    return await createHandlerBoundToURL('index.html')(params);
                } catch (innerError) {
                    // If neither are precached, just fetch from network
                    return fetch(params.request);
                }
            }
        }
    )
);

self.addEventListener('push', (event) => {
	event.waitUntil(
		(async () => {
			const data = event.data?.json() ?? {};

			await self.registration.showNotification(data.title ?? 'Imposter Words', {
				body: data.body ?? 'A match update is available.',
				icon: '/icons/icon-192.png',
				badge: '/icons/icon-192.png',
				data: data.data ?? {}
			});
		})()
	);
});

self.addEventListener('notificationclick', (event) => {
	event.notification.close();

	event.waitUntil(
		(async () => {
			const url = event.notification.data?.url ?? '/home';
			const clients = await self.clients.matchAll({
				type: 'window',
				includeUncontrolled: true
			});

			for (const client of clients) {
				if ('focus' in client) {
					await client.focus();
					if ('navigate' in client) {
						await client.navigate(url);
					}
					return;
				}
			}

			await self.clients.openWindow(url);
		})()
	);
});