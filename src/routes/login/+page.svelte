<script>
    import { TextFieldOutlined, Button } from 'm3-svelte';

    import LabeledSwitch from '$components/ui/LabeledSwitch.svelte';
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <h1>LOGIN</h1>

    <TextFieldOutlined label = 'email' />
    <TextFieldOutlined label = 'password' />
    <Button variant='filled'> LOGIN </Button>

    <div class = 'toLogin'>
        <span>Don't have an account ?</span>
        <a href="/signup"> signup </a>
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