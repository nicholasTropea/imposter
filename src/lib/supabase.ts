import { createBrowserClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

import type { Database } from '$lib/types/supabase';


/**
 * Supabase browser client for client-side usage.
 *
 * This is a singleton instance created with the public anon key and typed
 * against the generated `Database` schema, providing full type safety for
 * all client-side queries.     
 *
 * @remarks
 * Do **not** use this client in server-side files (`+page.server.ts`,
 * `+layout.server.ts`, `+server.ts`). Those should always use
 * `locals.supabase`, which is request-scoped and handles cookie-based
 * session management correctly via `@supabase/ssr`.
 *
 * @example
 * ```ts
 * import { supabase } from '$lib/supabase';
 *
 * const { data } = await supabase.from('settings').select('*');
 * ```
 */
export const supabase = createBrowserClient<Database>(
    PUBLIC_SUPABASE_URL,
    PUBLIC_SUPABASE_ANON_KEY
);