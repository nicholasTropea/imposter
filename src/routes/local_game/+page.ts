import { redirect } from "@sveltejs/kit";

export function load() {
    // Just redirect /local_game to /local_game/settings
    return redirect(302, '/local_game/settings');
}