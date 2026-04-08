let dark = $state(false); // shared state

export const themeStore = {
    get dark() { return dark },  // anyone can read
    set dark(v: boolean) { dark = v } // anyone can write
};