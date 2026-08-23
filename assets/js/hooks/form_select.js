const FormSelect = {
  mounted() {
    this._input = this.el.querySelector('[data-input]')
    this._label = this.el.querySelector('[data-label]')
    this._toggle = this.el.querySelector('[data-toggle]')
    this._panel = this.el.querySelector('[data-panel]')
    this._open = false

    this._syncLabel()

    this._toggle.addEventListener('click', (e) => {
      e.stopPropagation()
      if (this._open) {
        this._close()
      } else {
        this._openPanel()
      }
    })

    this.el.querySelectorAll('[data-option]').forEach((opt) => {
      opt.addEventListener('click', (e) => {
        e.stopPropagation()
        this._input.value = opt.dataset.value
        this._syncLabel()
        this._close()
        this._input.dispatchEvent(new Event('change', { bubbles: true }))
      })
    })

    this._outside = (e) => {
      if (this._open && !this.el.contains(e.target)) this._close()
    }
    document.addEventListener('mousedown', this._outside)

    this._keydown = (e) => {
      if (e.key === 'Escape' && this._open) this._close()
    }
    document.addEventListener('keydown', this._keydown)
  },

  updated() {
    this._syncLabel()
    if (this._open) this._panel.classList.remove('hidden')
  },

  destroyed() {
    document.removeEventListener('mousedown', this._outside)
    document.removeEventListener('keydown', this._keydown)
  },

  _syncLabel() {
    const val = String(this._input.value || '')
    const opt = this.el.querySelector('[data-option][data-value="' + val + '"]')
    const prompt = this.el.dataset.prompt || '—'
    if (opt && val !== '') {
      this._label.textContent = opt.dataset.label
      this._label.classList.remove('text-base-content/60')
      this._label.classList.add('text-base-content')
    } else {
      this._label.textContent = prompt
      this._label.classList.add('text-base-content/60')
      this._label.classList.remove('text-base-content')
    }
  },

  _openPanel() {
    this._open = true
    this._panel.classList.remove('hidden')
  },

  _close() {
    this._open = false
    this._panel.classList.add('hidden')
  },
}

export default FormSelect
