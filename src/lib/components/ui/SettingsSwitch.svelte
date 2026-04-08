<script lang='ts'>
    import { Switch } from 'm3-svelte';

    let {
        label,
        meaning,
        active = $bindable()
    }: { label: string, meaning?: string, active: boolean } = $props();
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <div class = 'textContainer'>
        <span>{label}</span>
        {#if meaning} <span>{meaning}</span> {/if}
    </div>

    <label>
        <Switch bind:checked={active} />
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

    .textContainer {
        height: 100%;

        display: flex;
        flex-direction: column;
        justify-content: space-between;
        align-items: flex-start;
    }
</style>