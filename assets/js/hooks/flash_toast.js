const FlashToastHook = {
  mounted() {
    this._timer = setTimeout(() => {
      const btn = this.el.querySelector("button")
      if (btn) btn.click()
    }, 4000)
  },
  destroyed() {
    clearTimeout(this._timer)
  },
}

export default FlashToastHook
