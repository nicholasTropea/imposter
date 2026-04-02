<script>
    import { TextFieldOutlined, Button } from 'm3-svelte';

    import LabeledSwitch from '$components/ui/LabeledSwitch.svelte';
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <h1>SIGNUP</h1>

    <TextFieldOutlined label = 'nickname' />
    <TextFieldOutlined label = 'email' />
    <TextFieldOutlined label = 'password' />
    <LabeledSwitch label = 'I agree to the terms of service'/>
    <Button variant='filled'> SIGNUP </Button>

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
</style>