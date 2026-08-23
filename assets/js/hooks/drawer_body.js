// DrawerBody hook — hides stale content when switching tasks.
// Adds `is-switching` on any [data-task-link] click; cleared in updated()
// when the server's next patch arrives. A generous timeout fallback handles
// same-task re-clicks where updated() might not fire.
// Also guards the ESC key when the notes editor has unsaved changes.
const DrawerBody = {
  mounted() {
    this._switchTimer = null
    this._enterTimer = null
    this._taskId = this.el.dataset.taskId
    this._dirty = false

    // Track dirty state from the tiptap notes editor inside this drawer
    this._unsavedHandler = (e) => {
      const drawer = document.getElementById("task-drawer")
      if (drawer && (drawer.contains(e.target) || e.target === document)) {
        this._dirty = !!e.detail?.dirty
      }
    }
    document.addEventListener("konevo:unsaved-change", this._unsavedHandler, true)

    // Intercept ESC before LiveView processes it — show unsaved modal if dirty
    this._escHandler = (e) => {
      if (e.key !== "Escape") return
      const drawer = document.getElementById("task-drawer")
      if (!drawer || !drawer.classList.contains("drawer-open")) return
      if (!this._dirty) return

      e.stopImmediatePropagation()

      // Simulate a backdrop click so the existing unsaved-changes guard shows the modal
      const backdrop = document.getElementById("task-drawer-backdrop")
      if (backdrop) backdrop.click()
    }
    document.addEventListener("keydown", this._escHandler, true)

    this._handler = (e) => {
      if (e.target.closest('[data-task-link]')) {
        this.el.classList.add('is-switching')
        this.el.classList.remove('is-entering')
        clearTimeout(this._switchTimer)
        // Long fallback: let it clear if server takes a while
        this._switchTimer = setTimeout(() => this.el.classList.remove('is-switching'), 1200)
      }
    }
    document.addEventListener('click', this._handler, true)
  },
  updated() {
    const taskId = this.el.dataset.taskId
    const taskChanged = taskId !== this._taskId
    this._taskId = taskId

    clearTimeout(this._switchTimer)
    clearTimeout(this._enterTimer)
    this.el.classList.remove('is-switching')

    if (taskChanged) {
      this._dirty = false
      // Trigger a smooth fade-in only when switching tasks, not on upload progress patches.
      this.el.classList.add('is-entering')
      this._enterTimer = setTimeout(() => this.el.classList.remove('is-entering'), 280)
    }
  },
  destroyed() {
    document.removeEventListener('click', this._handler, true)
    document.removeEventListener("konevo:unsaved-change", this._unsavedHandler, true)
    document.removeEventListener("keydown", this._escHandler, true)
    clearTimeout(this._switchTimer)
    clearTimeout(this._enterTimer)
  }
}

export default DrawerBody
