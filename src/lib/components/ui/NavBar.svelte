<script lang='ts'>
    import type { Component } from 'svelte';

    interface NavItem {
        label: string;
        icon: Component;
    }

    let { items }: { items: NavItem[] } = $props();
</script>


{#snippet NavBarItem(label: string, Icon: Component)}
    <div class = 'navBarItem'>
        <Icon class="w-6 h-6" />
        <span>{label}</span>
    </div>
{/snippet}


<div class = 'navbar'>
    {#each items as item}
        {@render NavBarItem(item.label, item.icon)}
    {/each}
</div>


<style>
    .navbar {
        width: 100%;
        height: 10vh;
        
        display: flex;
        flex-direction: row;
        justify-content: space-around;
        align-items: center;
        background-color: bisque;
    }

    .navBarItem {
        height: 100%;
        width: 20vw;
        
        display: flex;
        flex-direction: column;
        justify-content: space-around;
        align-items: center;
        background-color: aqua;
    }
</style>