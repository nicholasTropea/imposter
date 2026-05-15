import { snackbar } from 'm3-svelte';
import { offline } from '$lib/stores/network';
import { goto } from '$app/navigation';
import type { SubmitFunction } from '@sveltejs/kit';


export async function guardOnline(message = 'You are offline.'): Promise<boolean> {
    const online = await offline.assertOnline();

    if (!online) {
        snackbar(message, undefined, true);
        return false;
    }

    return true;
}


export async function gotoIfOnline(
    path: string,
    message = 'You are offline.'
): Promise<boolean> {
    const ok = await guardOnline(message);

    if (!ok) return false;

    await goto(path);
    return true;
}


export function submitIfOnline(message = 'You are offline.'): SubmitFunction {
    return async ({ cancel }) => {
        const ok = await guardOnline(message);

        if (!ok) {
            cancel();
            return;
        }

        return async ({ update }) => { await update(); }
    }
}