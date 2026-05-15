<script lang='ts'>
    import { offline } from '$lib/stores/network';
</script>

<!-- HTML -->
{#if $offline}
    <div class = 'offlinePill' role = 'status' aria-live = 'polite'>
        Offline
    </div>
{/if}


<style>
    .offlinePill {
        position: fixed;
        top: 1rem;
        left: 50%;
        transform: translateX(-50%);
        z-index: 1000;

        display: flex;
        align-items: center;

        padding: 0.7rem 1rem;
        border-radius: 9999px;

        background-color: rgba(255, 0, 0, 0.3);
        color: rgb(231, 231, 231);
        border: 1px solid rgb(215, 0, 0);

        font-size: 0.95rem;
        letter-spacing: 0.05rem;

        box-shadow:
			0 8px 24px rgba(0, 0, 0, 0.18),
			0 2px 8px rgba(0, 0, 0, 0.12);

		backdrop-filter: blur(10px);
		-webkit-backdrop-filter: blur(10px);
    }
</style>