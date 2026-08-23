const RangeInputHook = {
  mounted() {
    this.updateValue = this.updateValue.bind(this)
    this.handleInput = this.handleInput.bind(this)

    this.bindInput()
  },

  updated() {
    this.bindInput()
  },

  destroyed() {
    this.input?.removeEventListener("input", this.handleInput, true)
  },

  bindInput() {
    const nextInput = this.el.querySelector('input[type="range"]')

    if (this.input !== nextInput) {
      this.input?.removeEventListener("input", this.handleInput, true)
      this.input = nextInput
      this.input?.addEventListener("input", this.handleInput, true)
    }

    this.valueLabel = this.el.querySelector("[data-range-value]")
    this.updateValue()
  },

  handleInput(event) {
    this.updateValue()
    event.stopImmediatePropagation()
  },

  updateValue() {
    if (!this.input || !this.valueLabel) return

    const suffix = this.el.dataset.suffix || ""
    const min = Number(this.input.min || 0)
    const max = Number(this.input.max || 100)
    const value = Number(this.input.value || min)
    const percent = max === min ? 0 : ((value - min) / (max - min)) * 100

    this.valueLabel.textContent = `${this.input.value}${suffix}`
    this.input.style.setProperty("--range-fill", `${Math.min(100, Math.max(0, percent))}%`)
  },
}

export default RangeInputHook
