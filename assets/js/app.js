// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// FlyonUI JS for interactive components (accordion, dropdown, modal, etc.)
import "flyonui/flyonui"
import _ from "lodash"

window._ = _

import live_select from "live_select"
import FlatpickrHook from "./hooks/flatpickr"
import DateRangePickerHook from "./hooks/date_range_picker"
import FormSelectHook from "./hooks/form_select"
import RowMenuHook from "./hooks/row_menu"
import ImageLightboxHook from "./hooks/image_lightbox"
import TiptapEditorHook from "./hooks/tiptap_editor"
import FlashToastHook from "./hooks/flash_toast"
import {AutoResize} from "./hooks/auto_resize"
import FilterPanelHook from "./hooks/filter_panel"
import NameTipHook from "./hooks/name_tip"
import SortableKanban from "./hooks/sortable_kanban"
import DrawerBodyHook from "./hooks/drawer_body"
import RangeInputHook from "./hooks/range_input"
import FullCalendarPlannerHook from "./hooks/fullcalendar_planner"
import ScheduleDropdownHook from "./hooks/schedule_dropdown"
import EmailSelectionActionsHook from "./hooks/email_selection_actions"
import CollapsiblePanelHook from "./hooks/collapsible_panel"

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/konevo"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
    viewport: window.matchMedia("(min-width: 640px)").matches ? "desktop" : "mobile",
  },
  hooks: {...colocatedHooks, ...live_select, Flatpickr: FlatpickrHook, DateRangePicker: DateRangePickerHook, FormSelect: FormSelectHook, AutoResize, RowMenu: RowMenuHook, ImageLightbox: ImageLightboxHook, TiptapEditor: TiptapEditorHook, TipTapRichText: TiptapEditorHook, FlashToast: FlashToastHook, NameTip: NameTipHook, FilterPanel: FilterPanelHook, SortableKanban, DrawerBody: DrawerBodyHook, RangeInput: RangeInputHook, FullCalendarPlanner: FullCalendarPlannerHook, ScheduleDropdown: ScheduleDropdownHook, EmailSelectionActions: EmailSelectionActionsHook, CollapsiblePanel: CollapsiblePanelHook},
})

window.addEventListener("phx:inbox-thread-selection", event => {
  const selectedIds = new Set((event.detail?.ids || []).map(id => String(id)))

  document.querySelectorAll("[data-inbox-thread-select]").forEach(input => {
    input.checked = selectedIds.has(input.dataset.inboxThreadSelect)
  })
})

window.addEventListener("phx:inbox:scroll-to-reply", () => {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      const reply = document.getElementById("reply-composer") || document.getElementById("reply-form")

      reply?.scrollIntoView({behavior: "smooth", block: "end"})
    })
  })
})

window.addEventListener("click", event => {
  const trigger = event.target.closest("[data-schedule-preset-target]")
  if (!trigger) return

  const input = document.getElementById(trigger.dataset.schedulePresetTarget)
  if (!input) return

  input.value = trigger.dataset.schedulePresetValue || ""
})

const installUnsavedChangesGuard = () => {
  const dirtySources = new Set()
  let allowNavigation = false
  let pendingLink = null
  let pendingAction = null
  const formBaselines = new WeakMap()

  const modal = () => document.querySelector("[data-unsaved-modal]")
  const backdrop = () => document.querySelector("[data-unsaved-backdrop]")
  const sourceElement = source =>
    document.querySelector(`[data-unsaved-source="${source}"]`) ||
    document.getElementById(source)
  const sourceActive = source => {
    if (source === "global") return true

    const element = sourceElement(source)
    if (!element) return false

    const drawer = element.closest("#task-drawer")
    if (drawer) return drawer.classList.contains("drawer-open")

    return true
  }

  const activeDirty = () => {
    for (const source of [...dirtySources]) {
      if (!sourceActive(source)) dirtySources.delete(source)
    }

    return dirtySources.size > 0
  }

  const setDirty = (value, source = "global") => {
    if (value) {
      dirtySources.add(source)
    } else {
      dirtySources.delete(source)
    }

    document.documentElement.toggleAttribute("data-unsaved-changes", activeDirty())
  }

  const formSnapshot = form => JSON.stringify([...new window.FormData(form).entries()])
  const formSource = form => form.id || "global"
  const trackForm = form => {
    if (!formBaselines.has(form)) formBaselines.set(form, formSnapshot(form))
  }
  const updateFormDirty = form => {
    trackForm(form)
    setDirty(formSnapshot(form) !== formBaselines.get(form), formSource(form))
  }
  const trackForms = () => {
    document.querySelectorAll("form[data-unsaved-form]").forEach(trackForm)
  }

  const hideModal = () => {
    modal()?.classList.add("hidden")
    backdrop()?.classList.add("hidden")
    pendingLink = null
    pendingAction = null
  }

  const showModal = ({link = null, action = null} = {}) => {
    pendingLink = link
    pendingAction = action
    modal()?.classList.remove("hidden")
    backdrop()?.classList.remove("hidden")
    document.querySelector("[data-unsaved-stay]")?.focus()
  }

  document.addEventListener("konevo:unsaved-change", event => {
    setDirty(!!event.detail?.dirty, event.detail?.source || "global")
  })

  document.addEventListener("phx:update", trackForms)
  document.addEventListener("focusin", event => {
    const form = event.target.closest?.("form[data-unsaved-form]")
    if (form) trackForm(form)
  })
  document.addEventListener("input", event => {
    const form = event.target.closest?.("form[data-unsaved-form]")
    if (form) updateFormDirty(form)
  })
  document.addEventListener("change", event => {
    const form = event.target.closest?.("form[data-unsaved-form]")
    if (form) updateFormDirty(form)
  })

  document.addEventListener("click", event => {
    if (event.target.closest("[data-unsaved-stay]")) {
      hideModal()
      return
    }

    if (event.target.closest("[data-unsaved-leave]")) {
      const link = pendingLink
      const action = pendingAction
      hideModal()
      dirtySources.clear()
      document.documentElement.removeAttribute("data-unsaved-changes")

      if (action) {
        allowNavigation = true
        action.click()
        setTimeout(() => {
          allowNavigation = false
        }, 0)
        return
      }

      if (!link) return

      allowNavigation = true
      link.click()
      setTimeout(() => {
        allowNavigation = false
      }, 0)
      return
    }

    if (!activeDirty() || allowNavigation) return

    const guardedAction = event.target.closest("[data-unsaved-confirm]")
    if (guardedAction) {
      event.preventDefault()
      event.stopImmediatePropagation()
      showModal({action: guardedAction})
      return
    }

    const link = event.target.closest("a[href]")
    if (!link || link.target === "_blank" || link.getAttribute("href") === "#") return

    event.preventDefault()
    event.stopImmediatePropagation()
    showModal({link})
  }, true)

  window.addEventListener("beforeunload", event => {
    if (!activeDirty()) return

    event.preventDefault()
    event.returnValue = ""
  })
}

installUnsavedChangesGuard()

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
