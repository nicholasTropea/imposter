import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { createServerClient } from '@supabase/ssr';

import type { Handle } from '@sveltejs/kit';
import type { Database } from '$lib/types/supabase';

/**
 * SvelteKit server hook that runs on every request.
 *
 * Attaches a Supabase server client and a safe session getter to `event.locals`,
 * making them available in all `+page.server.ts` load functions and actions.
 *
 * - `locals.supabase` — a request-scoped Supabase client that reads/writes
 *   cookies for session management.
 * - `locals.safeGetSession` — validates the session server-side via `getUser()`
 *   instead of trusting the JWT from `getSession()` alone, preventing spoofed
 *   sessions from being treated as authenticated.
 * 
 * @throws {Error} If the supabase client fails to initialize.
 *
 * @param event - The SvelteKit request event.
 * @param  resolve - Resolves the request into a response.
 * @returns The resolved HTTP response.
 *
 */
export const handle: Handle = async ({ event, resolve }) => {
    /**
     * Request-scoped Supabase client for server-side usage.
     *
     * Created fresh on every request using the public anon key, with cookie
     * handlers wired to SvelteKit's `event.cookies` so the client can
     * automatically read, set, and refresh the Supabase session cookies
     * (`sb-access-token`, `sb-refresh-token`) on each request.
     *
     * `path: '/'` ensures session cookies are sent on all routes, not just
     * the current path.
     *
     * Should only be used server-side (load functions, actions, hooks).
     * For client-side usage, use the browser Supabase client instead.
     */
    event.locals.supabase = createServerClient<Database>(
        PUBLIC_SUPABASE_URL,
        PUBLIC_SUPABASE_ANON_KEY,
        {
            cookies: {
                getAll: () => event.cookies.getAll(),
                setAll: (cookiesToSet) => {
                    cookiesToSet.forEach(({ name, value, options }) =>
                        event.cookies.set(name, value, { ...options, path: '/' })
                    )
                }
            }
        }
    );

    /**
     * Retrieves and validates the current user session server-side.
     *
     * Two-step process:
     * 1. `getSession()` — fast local JWT decode to check if a session exists.
     * 2. `getUser()` — network request to Supabase to cryptographically verify
     *    the JWT is genuine and has not been tampered with.
     *
     * Using `getSession()` alone is unsafe on the server, as it trusts the
     * JWT payload without verifying it against Supabase's auth server.
     *
     * @returns A verified `{ session, user }` pair, or `{ session: null, user: null }`
     * if unauthenticated, the token is expired, or validation fails.
     */
    event.locals.safeGetSession = async () => {
        const { data: { session } } = await event.locals.supabase.auth.getSession();

        if (!session) return { session: null, user: null };

        const { data: { user }, error } = await event.locals.supabase.auth.getUser();
        if (error) return { session: null, user: null };

        return { session, user };
    };

    return resolve(event, {
        filterSerializedResponseHeaders: (name) =>
            name === 'content-range' || name === 'x-supabase-api-version'
    });
};