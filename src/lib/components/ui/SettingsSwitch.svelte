<script lang='ts'>
    import { Switch } from 'm3-svelte';

    let {
        label,
        meaning,
        disabled = false,
        active = $bindable()
    }: { label: string, meaning?: string, disabled?: boolean, active: boolean } = $props();
</script>


<!-- HTML -->
<div class = 'wrapper' class:disabled>
    <div class = 'textContainer'>
        <span>{label}</span>
        {#if meaning} <span>{meaning}</span> {/if}
    </div>

    <label>
        <Switch bind:checked={active} {disabled} />
    </label>
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: row;
        justify-content: space-between;
        align-items: center;
    }

    .wrapper.disabled {
        opacity: 0.5;
        pointer-events: none;
    }

    .textContainer {
        height: 100%;

        display: flex;
        flex-direction: column;
        justify-content: space-between;
        align-items: flex-start;
    }
</style>