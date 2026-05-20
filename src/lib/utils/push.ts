import { PUBLIC_VAPID_KEY } from '$env/static/public';

/**
 * Converts a Base64URL-encoded VAPID public key into the Uint8Array format
 * required by `PushManager.subscribe()`.
 *
 * @param base64Url The Base64URL-encoded public VAPID key.
 * @returns The decoded key as a Uint8Array.
 */
function base64UrlToUint8Array(base64Url: string): Uint8Array {
	const padding = '='.repeat((4 - (base64Url.length % 4)) % 4);
	const base64 = (base64Url + padding).replace(/-/g, '+').replace(/_/g, '/');
	const raw = atob(base64);
	return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)));
}

/**
 * Requests notification permission, creates or reuses a Web Push subscription,
 * and sends it to the server for persistence.
 *
 * This function requires browser support for service workers, the Push API,
 * and the Notifications API. It reuses an existing subscription when available
 * to avoid creating duplicates unnecessarily.
 *
 * @returns A promise that resolves once the subscription has been stored successfully.
 * @throws {Error} If service workers are unsupported, push notifications are unsupported,
 * notification permission is denied, the subscription is incomplete, or the server
 * fails to save the subscription.
 */
export async function subscribeToPush(): Promise<void> {
	if (!('serviceWorker' in navigator)) throw new Error('Service worker not supported');

	if (!('PushManager' in window)) throw new Error('Push notifications not supported');

	if (Notification.permission === 'denied') {
		throw new Error('Notifications are blocked by your browser. Please reset permissions in your browser settings.');
	}

	const permission = await Notification.requestPermission();
	if (permission !== 'granted') throw new Error('Notification permission not granted');

	const registration = await navigator.serviceWorker.ready;

	let subscription = await registration.pushManager.getSubscription();

	if (!subscription) {
		subscription = await registration.pushManager.subscribe({
			userVisibleOnly: true,
			applicationServerKey: base64UrlToUint8Array(PUBLIC_VAPID_KEY) as
                Uint8Array<ArrayBuffer>
		});
	}

	const jsonSub = subscription.toJSON();
	const keys = jsonSub.keys;

	if (!jsonSub.endpoint || !keys?.p256dh || !keys?.auth) {
		throw new Error('Incomplete push subscription');
	}

	const res = await fetch('/api/push_subscription', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			endpoint: jsonSub.endpoint,
			p256dh: keys.p256dh,
			auth: keys.auth,
			userAgent: navigator.userAgent
		})
	});

	if (!res.ok) {
		const data = await res.json().catch(() => null);
		throw new Error(data?.error ?? 'Failed to save push subscription');
	}
}

/**
 * Checks if the current browser already has an active push subscription.
 * 
 * @returns The subscription object if it exists, otherwise null.
 */
export async function getPushSubscription(): Promise<PushSubscription | null> {
    if (!('serviceWorker' in navigator)) return null;
    
    const registration = await navigator.serviceWorker.ready;
    return await registration.pushManager.getSubscription();
}

/**
 * Unsubscribes the current device from push notifications and informs the server.
 */
export async function unsubscribeFromPush(): Promise<void> {
    const subscription = await getPushSubscription();
    if (!subscription) return;

    // Unsubscribe from browser
    await subscription.unsubscribe();

    // Inform server
    const res = await fetch('/api/push_subscription', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ endpoint: subscription.endpoint })
    });

    if (!res.ok) {
        const data = await res.json().catch(() => null);
        throw new Error(data?.error ?? 'Failed to remove push subscription');
    }
}