const ImageLightbox = {
  mounted() {
    this.group = this.el.dataset.lightboxGroup
    this.image = this.el.querySelector("[data-lightbox-image]")
    this.frame = this.el.querySelector("[data-lightbox-frame]")
    this.stage = this.el.querySelector("[data-lightbox-stage]")
    this.loader = this.el.querySelector("[data-lightbox-loader]")
    this.title = this.el.querySelector("[data-lightbox-title]")
    this.counter = this.el.querySelector("[data-lightbox-counter]")
    this.previous = this.el.querySelector("[data-lightbox-previous]")
    this.next = this.el.querySelector("[data-lightbox-next]")
    this.download = this.el.querySelector("[data-lightbox-download]")
    this.zoom = this.el.querySelector("[data-lightbox-zoom]")
    this.fullscreen = this.el.querySelector("[data-lightbox-fullscreen]")
    this.expandIcon = this.el.querySelector("[data-lightbox-expand-icon]")
    this.restoreIcon = this.el.querySelector("[data-lightbox-restore-icon]")
    this.thumbnails = this.el.querySelector("[data-lightbox-thumbnails]")
    this.index = 0
    this.scale = 1
    this.offset = {x: 0, y: 0}
    this.historyEntryActive = false

    this.onDocumentClick = event => {
      const trigger = event.target.closest("[data-lightbox]")
      if (!trigger || trigger.dataset.lightboxGroup !== this.group) return

      event.preventDefault()
      this.open(trigger)
    }

    this.onDialogClick = event => {
      if (event.target === this.el || event.target === this.stage) this.close()
    }

    this.onKeydown = event => {
      if (!this.el.open) return

      if (this.mode === "image" && event.key === "ArrowLeft") this.showPrevious()
      if (this.mode === "image" && event.key === "ArrowRight") this.showNext()
      if (this.mode === "image" && event.key.toLowerCase() === "z") this.toggleZoom()
    }

    this.onCancel = event => {
      event.preventDefault()
      this.close()
    }

    this.onPopState = () => {
      if (this.el.open && this.historyEntryActive) this.close({fromHistory: true})
    }

    this.onFullscreenClick = () => this.setFullscreen(this.el.dataset.fullscreen !== "true")

    this.onPointerDown = event => {
      if (this.mode !== "image") return

      if (this.scale === 1) {
        this.pointerStart = {x: event.clientX, y: event.clientY}
        return
      }

      this.dragStart = {
        x: event.clientX - this.offset.x,
        y: event.clientY - this.offset.y,
      }
      this.stage.setPointerCapture(event.pointerId)
      this.image.classList.add("cursor-grabbing")
    }

    this.onPointerMove = event => {
      if (!this.dragStart) return
      this.offset = {x: event.clientX - this.dragStart.x, y: event.clientY - this.dragStart.y}
      this.applyTransform()
    }

    this.onPointerUp = event => {
      if (this.dragStart) {
        this.dragStart = null
        this.image.classList.remove("cursor-grabbing")
        return
      }

      if (!this.pointerStart || this.scale !== 1) return
      const horizontal = event.clientX - this.pointerStart.x
      const vertical = event.clientY - this.pointerStart.y
      this.pointerStart = null

      if (Math.abs(horizontal) > 55 && Math.abs(horizontal) > Math.abs(vertical)) {
        horizontal > 0 ? this.showPrevious() : this.showNext()
      }
    }

    this.onWheel = event => {
      if (!this.el.open || this.mode !== "image") return
      event.preventDefault()
      this.scale = Math.min(4, Math.max(1, this.scale + (event.deltaY < 0 ? 0.25 : -0.25)))
      if (this.scale === 1) this.offset = {x: 0, y: 0}
      this.applyTransform()
    }

    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
    window.addEventListener("popstate", this.onPopState)
    this.el.addEventListener("click", this.onDialogClick)
    this.el.addEventListener("cancel", this.onCancel)
    this.el.querySelector("[data-lightbox-close]").addEventListener("click", () => this.close())
    this.previous.addEventListener("click", () => this.showPrevious())
    this.next.addEventListener("click", () => this.showNext())
    this.zoom.addEventListener("click", () => this.toggleZoom())
    this.fullscreen.addEventListener("click", this.onFullscreenClick)
    this.image.addEventListener("dblclick", () => this.toggleZoom())
    this.stage.addEventListener("pointerdown", this.onPointerDown)
    this.stage.addEventListener("pointermove", this.onPointerMove)
    this.stage.addEventListener("pointerup", this.onPointerUp)
    this.stage.addEventListener("pointercancel", this.onPointerUp)
    this.stage.addEventListener("wheel", this.onWheel, {passive: false})
  },

  destroyed() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("popstate", this.onPopState)
    this.el.removeEventListener("click", this.onDialogClick)
    this.el.removeEventListener("cancel", this.onCancel)
    this.stage.removeEventListener("pointerdown", this.onPointerDown)
    this.stage.removeEventListener("pointermove", this.onPointerMove)
    this.stage.removeEventListener("pointerup", this.onPointerUp)
    this.stage.removeEventListener("pointercancel", this.onPointerUp)
    this.stage.removeEventListener("wheel", this.onWheel)
    this.fullscreen.removeEventListener("click", this.onFullscreenClick)
    document.body.classList.remove("overflow-hidden")
    this.historyEntryActive = false
  },

  open(trigger) {
    this.mode = trigger.dataset.lightbox

    if (this.mode === "pdf") {
      this.showDocument({url: trigger.href, title: trigger.dataset.lightboxTitle || ""})
      this.openDialog()
      return
    }

    const seen = new Set()
    this.images = [...document.querySelectorAll('[data-lightbox="image"]')]
      .filter(link => link.dataset.lightboxGroup === this.group)
      .map(link => ({url: link.href, title: link.dataset.lightboxTitle || ""}))
      .filter(item => !seen.has(item.url) && seen.add(item.url))

    this.index = Math.max(0, this.images.findIndex(item => item.url === trigger.href))
    this.renderThumbnails()
    this.showImage()
    this.openDialog()
  },

  openDialog() {
    this.el.showModal()
    document.body.classList.add("overflow-hidden")
    window.history.pushState(
      {...(window.history.state || {}), konevoPreview: this.group},
      "",
      window.location.href,
    )
    this.historyEntryActive = true
  },

  close({fromHistory = false} = {}) {
    if (!this.el.open) return
    this.el.close()
    this.loadToken = null
    document.body.classList.remove("overflow-hidden")
    this.frame.src = "about:blank"
    this.resetZoom()
    this.setFullscreen(false)

    const shouldPopHistory = this.historyEntryActive && !fromHistory
    this.historyEntryActive = false
    if (shouldPopHistory) window.history.back()
  },

  showDocument(item) {
    this.resetZoom()
    this.loadToken = null
    this.title.textContent = item.title
    this.counter.textContent = ""
    this.counter.classList.add("hidden")
    this.setDownload(item)
    this.image.classList.add("hidden")
    this.frame.classList.remove("hidden")
    this.frame.src = item.url
    this.loader.classList.remove("opacity-100")
    this.previous.classList.add("hidden")
    this.next.classList.add("hidden")
    this.zoom.classList.add("hidden")
    this.thumbnails.classList.add("hidden")
  },

  showImage() {
    const item = this.images[this.index]
    if (!item) return

    const loadToken = Symbol("image-load")
    this.loadToken = loadToken
    this.resetZoom()
    this.loader.classList.add("opacity-100")
    this.image.classList.remove("hidden")
    this.frame.classList.add("hidden")
    this.frame.src = "about:blank"
    this.zoom.classList.remove("hidden")
    this.image.classList.add("opacity-0")
    this.title.textContent = item.title
    this.counter.textContent = `${this.index + 1} / ${this.images.length}`
    this.counter.classList.remove("hidden")
    this.setDownload(item)
    this.image.onload = () => {
      if (this.loadToken !== loadToken) return
      this.loader.classList.remove("opacity-100")
      this.image.classList.remove("opacity-0")
    }
    this.image.onerror = () => {
      if (this.loadToken !== loadToken) return
      this.loader.classList.remove("opacity-100")
      this.image.classList.remove("opacity-0")
    }

    const preload = new window.Image()
    preload.onload = () => {
      if (this.loadToken !== loadToken) return
      this.image.src = item.url
      this.image.alt = item.title
    }
    preload.onerror = () => {
      if (this.loadToken !== loadToken) return
      this.image.src = item.url
      this.image.alt = item.title
    }
    preload.src = item.url

    const multiple = this.images.length > 1
    this.previous.classList.toggle("hidden", !multiple)
    this.next.classList.toggle("hidden", !multiple)
    this.thumbnails.classList.toggle("hidden", !multiple)
    this.updateThumbnailSelection()
  },

  showPrevious() {
    if (this.images.length < 2) return
    this.index = (this.index - 1 + this.images.length) % this.images.length
    this.showImage()
  },

  setDownload(item) {
    const downloadUrl = new window.URL(item.url)
    downloadUrl.searchParams.delete("preview")
    this.download.href = downloadUrl.toString()
    this.download.download = item.title
  },

  showNext() {
    if (this.images.length < 2) return
    this.index = (this.index + 1) % this.images.length
    this.showImage()
  },

  renderThumbnails() {
    this.thumbnails.replaceChildren()

    this.images.forEach((item, index) => {
      const button = document.createElement("button")
      const image = document.createElement("img")
      button.type = "button"
      button.className = "size-12 shrink-0 overflow-hidden rounded-lg border-2 border-base-content/30 opacity-55 transition hover:opacity-100 focus-visible:outline-2 focus-visible:outline-white"
      button.dataset.lightboxThumbnail = index
      button.setAttribute("aria-label", item.title)
      image.src = item.url
      image.alt = ""
      image.loading = "lazy"
      image.className = "size-full object-cover"
      button.appendChild(image)
      button.addEventListener("click", () => {
        this.index = index
        this.showImage()
      })
      this.thumbnails.appendChild(button)
    })
  },

  updateThumbnailSelection() {
    this.thumbnails.querySelectorAll("[data-lightbox-thumbnail]").forEach((thumbnail, index) => {
      const selected = index === this.index
      thumbnail.classList.toggle("border-primary", selected)
      thumbnail.classList.toggle("opacity-100", selected)
      thumbnail.setAttribute("aria-current", selected ? "true" : "false")
      if (selected) thumbnail.scrollIntoView({behavior: "smooth", block: "nearest", inline: "center"})
    })
  },

  toggleZoom() {
    this.scale = this.scale === 1 ? 2 : 1
    if (this.scale === 1) this.offset = {x: 0, y: 0}
    this.applyTransform()
  },

  setFullscreen(fullscreen) {
    this.el.dataset.fullscreen = fullscreen ? "true" : "false"
    this.fullscreen.setAttribute("aria-pressed", fullscreen ? "true" : "false")

    const label = fullscreen
      ? this.fullscreen.dataset.restoreLabel
      : this.fullscreen.dataset.expandLabel

    this.fullscreen.setAttribute("aria-label", label)
    this.fullscreen.title = label
    this.expandIcon.classList.toggle("hidden", fullscreen)
    this.restoreIcon.classList.toggle("hidden", !fullscreen)
  },

  resetZoom() {
    this.scale = 1
    this.offset = {x: 0, y: 0}
    this.applyTransform()
  },

  applyTransform() {
    this.image.style.transform = `translate(${this.offset.x}px, ${this.offset.y}px) scale(${this.scale})`
    this.image.classList.toggle("cursor-zoom-in", this.scale === 1)
    this.image.classList.toggle("cursor-grab", this.scale > 1)
    this.zoom.setAttribute("aria-pressed", this.scale > 1 ? "true" : "false")
  },
}

export default ImageLightbox
