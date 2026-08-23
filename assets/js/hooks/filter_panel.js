let openFilterPanel = null

const FilterPanel = {
  mounted() {
    this._open = false
    this._panel = this.el.querySelector('[data-panel]')
    this._toggle = this.el.querySelector('[data-toggle]')

    this._toggleClick = (e) => {
      e.stopPropagation()
      this._open ? this._close() : this._openPanel()
    }
    this._toggle.addEventListener('click', this._toggleClick)

    this._outside = (e) => {
      if (this._open && !this.el.contains(e.target) && !this._panel?.contains(e.target)) {
        this._close()
      }
    }
    document.addEventListener('mousedown', this._outside)

    this._keydown = (e) => {
      if (e.key === 'Escape' && this._open) this._close()
    }
    document.addEventListener('keydown', this._keydown)

    this._checkboxChange = (e) => {
      if (e.target.matches('[data-select-all]')) {
        this._panel.querySelectorAll('[data-select-option]').forEach(input => {
          input.checked = e.target.checked
        })
        return
      }

      if (e.target.matches('[data-select-option]')) {
        const selectAll = this._panel.querySelector('[data-select-all]')
        if (!selectAll) return

        const options = [...this._panel.querySelectorAll('[data-select-option]')]
        selectAll.checked = options.length > 0 && options.every(input => input.checked)
      }
    }
    this._panel?.addEventListener('change', this._checkboxChange)

    this._panelClick = (e) => {
      if (e.target.closest('[data-close-panel]')) {
        this._close()
      }
    }
    this._panel?.addEventListener('click', this._panelClick)
  },

  updated() {
    if (this._open) {
      this._reposition()
    }
  },

  destroyed() {
    this._close()
    this._toggle?.removeEventListener('click', this._toggleClick)
    this._panel?.removeEventListener('change', this._checkboxChange)
    this._panel?.removeEventListener('click', this._panelClick)
    document.removeEventListener('mousedown', this._outside)
    document.removeEventListener('keydown', this._keydown)
    if (this._panel && this._panel.parentNode === document.body) {
      document.body.removeChild(this._panel)
    }
  },

  _openPanel() {
    if (openFilterPanel && openFilterPanel !== this) openFilterPanel._close()
    openFilterPanel = this

    this._open = true
    if (!this._panelOriginalParent) {
      this._panelOriginalParent = this._panel.parentNode
      this._panelNextSibling = this._panel.nextSibling
    }
    document.body.appendChild(this._panel)

    this._panel.classList.remove('row-menu-closed')
    this._panel.classList.add('row-menu-open')
    this._reposition()
  },

  _reposition() {
    const rect = this._toggle.getBoundingClientRect()
    const pad = 8

    this._panel.style.visibility = 'hidden'
    const panelW = this._panel.offsetWidth
    const panelH = this._panel.offsetHeight

    const spaceBelow = window.innerHeight - rect.bottom - pad
    const spaceAbove = rect.top - pad
    const top = spaceBelow >= panelH || spaceBelow >= spaceAbove
      ? rect.bottom + 4
      : rect.top - panelH - 4

    const left = Math.min(Math.max(rect.left, pad), window.innerWidth - panelW - pad)

    this._panel.style.top = top + 'px'
    this._panel.style.left = left + 'px'
    this._panel.style.right = 'auto'
    this._panel.style.visibility = ''
  },

  _close() {
    if (openFilterPanel === this) openFilterPanel = null
    this._open = false
    if (this._panel) {
      this._panel.classList.remove('row-menu-open')
      this._panel.classList.add('row-menu-closed')
      if (this._panelOriginalParent) {
        this._panelOriginalParent.insertBefore(this._panel, this._panelNextSibling || null)
        this._panelOriginalParent = null
        this._panelNextSibling = null
      }
    }
  },
}

export default FilterPanel

