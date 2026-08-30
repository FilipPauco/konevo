const CollapsiblePanelHook = {
  mounted() {
    this.toggle = this.el.querySelector("[data-collapsible-toggle]")
    this.open = this.el.dataset.open === "true"
    this.handleToggle = () => {
      this.open = !this.open
      this.el.dataset.open = String(this.open)
      this.toggle?.setAttribute("aria-expanded", String(this.open))
    }

    this.toggle?.addEventListener("click", this.handleToggle)
  },

  updated() {
    this.el.dataset.open = String(this.open)
    this.toggle?.setAttribute("aria-expanded", String(this.open))
  },

  destroyed() {
    this.toggle?.removeEventListener("click", this.handleToggle)
  },
}

export default CollapsiblePanelHook
