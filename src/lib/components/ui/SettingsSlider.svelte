<script lang='ts'>
    import { Slider } from 'm3-svelte';

    let { label, initial = $bindable() }: { label: string, initial: number } = $props();
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <div class = 'header'>
        <span>{label}</span>
        <span>{initial}</span>
    </div>

    <Slider bind:value={initial} endStops={false} min={0} max={100} step={1}/>
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: space-around;
    }

    .header {
        width: 100%;

        display: flex;
        flex-direction: row;
        justify-content: space-between;
        align-items: center;
    }
</style>