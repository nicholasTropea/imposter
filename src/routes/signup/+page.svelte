<script>
    import { TextFieldOutlined, Button } from 'm3-svelte';
    import LabeledSwitch from '$components/ui/LabeledSwitch.svelte';
    import { enhance } from '$app/forms';
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <h1>SIGNUP</h1>

    <form method = 'POST' action = '?/signup' use:enhance>
        <TextFieldOutlined label = 'nickname' name='nickname' />
        <TextFieldOutlined label = 'email' name='email' />
        <TextFieldOutlined label = 'password' name='password' />
        <LabeledSwitch label = 'I agree to the terms of service'/>
        <Button variant='filled' type='submit'> SIGNUP </Button>
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