let openMenu = null

// Close any open menu on LiveView patch/navigate
window.addEventListener('phx:page-loading-start', () => {
  if (openMenu) openMenu._close()
})

const RowMenu = {
  mounted() {
    this._open = false
    this._panel = this.el.querySelector('[data-panel]')
    this._toggle = this.el.querySelector('[data-toggle]')

    if (!this._toggle || !this._panel) return
    this._panelStartsHidden = this._panel.classList.contains('hidden')

    if (!this._panel.classList.contains('row-menu-open') && !this._panel.classList.contains('row-menu-closed')) {
      this._panel.classList.add('row-menu-closed')
    }

    this._toggleClick = (e) => {
      e.stopPropagation()
      this._open ? this._close() : this._openMenu()
    }
    this._toggle.addEventListener('click', this._toggleClick)

    this._panelClick = (e) => {
      if (e.target.closest('a, button')) this._close()
    }
    this._panel.addEventListener('click', this._panelClick)

    this._outside = (e) => {
      if (this._open && !this.el.contains(e.target) && !this._panel?.contains(e.target)) this._close()
    }
    document.addEventListener('mousedown', this._outside)

    this._keydown = (e) => {
      if (e.key === 'Escape' && this._open) this._close()
    }
    document.addEventListener('keydown', this._keydown)
  },

  updated() {
    this._close()
  },

  destroyed() {
    this._close()
    this._toggle?.removeEventListener('click', this._toggleClick)
    this._panel?.removeEventListener('click', this._panelClick)
    document.removeEventListener('mousedown', this._outside)
    document.removeEventListener('keydown', this._keydown)
    // If panel was teleported, remove it from body
    if (this._panel && this._panel.parentNode === document.body) {
      document.body.removeChild(this._panel)
    }
  },

  _openMenu() {
    if (openMenu && openMenu !== this) openMenu._close()

    openMenu = this
    this._open = true
    this._toggle.setAttribute('aria-expanded', 'true')

    // Teleport panel to body to escape any CSS transform containing block
    // (e.g. a drawer/modal with translate-x animation)
    if (!this._panelOriginalParent) {
      this._panelOriginalParent = this._panel.parentNode
      this._panelNextSibling = this._panel.nextSibling
    }
    document.body.appendChild(this._panel)

    const rect = this._toggle.getBoundingClientRect()
    const viewportPadding = 8

    // Position before revealing so offsetWidth is correct
    this._panel.style.visibility = 'hidden'
    this._panel.classList.remove('hidden')
    this._panel.classList.remove('row-menu-closed')
    this._panel.classList.add('row-menu-open')

    const panelWidth = this._panel.offsetWidth
    const panelHeight = this._panel.offsetHeight
    const spaceBelow = window.innerHeight - rect.bottom - viewportPadding
    const spaceAbove = rect.top - viewportPadding

    // Flip upward if not enough space below
    const top = spaceBelow >= panelHeight || spaceBelow >= spaceAbove
      ? rect.bottom + 4
      : rect.top - panelHeight - 4

    const centeredLeft = rect.left + rect.width / 2 - panelWidth / 2
    const maxLeft = window.innerWidth - panelWidth - viewportPadding
    const left = Math.min(Math.max(centeredLeft, viewportPadding), maxLeft)

    this._panel.style.top = top + 'px'
    this._panel.style.left = left + 'px'
    this._panel.style.right = 'auto'
    this._panel.style.visibility = ''
  },

  _close() {
    if (openMenu === this) openMenu = null
    this._open = false
    if (this._toggle) this._toggle.setAttribute('aria-expanded', 'false')
    if (this._panel) {
      this._panel.classList.remove('row-menu-open')
      this._panel.classList.add('row-menu-closed')

      // Restore panel to original DOM position
      if (this._panelOriginalParent) {
        this._panelOriginalParent.insertBefore(this._panel, this._panelNextSibling || null)
        this._panelOriginalParent = null
        this._panelNextSibling = null
      }

      if (this._panelStartsHidden) this._panel.classList.add('hidden')
    }
  },
}

export default RowMenu
