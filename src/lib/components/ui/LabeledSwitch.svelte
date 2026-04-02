<script lang='ts'>
    import { Switch } from 'm3-svelte';

    let { label }: { label: string } = $props();
    let isChecked = $state(false);
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <label>
        <Switch bind:checked={isChecked} />
    </label>
    
    <span>{label}</span>
</div>


<style>
    .wrapper {
        display: flex;
        flex-direction: row;
        justify-content: center;
        align-items: center;
        gap: 2vw;
    }
</style>