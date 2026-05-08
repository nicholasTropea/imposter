import type { Database } from './supabase';

export type CastVoteArgs = Omit<
    Database['public']['Functions']['cast_vote']['Args'],
    'p_target_id'
> & {
    p_target_id: string | null;
};