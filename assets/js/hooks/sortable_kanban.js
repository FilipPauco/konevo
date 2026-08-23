import Sortable from "sortablejs"

const GLOBAL_KANBAN_DRAG_STATE = {
  originalParent: null,
  originalIndex: null,
  currentMouseX: 0,
  currentMouseY: 0,
  originalPlaceholder: null,
  dropPlaceholder: null,
  draggedElement: null,
  draggedElementClone: null,
  draggedRect: null,
  isDragging: false,
  lastDropZone: null,
  lastRelatedElement: null,
  pendingTimers: new Map(),
  preferredOrders: new Map(),
  preferredOrderTimers: new Map()
}

const SortableKanban = {
  mounted() {
    this.group = this.el.dataset.group

    this._trackMouse = e => {
      const point = e.touches?.[0] || e.changedTouches?.[0] || e
      GLOBAL_KANBAN_DRAG_STATE.currentMouseX = point.clientX
      GLOBAL_KANBAN_DRAG_STATE.currentMouseY = point.clientY

      if (!GLOBAL_KANBAN_DRAG_STATE.isDragging) return

      const el = document.elementFromPoint(point.clientX, point.clientY)
      if (!el) {
        this._removeDropPlaceholder()
        GLOBAL_KANBAN_DRAG_STATE.lastDropZone = null
        GLOBAL_KANBAN_DRAG_STATE.lastRelatedElement = null
        return
      }

      const dropZone = el.closest('[phx-hook="SortableKanban"][data-group]')

      if (dropZone) {
        const cards = Array.from(dropZone.querySelectorAll("[data-id]")).filter(
          c =>
            c !== GLOBAL_KANBAN_DRAG_STATE.draggedElement &&
            c !== GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder &&
            c !== GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder
        )

        let relatedElement = null
        for (const card of cards) {
          const cardRect = card.getBoundingClientRect()
          const midpoint = cardRect.top + cardRect.height / 2
          if (point.clientY < midpoint) {
            relatedElement = card
            break
          }
        }

        if (
          GLOBAL_KANBAN_DRAG_STATE.lastDropZone === dropZone &&
          GLOBAL_KANBAN_DRAG_STATE.lastRelatedElement === relatedElement
        ) {
          return
        }

        GLOBAL_KANBAN_DRAG_STATE.lastDropZone = dropZone
        GLOBAL_KANBAN_DRAG_STATE.lastRelatedElement = relatedElement
        this._updateDropPlaceholder(dropZone, relatedElement)
      } else {
        this._removeDropPlaceholder()
        GLOBAL_KANBAN_DRAG_STATE.lastDropZone = null
        GLOBAL_KANBAN_DRAG_STATE.lastRelatedElement = null
      }
    }

    this.sortable = new Sortable(this.el, {
      delay: 0,
      swapThreshold: 1,
      group: this.group ? this.group : undefined,
      sort: false,
      animation: 180,
      easing: "cubic-bezier(0.2, 0, 0, 1)",
      chosenClass: "kanban-drag-chosen",
      dragClass: "kanban-drag-source",
      ghostClass: "kanban-drag-ghost",
      fallbackClass: "kanban-drag-fallback",
      forceFallback: true,
      fallbackOnBody: true,
      fallbackTolerance: 2,
      fallbackOffset: {x: 0, y: 0},
      touchStartThreshold: 3,
      emptyInsertThreshold: 28,
      handle: ".drag-handle",
      onClone: e => {
        this._applyLockedSize(e.clone, GLOBAL_KANBAN_DRAG_STATE.draggedRect, true)
      },
      onEnd: e => {
        const placeholder = GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder

        let targetZone = null

        if (placeholder && placeholder.parentNode) {
          targetZone =
            placeholder.parentNode.closest('[phx-hook="SortableKanban"][data-group]') ||
            placeholder.parentNode
          targetZone.insertBefore(e.item, placeholder)
        } else {
          const mouseX = GLOBAL_KANBAN_DRAG_STATE.currentMouseX
          const mouseY = GLOBAL_KANBAN_DRAG_STATE.currentMouseY
          targetZone = this._findDropZone(mouseX, mouseY)

          if (!targetZone) {
            this._restoreOriginalPosition(e.item)
            this._finishDrag(e.item)
            return
          }

          const fallbackCards = Array.from(targetZone.querySelectorAll("[data-id]")).filter(
            c =>
              c !== e.item &&
              c !== GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder &&
              c !== GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder
          )

          let insertBefore = null
          for (const card of fallbackCards) {
            const cardRect = card.getBoundingClientRect()
            if (mouseY < cardRect.top + cardRect.height / 2) {
              insertBefore = card
              break
            }
          }

          if (insertBefore) targetZone.insertBefore(e.item, insertBefore)
          else targetZone.appendChild(e.item)
        }

        const allCards = Array.from(targetZone.querySelectorAll("[data-id]")).filter(
          c =>
            c !== e.item &&
            c !== GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder &&
            c !== GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder
        )

        const nextSibling = e.item.nextElementSibling
        const positionRef = nextSibling && allCards.includes(nextSibling) ? nextSibling : null

        this._rememberPreferredOrder(targetZone)
        if (
          GLOBAL_KANBAN_DRAG_STATE.originalParent &&
          GLOBAL_KANBAN_DRAG_STATE.originalParent !== targetZone
        ) {
          this._rememberPreferredOrder(GLOBAL_KANBAN_DRAG_STATE.originalParent)
        }

        this._finishDrag(e.item, true)

        const params = {
          from: {...e.from.dataset},
          to: {...targetZone.dataset},
          position: this._targetPosition(allCards, positionRef),
          ...e.item.dataset
        }
        this.pushEventTo(this.el, "reposition-kanban", params)
      },
      onMove: e => {
        this._removeSelection()
        return e.to?.dataset?.group === this.group ? 1 : -1
      },
      onStart: e => {
        this._removeSelection()
        GLOBAL_KANBAN_DRAG_STATE.originalIndex = e.oldIndex
        GLOBAL_KANBAN_DRAG_STATE.originalParent = e.from
        GLOBAL_KANBAN_DRAG_STATE.draggedElement = e.item
        GLOBAL_KANBAN_DRAG_STATE.draggedElementClone = e.item.cloneNode(true)
        GLOBAL_KANBAN_DRAG_STATE.draggedRect = this._measureElement(e.item)
        GLOBAL_KANBAN_DRAG_STATE.isDragging = true
        GLOBAL_KANBAN_DRAG_STATE.lastDropZone = null
        GLOBAL_KANBAN_DRAG_STATE.lastRelatedElement = null

        document.addEventListener("mousemove", this._trackMouse)
        document.addEventListener("touchmove", this._trackMouse, {passive: true})
        document.body?.classList.add("kanban-is-dragging")

        const originalPlaceholder = e.item.cloneNode(true)
        originalPlaceholder.classList.remove(
          "kanban-drag-source",
          "kanban-drag-hidden",
          "kanban-drag-ghost",
          "kanban-drag-fallback",
          "hidden"
        )
        originalPlaceholder.classList.add("kanban-original-placeholder")
        originalPlaceholder.removeAttribute("id")
        originalPlaceholder.setAttribute("data-original-placeholder", "true")
        originalPlaceholder.setAttribute("aria-hidden", "true")
        originalPlaceholder.style.pointerEvents = "none"
        this._applyLockedSize(originalPlaceholder, GLOBAL_KANBAN_DRAG_STATE.draggedRect)

        e.item.parentNode.insertBefore(originalPlaceholder, e.item)
        e.item.classList.add("kanban-drag-hidden")
        this._applyLockedSize(e.item, GLOBAL_KANBAN_DRAG_STATE.draggedRect)

        GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder = originalPlaceholder
      }
    })
  },
  updated() {
    this._applyPreferredOrder(this.el)
  },
  destroyed() {
    GLOBAL_KANBAN_DRAG_STATE.isDragging = false
    document.removeEventListener("mousemove", this._trackMouse)
    document.removeEventListener("touchmove", this._trackMouse)
    document.body?.classList.remove("kanban-is-dragging")

    if (GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder) {
      GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder.remove()
      GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder = null
    }

    this._removeDropPlaceholder()

    if (GLOBAL_KANBAN_DRAG_STATE.draggedElement) {
      GLOBAL_KANBAN_DRAG_STATE.draggedElement.classList.remove(
        "kanban-drag-hidden",
        "hidden"
      )
      this._clearLockedSize(GLOBAL_KANBAN_DRAG_STATE.draggedElement)
      GLOBAL_KANBAN_DRAG_STATE.draggedElement = null
    }

    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  },
  _removeDropPlaceholder() {
    if (GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder) {
      GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder.remove()
      GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder = null
    }
  },
  _updateDropPlaceholder(targetZone, relatedElement) {
    if (GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder) {
      GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder.remove()
    }

    const clone = GLOBAL_KANBAN_DRAG_STATE.draggedElementClone
    if (!clone) return

    const placeholder = clone.cloneNode(true)
    placeholder.classList.remove(
      "kanban-drag-source",
      "kanban-drag-hidden",
      "kanban-drag-ghost",
      "kanban-drag-fallback",
      "hidden"
    )
    placeholder.classList.add("kanban-drop-placeholder")
    placeholder.setAttribute("data-drop-placeholder", "true")
    placeholder.setAttribute("aria-hidden", "true")
    placeholder.style.pointerEvents = "none"
    this._applyLockedSize(placeholder, GLOBAL_KANBAN_DRAG_STATE.draggedRect)

    if (relatedElement) {
      targetZone.insertBefore(placeholder, relatedElement)
    } else {
      targetZone.appendChild(placeholder)
    }

    GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder = placeholder
  },
  _finishDrag(item, settle = false) {
    GLOBAL_KANBAN_DRAG_STATE.isDragging = false
    document.removeEventListener("mousemove", this._trackMouse)
    document.removeEventListener("touchmove", this._trackMouse)
    document.body?.classList.remove("kanban-is-dragging")

    this._removeDropPlaceholder()

    if (GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder) {
      GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder.remove()
      GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder = null
    }

    item.classList.remove(
      "kanban-drag-hidden",
      "kanban-drag-source",
      "kanban-drag-ghost",
      "kanban-drag-fallback"
    )

    if (settle) {
      this._markDropPending(item)
    } else {
      this._clearLockedSize(item)
    }

    GLOBAL_KANBAN_DRAG_STATE.draggedElement = null
    GLOBAL_KANBAN_DRAG_STATE.draggedElementClone = null
    GLOBAL_KANBAN_DRAG_STATE.draggedRect = null
    GLOBAL_KANBAN_DRAG_STATE.lastDropZone = null
    GLOBAL_KANBAN_DRAG_STATE.lastRelatedElement = null
  },
  _restoreOriginalPosition(item) {
    const originalParent = GLOBAL_KANBAN_DRAG_STATE.originalParent
    if (!originalParent) return

    const children = Array.from(originalParent.children).filter(
      child => child !== GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder
    )
    const target = children[GLOBAL_KANBAN_DRAG_STATE.originalIndex] || null
    originalParent.insertBefore(item, target)
  },
  _markDropPending(item) {
    const rect = GLOBAL_KANBAN_DRAG_STATE.draggedRect
    const dealId = item.dataset.id

    item.classList.add("kanban-drop-pending", "kanban-drop-settling")
    item.removeAttribute("aria-hidden")
    this._applyLockedSize(item, rect)

    if (!dealId) {
      window.setTimeout(() => this._clearDropPending(item), 220)
      return
    }

    this._clearPendingTimer(dealId)
    const timer = window.setTimeout(() => {
      GLOBAL_KANBAN_DRAG_STATE.pendingTimers.delete(dealId)
      this._clearDropPending(item)
    }, 220)

    GLOBAL_KANBAN_DRAG_STATE.pendingTimers.set(dealId, timer)
  },
  _clearDropPending(item) {
    item.classList.remove("kanban-drop-pending", "kanban-drop-settling")
    this._clearLockedSize(item)
  },
  _clearPendingTimer(dealId) {
    const timer = GLOBAL_KANBAN_DRAG_STATE.pendingTimers.get(dealId)
    if (timer) {
      window.clearTimeout(timer)
      GLOBAL_KANBAN_DRAG_STATE.pendingTimers.delete(dealId)
    }
  },
  _measureElement(element) {
    const rect = element.getBoundingClientRect()
    return {width: rect.width, height: rect.height}
  },
  _applyLockedSize(element, rect, fixedWidth = false) {
    if (!element || !rect) return
    element.style.minHeight = `${rect.height}px`
    element.style.width = fixedWidth ? `${rect.width}px` : "100%"
  },
  _clearLockedSize(element) {
    if (!element) return
    element.style.minHeight = ""
    element.style.width = ""
  },
  _findDropZone(mouseX, mouseY) {
    const el = document.elementFromPoint(mouseX, mouseY)
    if (!el) return null
    return el.closest('[phx-hook="SortableKanban"][data-group]')
  },
  _targetPosition(cards, insertBefore) {
    if (!insertBefore) return cards.length
    const index = cards.indexOf(insertBefore)
    return index >= 0 ? index : cards.length
  },
  _zoneKey(zone) {
    if (!zone) return null
    return zone.id || `${zone.dataset.parent || ""}:${zone.dataset.status || ""}`
  },
  _zoneCards(zone, includeDragged = false) {
    if (!zone) return []
    return Array.from(zone.querySelectorAll("[data-id]")).filter(card => {
      if (!includeDragged && card === GLOBAL_KANBAN_DRAG_STATE.draggedElement) return false
      if (card === GLOBAL_KANBAN_DRAG_STATE.dropPlaceholder) return false
      if (card === GLOBAL_KANBAN_DRAG_STATE.originalPlaceholder) return false
      if (card.getAttribute("data-drop-placeholder") === "true") return false
      if (card.getAttribute("data-original-placeholder") === "true") return false
      return Boolean(card.dataset.id)
    })
  },
  _rememberPreferredOrder(zone) {
    const key = this._zoneKey(zone)
    if (!key) return

    const order = this._zoneCards(zone, true).map(card => card.dataset.id)
    const expiresAt = Date.now() + 3000

    GLOBAL_KANBAN_DRAG_STATE.preferredOrders.set(key, {order, expiresAt})

    const existingTimer = GLOBAL_KANBAN_DRAG_STATE.preferredOrderTimers.get(key)
    if (existingTimer) window.clearTimeout(existingTimer)

    const timer = window.setTimeout(() => {
      const preferred = GLOBAL_KANBAN_DRAG_STATE.preferredOrders.get(key)
      if (preferred?.expiresAt === expiresAt) {
        GLOBAL_KANBAN_DRAG_STATE.preferredOrders.delete(key)
      }
      GLOBAL_KANBAN_DRAG_STATE.preferredOrderTimers.delete(key)
    }, 3000)

    GLOBAL_KANBAN_DRAG_STATE.preferredOrderTimers.set(key, timer)
  },
  _applyPreferredOrder(zone) {
    const key = this._zoneKey(zone)
    if (!key) return

    const preferred = GLOBAL_KANBAN_DRAG_STATE.preferredOrders.get(key)
    if (!preferred || preferred.expiresAt < Date.now()) {
      GLOBAL_KANBAN_DRAG_STATE.preferredOrders.delete(key)
      return
    }

    const cards = this._zoneCards(zone, true)
    if (cards.length < 2) return

    const cardById = new Map(cards.map(card => [card.dataset.id, card]))
    const reordered = []

    preferred.order.forEach(id => {
      const card = cardById.get(id)
      if (card) {
        reordered.push(card)
        cardById.delete(id)
      }
    })

    cards.forEach(card => {
      if (cardById.has(card.dataset.id)) {
        reordered.push(card)
        cardById.delete(card.dataset.id)
      }
    })

    reordered.forEach(card => zone.appendChild(card))
  },
  _removeSelection() {
    const selection = window.getSelection()
    if (selection?.rangeCount > 0) selection.removeAllRanges()
  }
}

export default SortableKanban

