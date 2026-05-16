<script lang='ts'>
    import { Button } from 'm3-svelte';
    import { goto } from '$app/navigation';
    import { offline } from '$lib/stores/network';

    function retry() { location.reload(); }
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <div class = 'content'>
        {#if $offline}
            <span> You are offline. Ranked matchmaking requires connection. </span>

            <div class = 'actions'>
                <Button variant = 'filled' onclick = { retry } >
                    Try Again
                </Button>

                <Button variant = 'outlined' onclick = { () => goto('/home') } >
                    Back
                </Button>
            </div>
        {:else}
            <span> Finding the right game... </span>

            <div class = 'actions'>
                <Button variant = 'text' onclick = { () => goto('/home') } >
                    Cancel
                </Button>
            </div>
        {/if}
    </div>
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: row;
        justify-content: center;
        align-items: center;
    }

    .content {
        width: min(100%, 28rem);
        padding: 1.5rem;
        border-radius: 1rem;
        text-align: center;

        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1rem;
    }

    .actions {
        width: 100%;

        display: flex;
        flex-direction: column;
        gap: 0.75rem;
    }

    @media (min-width: 640px) {
        .wrapper {
            padding: 2rem;
        }

        .content {
            padding: 2rem;
        }

        .actions {
            flex-direction: row;
            justify-content: center;
        }
    }
</style>