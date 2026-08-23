let openScheduleDropdown = null

const ScheduleDropdown = {
  mounted() {
    this._open = false
    this._panel = this.el.querySelector("[data-panel]")
    this._toggle = this.el.querySelector("[data-toggle]")
    this._ignoreOutsideUntil = 0

    this._toggleClick = event => {
      event.stopPropagation()
      this._open ? this._close() : this._openPanel()
    }
    this._toggle?.addEventListener("click", this._toggleClick)

    this._insideMouseDown = event => {
      event.stopPropagation()
    }
    this.el.addEventListener("mousedown", this._insideMouseDown)

    this._datetimeInteraction = event => {
      if (event.target?.matches?.("input[type='datetime-local']")) {
        this._ignoreOutsideUntil = Date.now() + 1200
        if (this._open) this._showPanel()
      }
    }
    this.el.addEventListener("focusin", this._datetimeInteraction)
    this.el.addEventListener("input", this._datetimeInteraction)
    this.el.addEventListener("change", this._datetimeInteraction)

    this._outside = event => {
      if (!this._open) return
      if (this.el.contains(event.target)) return
      if (Date.now() < this._ignoreOutsideUntil) return
      if (this.el.contains(document.activeElement)) return

      this._close()
    }
    document.addEventListener("mousedown", this._outside)

    this._keydown = event => {
      if (event.key === "Escape" && this._open) this._close()
    }
    document.addEventListener("keydown", this._keydown)
  },

  destroyed() {
    this._close()
    this._toggle?.removeEventListener("click", this._toggleClick)
    this.el.removeEventListener("mousedown", this._insideMouseDown)
    this.el.removeEventListener("focusin", this._datetimeInteraction)
    this.el.removeEventListener("input", this._datetimeInteraction)
    this.el.removeEventListener("change", this._datetimeInteraction)
    document.removeEventListener("mousedown", this._outside)
    document.removeEventListener("keydown", this._keydown)
  },

  updated() {
    if (this._open) this._showPanel()
  },

  _openPanel() {
    if (openScheduleDropdown && openScheduleDropdown !== this) openScheduleDropdown._close()
    openScheduleDropdown = this

    this._open = true
    this._showPanel()
  },

  _showPanel() {
    this._panel?.classList.remove("hidden")
  },

  _close() {
    if (openScheduleDropdown === this) openScheduleDropdown = null
    this._open = false
    this._panel?.classList.add("hidden")
  },
}

export default ScheduleDropdown
