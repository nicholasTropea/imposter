<script lang="ts">

    import { Button } from 'm3-svelte';
    import { goto } from '$app/navigation';

    async function handleHomeClick() { await goto('/home'); }
    async function handleSignupClick() { await goto('/signup'); }
    
    let variant: "elevated" | "filled" | "tonal" | "outlined" | "text" = $state("filled");
    let square = $state(false);
    const sizes = ["xs", "s", "m", "l", "xl"] as const;
    let sizeIndex = $state(1);
</script>

LANDING PAGE

<Button
    {variant}
    {square}
    size={sizes[sizeIndex]}
    onclick={handleHomeClick}
>
    go to home
</Button>

<Button onclick={handleSignupClick} >
    go to signup
</Button>