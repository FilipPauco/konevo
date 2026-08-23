import flatpickr from "flatpickr"

const DateRangePicker = {
  mounted() {
    this._fp = null
    this._open = false
    this._init()
  },

  updated() {
    // Sync flatpickr selection when server clears/changes dates via URL push_patch
    if (this._fp) {
      const from = this.el.dataset.from || ""
      const to = this.el.dataset.to || ""
      if (!from && !to) {
        this._fp.clear()
      } else if (from && to) {
        const current = this._fp.selectedDates
        const fmtCurrent =
          current.length === 2
            ? [this._fmt(current[0]), this._fmt(current[1])]
            : []
        if (fmtCurrent[0] !== from || fmtCurrent[1] !== to) {
          this._fp.setDate([from, to], false)
        }
      }
    }
  },

  destroyed() {
    if (this._fp) { this._fp.destroy(); this._fp = null }
    if (this._outsideHandler) {
      document.removeEventListener("mousedown", this._outsideHandler)
    }
  },

  _init() {
    const trigger = this.el.querySelector("[data-trigger]")
    const panel = this.el.querySelector("[data-panel]")
    const calendarEl = this.el.querySelector("[data-calendar]")
    const fromStr = this.el.dataset.from || ""
    const toStr = this.el.dataset.to || ""

    // Inline range flatpickr
    this._fp = flatpickr(calendarEl, {
      mode: "range",
      inline: true,
      dateFormat: "Y-m-d",
      monthSelectorType: "static",
      defaultDate: [fromStr, toStr].filter(Boolean),
      onChange: (selectedDates) => {
        if (selectedDates.length === 2) {
          const from = this._fmt(selectedDates[0])
          const to = this._fmt(selectedDates[1])
          this.pushEvent("filter_date_range", { from, to })
          this._closePanel(panel)
        }
      },
    })

    // Toggle trigger
    trigger.addEventListener("click", (e) => {
      e.stopPropagation()
      if (this._open) {
        this._closePanel(panel)
      } else {
        this._openPanel(panel)
        this._highlightActivePreset()
      }
    })

    // Close on outside click
    this._outsideHandler = (e) => {
      if (!this.el.contains(e.target)) this._closePanel(panel)
    }
    document.addEventListener("mousedown", this._outsideHandler)

    // Preset buttons
    this.el.querySelectorAll("[data-preset]").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        const { from, to } = this._computePreset(btn.dataset.preset)
        if (from && to) {
          this._fp.setDate([from, to], false)
          this.pushEvent("filter_date_range", { from, to })
        } else {
          this._fp.clear()
          this.pushEvent("filter_date_range", { from: "", to: "" })
        }
        this._highlightActivePreset(from, to)
        this._closePanel(panel)
      })
    })

    // Server can clear the picker (e.g. "clear all filters")
    this.handleEvent("date_range:clear", () => {
      if (this._fp) this._fp.clear()
    })
  },

  _openPanel(panel) {
    panel.classList.remove("hidden")
    this._open = true
  },

  _closePanel(panel) {
    panel.classList.add("hidden")
    this._open = false
  },

  _highlightActivePreset(overrideFrom, overrideTo) {
    const from = overrideFrom !== undefined ? overrideFrom : (this.el.dataset.from || "")
    const to = overrideTo !== undefined ? overrideTo : (this.el.dataset.to || "")
    this.el.querySelectorAll("[data-preset]").forEach((btn) => {
      const { from: pFrom, to: pTo } = this._computePreset(btn.dataset.preset)
      btn.classList.toggle("date-preset-active", pFrom === from && pTo === to)
    })
  },

  _fmt(date) {
    const y = date.getFullYear()
    const m = String(date.getMonth() + 1).padStart(2, "0")
    const d = String(date.getDate()).padStart(2, "0")
    return `${y}-${m}-${d}`
  },

  _computePreset(preset) {
    const today = new Date()
    const y = today.getFullYear()
    const mo = today.getMonth()
    const d = today.getDate()

    switch (preset) {
      case "today":
        return { from: this._fmt(today), to: this._fmt(today) }

      case "this_week": {
        const day = today.getDay() // 0=Sun
        const monday = new Date(y, mo, d - (day === 0 ? 6 : day - 1))
        return { from: this._fmt(monday), to: this._fmt(today) }
      }

      case "last_week": {
        const day = today.getDay()
        const thisMonday = new Date(y, mo, d - (day === 0 ? 6 : day - 1))
        const lastMonday = new Date(thisMonday.getFullYear(), thisMonday.getMonth(), thisMonday.getDate() - 7)
        const lastSunday = new Date(thisMonday.getFullYear(), thisMonday.getMonth(), thisMonday.getDate() - 1)
        return { from: this._fmt(lastMonday), to: this._fmt(lastSunday) }
      }

      case "this_month":
        return { from: this._fmt(new Date(y, mo, 1)), to: this._fmt(new Date(y, mo + 1, 0)) }

      case "last_month":
        return { from: this._fmt(new Date(y, mo - 1, 1)), to: this._fmt(new Date(y, mo, 0)) }

      case "this_year":
        return { from: this._fmt(new Date(y, 0, 1)), to: this._fmt(new Date(y, 11, 31)) }

      case "last_year":
        return { from: this._fmt(new Date(y - 1, 0, 1)), to: this._fmt(new Date(y - 1, 11, 31)) }

      case "all_time":
      default:
        return { from: "", to: "" }
    }
  },
}

export default DateRangePicker
