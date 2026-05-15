<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────
    import { Card, TextField, Button, snackbar } from 'm3-svelte';
    import CloseIcon from '~icons/mdi/close';
    import { goto } from '$app/navigation';
    import { browser } from '$app/environment';

    // ── State ──────────────────────────────────────────────────────────────────────────
    let players: string[] = $state<string[]>(
        browser ? JSON.parse(localStorage.getItem('local_players') ?? '[]') : []
    );
    let inputText: string = $state<string>('');
    let inputError: string = $state<string>('');
    
    // ── Sync players to local storage ──────────────────────────────────────────────────
    $effect( () => {
        if (browser) {
            localStorage.setItem('local_players', JSON.stringify(players))
        }
    });
    
    // ── Player Input ───────────────────────────────────────────────────────────────────
    function handlePlayerInput(): void {
        if (inputText.trim() == '') return;
        
        if (players.includes(inputText)) {
            inputError = 'Nickname already used';
            return;
        }

        players.push(inputText);
        inputError = '';
        inputText = '';
    }

    function deletePlayer(nickname: string): void {
        players = players.filter(nick => nick !== nickname);
    }

    function handleGameStart(): void {
        if (players.length < 4) {
            snackbar('Minimum 4 players are required', undefined, true);
            return;
        }

        goto('/local_game/play');
    }
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <div class = 'settingsWrapper'>
        <Card variant = 'filled'>
            <div class = 'cardContent'>
                {#each players as nickname}
                    <Card variant = 'filled'>
                        <div class = 'playerCard'>
                            <span> { nickname } </span>
                            <Button
                                variant = 'outlined'
                                size = 'xs'
                                onclick = { () => deletePlayer(nickname) }
                            >
                                <CloseIcon />
                            </Button>
                        </div>
                    </Card>
                {/each}
    
                <TextField
                    label = "Nickname"
                    bind:value = { inputText }
                    error = { inputError !== '' }
                    oninput = { () => inputError = '' }
                    onkeydown = { (e) => e.key === 'Enter' && handlePlayerInput() }
                    autocomplete = 'off'
                />

                {#if inputError !== ''}
                    <span class = 'errorText'> { inputError } </span>
                {/if}

                <Button variant = 'filled' onclick = { handlePlayerInput } >
                    Add Player
                </Button>
            </div>
        </Card>

        <Button variant = 'filled' onclick = { handleGameStart } >
            Start Game ({ players.length } / 4 minimum)
        </Button>
    </div>
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: column;
        justify-content: space-between;
        align-items: center;
    }

    .settingsWrapper {
        width: 100%;

        display: flex;
        flex: 1;
        flex-direction: column;
        justify-content: space-around;
        align-items: center;
    }

    .cardContent {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        padding: 1rem;
    }

    .playerCard {
        display: flex;
        flex-direction: row;
        justify-content: space-between;
        align-items: center;
    }

    .errorText {
        font-size: 0.75rem;
        color: var(--m3c-error);
        padding-left: 1rem;
        margin-top: -0.5rem;
    }
</style>