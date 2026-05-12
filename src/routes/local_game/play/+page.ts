import { fallbackWordPairs } from '$lib/data/wordPairs';
import { redirect } from '@sveltejs/kit';
import { browser } from '$app/environment';
import { supabase } from '$lib/supabase';

const CACHE_KEY = 'cached_word_pairs';
const CACHE_TTL = 1000 * 60 * 60 * 24; // 24 hours

export async function load() {
    if (!browser) return {};
    
    const players: string[] = JSON.parse(localStorage.getItem('local_players') ?? '[]');
    if (players.length < 4) redirect(302, '/local_game/settings');

    const cached = localStorage.getItem(CACHE_KEY);
    const cachedAt = localStorage.getItem(CACHE_KEY + '_ts');
    const isValid = cached && cachedAt && (Date.now() - Number(cachedAt)) < CACHE_TTL;

    let wordPairs = fallbackWordPairs;

    // try cache, fallback to database, fallback to hardcoded
    if (isValid) wordPairs = JSON.parse(cached);
    else {
        try {
            const { data, error } = await supabase
                .from('words')
                .select('civilian_word, imposter_word')
                .limit(1000);
            
            if (data && !error) {
                wordPairs = data;
                localStorage.setItem(CACHE_KEY, JSON.stringify(data));
                localStorage.setItem(CACHE_KEY + '_ts', String(Date.now()));
            }
        }
        catch { ; }
    }

    // pick a random pair
    const pair = wordPairs[Math.floor(Math.random() * wordPairs.length)];

    return { players, pair };
}