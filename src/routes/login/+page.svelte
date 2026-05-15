<script lang='ts'>
	import { TextFieldOutlined, Button } from 'm3-svelte';
	import { enhance } from '$app/forms';
	import { offline } from '$lib/stores/network';
	import { submitIfOnline } from '$lib/utils/onlineGuard';
	import { auth } from '$lib/stores/auth';
	import type { SubmitFunction } from '@sveltejs/kit';
    import { goto } from '$app/navigation';

	const submitLogin: SubmitFunction = async (input) => {
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

<div class = 'wrapper'>
	<h1> LOGIN </h1>

	<form method = 'POST' action = '?/login' use:enhance = { submitLogin } >
		<TextFieldOutlined label = 'email' name = 'email' type = 'email' />

		<TextFieldOutlined label = 'password' name = 'password' type = 'password' />

		<Button variant = 'filled' type = 'submit' disabled = { $offline } >
			LOGIN
		</Button>
	</form>

	<div class = 'toLogin'>
		<span> Don't have an account ? </span>
		<a href = '/signup'> signup </a>
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
		height: 32vh;

		display: flex;
		flex-direction: column;
		justify-content: space-around;
		align-items: center;
	}
</style>