const MAX_SELECTION_LENGTH = 4000

const EmailSelectionActions = {
  mounted() {
    this.toolbar = this.el.querySelector("[data-selection-toolbar]")
    this.selection = null

    this.onSelectionChange = () => window.setTimeout(() => this.captureDocumentSelection(), 0)
    this.onMouseUp = () => window.setTimeout(() => this.captureDocumentSelection(), 0)
    this.onKeyUp = event => {
      if (event.key === "Escape") {
        this.hide()
      } else {
        window.setTimeout(() => this.captureDocumentSelection(), 0)
      }
    }
    this.onScroll = () => this.hide()
    this.onResize = () => this.hide()
    this.onThemeChange = () => window.setTimeout(() => this.syncIframeThemes(), 0)
    this.onStorage = event => {
      if (event.key === "phx:theme") this.syncIframeThemes()
    }
    this.onDocumentMouseDown = event => {
      if (!this.toolbar?.contains(event.target) && !this.el.contains(event.target)) this.hide()
    }

    this.toolbar?.addEventListener("mousedown", event => event.preventDefault())
    this.toolbar?.addEventListener("click", event => this.handleToolbarClick(event))
    document.addEventListener("selectionchange", this.onSelectionChange)
    document.addEventListener("mouseup", this.onMouseUp)
    document.addEventListener("keyup", this.onKeyUp)
    document.addEventListener("mousedown", this.onDocumentMouseDown)
    window.addEventListener("scroll", this.onScroll, true)
    window.addEventListener("resize", this.onResize)
    window.addEventListener("phx:set-theme", this.onThemeChange)
    window.addEventListener("storage", this.onStorage)

    this.attachIframeListeners()
  },

  updated() {
    this.attachIframeListeners()
  },

  destroyed() {
    document.removeEventListener("selectionchange", this.onSelectionChange)
    document.removeEventListener("mouseup", this.onMouseUp)
    document.removeEventListener("keyup", this.onKeyUp)
    document.removeEventListener("mousedown", this.onDocumentMouseDown)
    window.removeEventListener("scroll", this.onScroll, true)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("phx:set-theme", this.onThemeChange)
    window.removeEventListener("storage", this.onStorage)
  },

  attachIframeListeners() {
    this.el.querySelectorAll("[data-email-selectable-iframe]").forEach(iframe => {
      this.syncIframeTheme(iframe)
      if (iframe.dataset.selectionBound === "true") return

      iframe.dataset.selectionBound = "true"
      iframe.addEventListener("load", () => {
        this.syncIframeTheme(iframe)
        this.bindIframeDocument(iframe)
      })
      this.bindIframeDocument(iframe)
    })
  },

  syncIframeThemes() {
    this.el.querySelectorAll("[data-email-selectable-iframe]").forEach(iframe => {
      this.syncIframeTheme(iframe)
    })
  },

  syncIframeTheme(iframe) {
    const doc = this.iframeDocument(iframe)
    if (!doc) return

    const root = doc.documentElement

    root.dataset.theme = "corporate"
    root.style.setProperty("color-scheme", "light")
    root.style.setProperty("--email-background", "#f8fafc")
    root.style.setProperty("--email-foreground", "#1e293b")
    root.style.setProperty("--email-link", "#2563eb")
  },

  bindIframeDocument(iframe) {
    const doc = this.iframeDocument(iframe)
    if (!doc || doc.__emailSelectionBound) return

    doc.__emailSelectionBound = true
    doc.addEventListener("mouseup", () => window.setTimeout(() => this.captureIframeSelection(iframe), 0))
    doc.addEventListener("keyup", event => {
      if (event.key === "Escape") {
        this.hide()
      } else {
        window.setTimeout(() => this.captureIframeSelection(iframe), 0)
      }
    })
  },

  iframeDocument(iframe) {
    try {
      return iframe.contentDocument || iframe.contentWindow?.document || null
    } catch (_error) {
      return null
    }
  },

  captureDocumentSelection() {
    const selection = window.getSelection()
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      this.hide()
      return
    }

    const range = selection.getRangeAt(0)
    const container = this.selectionContainer(range.commonAncestorContainer)
    if (!container) {
      this.hide()
      return
    }

    this.show({
      text: this.cleanText(selection.toString()),
      emailId: container.dataset.emailId,
      rect: range.getBoundingClientRect(),
    })
  },

  captureIframeSelection(iframe) {
    const selection = iframe.contentWindow?.getSelection()
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      this.hide()
      return
    }

    const range = selection.getRangeAt(0)
    const iframeRect = iframe.getBoundingClientRect()
    const selectionRect = range.getBoundingClientRect()

    this.show({
      text: this.cleanText(selection.toString()),
      emailId: iframe.dataset.emailId,
      rect: {
        left: iframeRect.left + selectionRect.left,
        right: iframeRect.left + selectionRect.right,
        top: iframeRect.top + selectionRect.top,
        bottom: iframeRect.top + selectionRect.bottom,
        width: selectionRect.width,
        height: selectionRect.height,
      },
    })
  },

  selectionContainer(node) {
    const element = node?.nodeType === 1 ? node : node?.parentElement
    const container = element?.closest?.("[data-email-selectable]")

    if (container && this.el.contains(container)) return container
    return null
  },

  cleanText(text) {
    return (text || "").replace(/\s+\n/g, "\n").replace(/\n\s+/g, "\n").trim().slice(0, MAX_SELECTION_LENGTH)
  },

  show({text, emailId, rect}) {
    if (!this.toolbar || !text || !rect || rect.width === 0 && rect.height === 0) {
      this.hide()
      return
    }

    this.selection = {text, emailId}
    this.toolbar.classList.remove("hidden")
    this.toolbar.classList.add("flex")

    const toolbarRect = this.toolbar.getBoundingClientRect()
    const viewportPadding = 8
    const left = Math.min(
      Math.max(rect.left + rect.width / 2 - toolbarRect.width / 2, viewportPadding),
      window.innerWidth - toolbarRect.width - viewportPadding
    )
    const top = rect.top > toolbarRect.height + 12
      ? rect.top - toolbarRect.height - 8
      : rect.bottom + 8

    this.toolbar.style.left = `${left}px`
    this.toolbar.style.top = `${Math.max(top, viewportPadding)}px`
  },

  hide() {
    this.selection = null
    this.toolbar?.classList.add("hidden")
    this.toolbar?.classList.remove("flex")
  },

  handleToolbarClick(event) {
    const button = event.target.closest("[data-selection-action]")
    if (!button || !this.selection) return

    this.pushEvent("email_selection_action", {
      action: button.dataset.selectionAction,
      text: this.selection.text,
      email_id: this.selection.emailId,
    })
    this.hide()
  },
}

export default EmailSelectionActions
