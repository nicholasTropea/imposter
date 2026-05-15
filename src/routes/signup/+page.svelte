<script lang='ts'>
    import { TextFieldOutlined, Button } from 'm3-svelte';
    import LabeledSwitch from '$components/ui/LabeledSwitch.svelte';
    import { enhance } from '$app/forms';
    import { offline } from '$lib/stores/network';
    import { submitIfOnline } from '$lib/utils/onlineGuard';
    import { auth } from '$lib/stores/auth';
    import type { SubmitFunction } from '@sveltejs/kit';
    import { goto } from '$app/navigation';

    const submitSignup: SubmitFunction = async (input) => {
        const next = await submitIfOnline()(input);

        if (!next) return;

        return async (output) => {
            await next(output);

            if (output.result.type === 'success') {
                await auth.refresh();
                await goto('/home');
            }
        };
    };
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <h1> SIGNUP </h1>

    <form method = 'POST' action = '?/signup' use:enhance = { submitSignup } >
        <TextFieldOutlined label = 'nickname' name = 'nickname' />

        <TextFieldOutlined label = 'email' name = 'email' type = 'email' />

        <TextFieldOutlined label = 'password' name = 'password' type = 'password' />

        <LabeledSwitch label = 'I agree to the terms of service' />

        <Button variant = 'filled' type = 'submit' disabled = { $offline } >
            SIGNUP
        </Button>
    </form>

    <div class = 'toLogin'>
        <span>Already have an account ?</span>
        <a href="/login"> login </a>
    </div>
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: column;
        justify-content: space-around;
        align-items: center;

    }

    form {
        width: 100%;
        height: 40vh;

        display: flex;
        flex-direction: column;
        justify-content: space-around;
        align-items: center;
    }
</style>