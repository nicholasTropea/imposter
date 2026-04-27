/// <reference types="unplugin-icons/types/svelte" />

import type { SupabaseClient, Session, User } from "@supabase/supabase-js";
import type { Database } from '$lib/types/supabase';

declare global {
	namespace App {
		interface Locals {
			supabase: SupabaseClient<Database>
			safeGetSession: () => Promise<{session: Session | null; user: User | null }>
		}
	}
}

export {};
