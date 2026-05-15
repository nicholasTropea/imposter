/*
* Performs a "real" connectivity check instead of relying only on
* navigator.onLine, because navigator.onLine can say "true" even when
* the internet or the backend is not actually reachable.
*/
export async function isEffectivelyOffline(): Promise<boolean> {
    /*
     * Fast path:
     * if the browser itself already knows there is no network,
     * immediately return true.
     */
    if (!navigator.onLine) return true;

    /*
     * If navigator.onLine is true, still do not fully trust it.
     * Send a very small request to Supabase to verify that a real
     * network request can succeed.
     *
     * Why `HEAD`?
     * - it asks only for headers, not the full response body
     * - it is lighter than GET
     *
     * Why `cache: 'no-store'`?
     * - a cached response could trick it into thinking
     *   the network is available
     */
    try {
        const res = await fetch('https://rsimwvkiyhpfpjpqhche.supabase.co/rest/v1', {
            method: 'HEAD',
            cache: 'no-store'
        });

        return false;
    }

    /*
     * Any fetch error means the request could not be completed,
     * so from the app's point of view it should behave as offline.
     */
    catch { return true; }
}
