const NameTip = {
  mounted() {
    this._tip = document.createElement('div')
    this._tip.style.cssText = [
      'position:fixed',
      'z-index:9999',
      'display:none',
      'max-width:220px',
      'word-break:break-word',
      'white-space:normal',
      'padding:4px 10px',
      'border-radius:6px',
      'font-size:12px',
      'line-height:1.4',
      'font-weight:500',
      'background:oklch(20% 0 0)',
      'color:oklch(98% 0 0)',
      'box-shadow:0 4px 12px rgba(0,0,0,0.25)',
      'pointer-events:none',
    ].join(';')
    document.body.appendChild(this._tip)

    this._over = (e) => {
      if (e.pointerType === 'touch') return
      const a = e.target.closest('[data-full-name]')
      if (!a) return
      const fullName = a.dataset.fullName
      const rect = a.getBoundingClientRect()
      this._tip.textContent = fullName
      this._tip.style.top = (rect.bottom + 6) + 'px'
      this._tip.style.left = rect.left + 'px'
      this._tip.style.display = 'block'
    }

    this._out = (e) => {
      if (e.pointerType === 'touch') return
      if (e.target.closest('[data-full-name]')) this._tip.style.display = 'none'
    }

    this._touchHide = () => { this._tip.style.display = 'none' }

    this.el.addEventListener('pointerover', this._over)
    this.el.addEventListener('pointerout', this._out)
    document.addEventListener('touchstart', this._touchHide, { passive: true })
  },

  destroyed() {
    this._tip?.remove()
    this.el.removeEventListener('pointerover', this._over)
    this.el.removeEventListener('pointerout', this._out)
    document.removeEventListener('touchstart', this._touchHide)
  },
}

export default NameTip
