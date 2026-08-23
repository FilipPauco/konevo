export const AutoResize = {
  mounted() {
    // Store initial rows value
    this.storedRows = this.el.getAttribute('rows') || 1

    // Auto-resize based on content
    this.autoResize()

    // Listen for input events to auto-resize
    this.el.addEventListener('input', () => {
      this.autoResize()
    })

    // Listen for keyup events to handle paste and other operations
    this.el.addEventListener('keyup', () => {
      this.autoResize()
    })

    // Track when the textarea is resized (by user dragging the resize handle)
    this.resizeObserver = new ResizeObserver((_entries) => {
      // Debounce the resize end handler to avoid excessive calls
      clearTimeout(this.resizeTimeout)
      this.resizeTimeout = setTimeout(() => {
        this.handleResizeEnd()
      }, 100) // Wait 100ms after resize stops
    })

    this.resizeObserver.observe(this.el)
  },

  autoResize() {
    // Reset height to auto to get the natural height
    this.el.style.height = 'auto'

    // Get the scroll height (content height)
    const scrollHeight = this.el.scrollHeight

    // Set the height to match the content
    this.el.style.height = scrollHeight + 'px'

    // Calculate rows based on content
    const computedStyle = getComputedStyle(this.el)
    const lineHeight = parseFloat(computedStyle.lineHeight) || 20
    const paddingTop = parseFloat(computedStyle.paddingTop) || 0
    const paddingBottom = parseFloat(computedStyle.paddingBottom) || 0

    const contentHeight = scrollHeight - paddingTop - paddingBottom
    const newRows = Math.max(1, Math.round(contentHeight / lineHeight))

    // Store the new rows value
    this.storedRows = newRows
    this.el.setAttribute('rows', newRows)
  },

  handleResizeEnd() {
    const finalHeight = this.el.offsetHeight
    const computedStyle = getComputedStyle(this.el)
    const lineHeight = parseFloat(computedStyle.lineHeight) || 20
    const paddingTop = parseFloat(computedStyle.paddingTop) || 0
    const paddingBottom = parseFloat(computedStyle.paddingBottom) || 0

    // Calculate content height (excluding padding)
    const contentHeight = finalHeight - paddingTop - paddingBottom
    const newRows = Math.max(1, Math.round(contentHeight / lineHeight))

    // Store the new rows value
    this.storedRows = newRows
    this.el.setAttribute('rows', newRows)
  },

  // Restore rows and auto-resize after each LiveView update
  updated() {
    if (this.storedRows) {
      this.el.setAttribute('rows', this.storedRows)
    }
    // Auto-resize in case content changed
    this.autoResize()
  },

  // Clean up the observer when the hook is destroyed
  destroyed() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
    if (this.resizeTimeout) {
      clearTimeout(this.resizeTimeout)
    }
  }
}
