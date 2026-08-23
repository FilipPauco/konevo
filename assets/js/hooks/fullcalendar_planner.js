import "temporal-polyfill/global"
import {Calendar} from "fullcalendar"
import dayGridPlugin from "fullcalendar/daygrid"
import interactionPlugin from "fullcalendar/interaction"
import listPlugin from "fullcalendar/list"
import timeGridPlugin from "fullcalendar/timegrid"
import themePlugin from "fullcalendar/themes/monarch"
import skLocale from "fullcalendar/locales/sk"

const SOURCE_CLASSES = {
  task: "konevo-calendar-event--task",
  google_calendar: "konevo-calendar-event--google-calendar",
  deal_action: "konevo-calendar-event--deal-action",
  deal_close: "konevo-calendar-event--deal-close",
}

const TASK_TYPE_ICONS = {
  epic: "icon-[tabler--crown]",
  task: "icon-[tabler--menu-2]",
}

const EVENT_MIN_HEIGHT = 82
const CURRENT_TIME_SCROLL_OFFSET_MINUTES = 60

const FullCalendarPlanner = {
  mounted() {
    const initialPayload = this.readInitialPayload()

    this.events = initialPayload.events
    this.initialPayloadKey = this.el.dataset.initialCalendar || ""
    this.initialLoadedRange = initialPayload.range
    this.initialRangeConsumed = false
    this.enabledSources = new Set(["task", "google_calendar", "deal_action", "deal_close"])
    this.calendarEl = this.el.querySelector("[data-calendar]")
    this.titleEl = this.el.querySelector("[data-calendar-title]")
    this.countEl = this.el.querySelector("[data-calendar-count]")
    this.viewButtons = [...this.el.querySelectorAll("[data-calendar-view]")]
    this.sourceButtons = [...this.el.querySelectorAll("[data-calendar-source]")]

    this.calendar = new Calendar(this.calendarEl, {
      plugins: [themePlugin, dayGridPlugin, timeGridPlugin, listPlugin, interactionPlugin],
      locale: this.locale(),
      initialView: "dayGridMonth",
      initialDate: this.el.dataset.calendarInitialDate || undefined,
      headerToolbar: false,
      height: "100%",
      expandRows: true,
      nowIndicator: true,
      navLinks: true,
      dayMaxEvents: 4,
      scrollTime: this.currentScrollTime(),
      scrollTimeReset: false,
      eventDisplay: "block",
      eventMinHeight: EVENT_MIN_HEIGHT,
      eventShortHeight: 0,
      views: {
        timeGridWeek: {
          eventMinHeight: EVENT_MIN_HEIGHT,
          eventShortHeight: 0,
          slotMinHeight: 38,
        },
        timeGridDay: {
          eventMinHeight: EVENT_MIN_HEIGHT,
          eventShortHeight: 0,
          slotMinHeight: 38,
        },
      },
      eventTimeFormat: {
        hour: "2-digit",
        minute: "2-digit",
        meridiem: false,
      },
      noEventsContent: () => this.emptyContent(),
      eventClass: info => this.eventClasses(info),
      eventContent: info => this.eventContent(info),
      eventClick: info => this.openEvent(info),
      datesSet: info => this.syncRange(info),
      events: (_fetchInfo, successCallback) => successCallback(this.visibleEvents()),
    })

    this.bindToolbar()
    this.handleEvent("calendar:events", payload => {
      this.events = Array.isArray(payload.events) ? payload.events : []
      this.calendar.refetchEvents()
      this.updateVisibleCount()
    })

    this.calendar.render()
    if (this.initialLoadedRange) this.updateVisibleCount()
    this.scrollToRelevantTime()

    this.resizeHandler = () => this.scheduleResize()
    window.addEventListener("resize", this.resizeHandler)
    setTimeout(() => this.scheduleResize(), 60)
  },

  updated() {
    this.applyInitialPayload()
  },

  destroyed() {
    if (this.resizeHandler) window.removeEventListener("resize", this.resizeHandler)
    if (this.resizeFrame) cancelAnimationFrame(this.resizeFrame)
    if (this.calendar) this.calendar.destroy()
  },

  scheduleResize() {
    if (!this.calendar) return

    if (this.resizeFrame) cancelAnimationFrame(this.resizeFrame)

    this.resizeFrame = requestAnimationFrame(() => {
      this.resizeFrame = null
      this.resizeCalendar()
    })
  },

  resizeCalendar() {
    if (!this.calendar) return

    if (typeof this.calendar.updateSize === "function") {
      this.calendar.updateSize()
      return
    }

    this.calendar.render()
  },

  locale() {
    return this.el.dataset.calendarLocale === "sk" ? skLocale : "en"
  },

  readInitialPayload() {
    try {
      const payload = JSON.parse(this.el.dataset.initialCalendar || "{}")
      return {
        events: Array.isArray(payload.events) ? payload.events : [],
        range: this.validRange(payload.range) ? payload.range : null,
      }
    } catch (_error) {
      return {events: [], range: null}
    }
  },

  applyInitialPayload() {
    const payloadKey = this.el.dataset.initialCalendar || ""
    if (!this.calendar || payloadKey === this.initialPayloadKey) return

    this.initialPayloadKey = payloadKey
    const payload = this.readInitialPayload()
    if (!payload.range || !this.rangeMatchesCurrent(payload.range)) return

    this.events = payload.events
    this.initialLoadedRange = payload.range
    this.initialRangeConsumed = false
    this.calendar.refetchEvents()
    this.updateVisibleCount()
  },

  validRange(range) {
    return Boolean(range?.start && range?.end)
  },

  bindToolbar() {
    this.el.querySelector("[data-calendar-action='prev']")?.addEventListener("click", () => {
      this.calendar.prev()
    })

    this.el.querySelector("[data-calendar-action='next']")?.addEventListener("click", () => {
      this.calendar.next()
    })

    this.el.querySelector("[data-calendar-action='today']")?.addEventListener("click", () => {
      this.calendar.today()
      this.scrollToRelevantTime()
    })

    this.viewButtons.forEach(button => {
      button.addEventListener("click", () => {
        this.calendar.changeView(button.dataset.calendarView)
        this.scrollToRelevantTime()
      })
    })

    this.sourceButtons.forEach(button => {
      button.addEventListener("click", () => {
        const source = button.dataset.calendarSource
        if (this.enabledSources.has(source)) {
          this.enabledSources.delete(source)
          button.dataset.active = "false"
        } else {
          this.enabledSources.add(source)
          button.dataset.active = "true"
        }

        this.calendar.refetchEvents()
        this.updateVisibleCount()
      })
    })
  },

  syncRange(info) {
    if (this.titleEl) this.titleEl.textContent = info.view.title

    this.viewButtons.forEach(button => {
      const active = button.dataset.calendarView === info.view.type
      button.setAttribute("aria-pressed", active ? "true" : "false")
      button.classList.toggle("calendar-view-button--active", active)
      button.classList.toggle("btn-active", active)
    })

    if (
      this.initialLoadedRange &&
      !this.initialRangeConsumed &&
      this.rangeMatchesInfo(this.initialLoadedRange, info)
    ) {
      this.initialRangeConsumed = true
      this.updateVisibleCount()
      return
    }

    this.initialRangeConsumed = true
    this.pushEvent("calendar_range_changed", {
      start: info.startStr,
      end: info.endStr,
      view: info.view.type,
    })

    this.scrollToRelevantTime(info)
  },

  scrollToRelevantTime(info = null) {
    if (!this.calendar || !this.timedGridView(this.calendar.view?.type)) return

    const view = info?.view || this.calendar.view
    if (!this.todayInView(view)) return

    requestAnimationFrame(() => {
      this.calendar?.scrollToTime?.(this.currentScrollTime())
    })
  },

  todayInView(view) {
    const today = new Date()
    const start = view?.activeStart
    const end = view?.activeEnd

    if (!(start instanceof Date) || !(end instanceof Date)) return false

    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    const tomorrowStart = new Date(todayStart)
    tomorrowStart.setDate(tomorrowStart.getDate() + 1)

    return start < tomorrowStart && end > todayStart
  },

  currentScrollTime() {
    const date = new Date()
    const minutes = Math.max(0, date.getHours() * 60 + date.getMinutes() - CURRENT_TIME_SCROLL_OFFSET_MINUTES)
    const hours = String(Math.floor(minutes / 60)).padStart(2, "0")
    const mins = String(minutes % 60).padStart(2, "0")

    return `${hours}:${mins}:00`
  },

  rangeMatchesInfo(range, info) {
    return this.sameRange(range, {
      start: this.dateKey(info.start),
      end: this.dateKey(info.end),
    })
  },

  rangeMatchesCurrent(range) {
    const view = this.calendar?.view
    if (!view) return false

    return this.sameRange(range, {
      start: this.dateKey(view.activeStart),
      end: this.dateKey(view.activeEnd),
    })
  },

  sameRange(left, right) {
    return left?.start === right?.start && left?.end === right?.end
  },

  dateKey(value) {
    if (value instanceof Date) {
      const year = value.getFullYear()
      const month = String(value.getMonth() + 1).padStart(2, "0")
      const day = String(value.getDate()).padStart(2, "0")
      return `${year}-${month}-${day}`
    }

    if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}/.test(value)) {
      return value.slice(0, 10)
    }

    return ""
  },

  visibleEvents() {
    return this.events.filter(event => {
      return this.enabledSources.has(event.extendedProps?.source)
    })
  },

  updateVisibleCount() {
    if (!this.countEl) return

    const count = this.visibleEvents().length
    const singular = this.el.dataset.eventSingular || "1 event visible"
    const pluralLabel = this.el.dataset.eventPluralLabel || "events visible"

    this.countEl.textContent = count === 1 ? singular : `${count} ${pluralLabel}`
  },

  eventClasses(info) {
    const source = info.event.extendedProps?.source
    return [
      "konevo-calendar-event",
      this.timedGridView(info.view?.type) && "konevo-calendar-event--timed",
      SOURCE_CLASSES[source],
      info.event.extendedProps?.taskType && `konevo-calendar-event--task-type-${info.event.extendedProps.taskType}`,
      info.event.extendedProps?.status && `konevo-calendar-event--status-${info.event.extendedProps.status}`,
    ].filter(Boolean).join(" ")
  },

  eventContent(info) {
    const props = info.event.extendedProps || {}
    const timedGrid = this.timedGridView(info.view?.type)
    const inner = document.createElement("div")
    inner.className = [
      "konevo-calendar-event-inner",
      timedGrid && "konevo-calendar-event-inner--timed",
    ].filter(Boolean).join(" ")

    const topLine = document.createElement("div")
    topLine.className = "konevo-calendar-event-topline"

    const eyebrow = document.createElement("span")
    eyebrow.className = "konevo-calendar-event-eyebrow"

    if (props.source === "task") {
      const typeIcon = document.createElement("span")
      typeIcon.className = [
        "konevo-calendar-event-type-icon",
        TASK_TYPE_ICONS[props.taskType] || TASK_TYPE_ICONS.task,
      ].join(" ")
      eyebrow.append(typeIcon)
    }

    const typeLabel = document.createElement("span")
    typeLabel.className = "konevo-calendar-event-type-label"
    typeLabel.textContent = props.typeLabel || ""
    eyebrow.append(typeLabel)

    topLine.append(eyebrow)

    if (props.source === "task" && props.statusLabel) {
      const status = document.createElement("span")
      status.className = "konevo-calendar-event-chip konevo-calendar-event-chip--status"
      status.textContent = props.statusLabel
      topLine.append(status)
    }

    const title = document.createElement("div")
    title.className = "konevo-calendar-event-title"
    title.textContent = info.event.title || ""

    const footer = document.createElement("div")
    footer.className = "konevo-calendar-event-footer"

    const meta = document.createElement("span")
    meta.className = "konevo-calendar-event-meta"
    meta.textContent = props.meta || props.stage || ""
    if (meta.textContent) footer.append(meta)

    inner.append(topLine, title)
    if (footer.childElementCount) inner.append(footer)

    return {domNodes: [inner]}
  },

  timedGridView(viewType) {
    return viewType === "timeGridWeek" || viewType === "timeGridDay"
  },

  emptyContent() {
    const wrapper = document.createElement("div")
    wrapper.className = "konevo-calendar-empty"

    const title = document.createElement("div")
    title.className = "konevo-calendar-empty-title"
    title.textContent = this.el.dataset.noEventsTitle || "No planned work in this range"

    const subtitle = document.createElement("div")
    subtitle.className = "konevo-calendar-empty-subtitle"
    subtitle.textContent = this.el.dataset.noEventsSubtitle || ""

    wrapper.append(title, subtitle)
    return {domNodes: [wrapper]}
  },

  openEvent(info) {
    const url = info.event.url
    if (!url) return

    info.jsEvent.preventDefault()

    if (info.event.extendedProps?.source === "task") {
      const taskId = String(info.event.id || "").replace(/^task-/, "")
      if (taskId) {
        this.pushEvent("open_calendar_task", {id: taskId})
        return
      }
    }

    window.location.assign(url)
  },
}

export default FullCalendarPlanner
