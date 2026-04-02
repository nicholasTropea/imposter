<script lang="ts">

    import { Button } from 'm3-svelte';
    import { goto } from '$app/navigation';

    async function handleHomeClick() { await goto('/home'); }
    async function handleSignupClick() { await goto('/signup'); }
    
    let variant: "elevated" | "filled" | "tonal" | "outlined" | "text" = $state("filled");
    let action: "click" | "link" | "toggle" = $state("click");
    let square = $state(false);
    let iconType: "none" | "left" | "full" = $state("none");
    const sizes = ["xs", "s", "m", "l", "xl"] as const;
    const sizeLabels = ["Extra small", "Small", "Medium", "Large", "Extra large"] as const;
    let sizeIndex = $state(1);
    let enabled = $state(true);
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