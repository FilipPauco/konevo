import flatpickr from "flatpickr"

const Flatpickr = {
  mounted() {
    this._initFlatpickr()

    // Server can push "flatpickr:clear" with {id: "my-id"} or {id: "*"} to clear this picker
    this.handleEvent("flatpickr:clear", ({ id }) => {
      if (id === "*" || id === this.el.id) {
        if (this._fp) this._fp.clear()
      }
    })
  },

  // Only called when NOT wrapped in phx-update="ignore"
  updated() {
    if (this._fp) {
      const incoming = this.el.value
      const current = this._fp.selectedDates.length > 0
        ? this._fp.formatDate(this._fp.selectedDates[0], this._fp.config.dateFormat)
        : ""
      if (current !== incoming) {
        this._fp.setDate(incoming || "", false)
      }
    }
  },

  destroyed() {
    if (this._fp) {
      this._fp.destroy()
      this._fp = null
    }
  },

  _initFlatpickr() {
    let opts = {}
    try {
      opts = JSON.parse(this.el.dataset.flatpickrOpts || "{}")
    } catch (_) {}

    const pushEventName = this.el.dataset.pushEvent
    const pushKey = this.el.dataset.pushKey || "date"

    this._fp = flatpickr(this.el, {
      ...opts,
      onChange: (selectedDates, dateStr) => {
        if (pushEventName) {
          // Reliable LiveView path: pushEvent to server, server push_patches URL
          this.pushEvent(pushEventName, { [pushKey]: dateStr })
        } else {
          // Form-based fallback: dispatch events so phx-change picks them up
          this.el.value = dateStr
          this.el.dispatchEvent(new Event("input", { bubbles: true }))
          this.el.dispatchEvent(new Event("change", { bubbles: true }))
        }
      },
    })
  },
}

export default Flatpickr
