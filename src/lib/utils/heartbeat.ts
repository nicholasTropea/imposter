/**
 * Starts a heartbeat loop that pings the server every 5 seconds to signal
 * that the current player is still active in the game.
 * 
 * Uses `sendBeacon` to ensure the ping is fired reliably even when the page
 * is being unloaded. Should be called inside `onMount` and cleaned up via
 * its returned stop function.
 *
 * @param gameId - The UUID of the game the player is currently in.
 * @returns A cleanup function that stops the heartbeat when called.
 *
 * @example
 * onMount(() => {
 *     const stopHeartbeat = startHeartbeat(data.gameId);
 *     return () => stopHeartbeat();
 * });
 */
export function startHeartbeat(gameId: string): () => void {
    const interval = setInterval(() => {
        navigator.sendBeacon(
            '/api/heartbeat',
            new Blob(
                [JSON.stringify({ gameId })],
                { type: 'application/json' }
            )
        );
    }, 5000);

    return () => clearInterval(interval);
}