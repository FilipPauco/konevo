import {Editor} from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"
import Underline from "@tiptap/extension-underline"
import Highlight from "@tiptap/extension-highlight"
import Link from "@tiptap/extension-link"
import TextAlign from "@tiptap/extension-text-align"
import {CodeBlockLowlight} from "@tiptap/extension-code-block-lowlight"
import {createPopper} from "@popperjs/core"
import {createLowlight} from "lowlight"
import {common} from "lowlight"
import hljs from "highlight.js/lib/core"
import bash from "highlight.js/lib/languages/bash"
import css from "highlight.js/lib/languages/css"
import elixir from "highlight.js/lib/languages/elixir"
import javascript from "highlight.js/lib/languages/javascript"
import json from "highlight.js/lib/languages/json"
import markdown from "highlight.js/lib/languages/markdown"
import plaintext from "highlight.js/lib/languages/plaintext"
import sql from "highlight.js/lib/languages/sql"
import typescript from "highlight.js/lib/languages/typescript"
import xml from "highlight.js/lib/languages/xml"

hljs.registerLanguage("bash", bash)
hljs.registerLanguage("css", css)
hljs.registerLanguage("elixir", elixir)
hljs.registerLanguage("html", xml)
hljs.registerLanguage("javascript", javascript)
hljs.registerLanguage("json", json)
hljs.registerLanguage("markdown", markdown)
hljs.registerLanguage("plaintext", plaintext)
hljs.registerLanguage("sql", sql)
hljs.registerLanguage("typescript", typescript)
hljs.registerLanguage("xml", xml)

const lowlight = createLowlight(common)

const TipTapRichText = {
  mounted() {
    this.editorId = this.el.id.replace(/-wrapper$/, "")
    this.el.dataset.unsavedSource = this.editorId
    this.input = this.el.querySelector("[data-tiptap-input]")
    this.editorTarget = this.el.querySelector("[data-tiptap-editor]")
    this.linkPopover = this.el.querySelector("[data-link-popover]")
    this.highlightPopover = this.el.querySelector("[data-highlight-popover]")
    this.headingPopover = this.el.querySelector("[data-heading-popover]")
    this.emojiPopover = this.el.querySelector("[data-emoji-popover]")
    this.popperInstances = {}
    this.closePopoversOutsideHandler = event => this.closePopoversOutside(event)
    this.initialContent = this.input.value || ""
    this.dirty = false

    this.editor = new Editor({
      element: this.editorTarget,
      content: this.input.value || "",
      extensions: [
        StarterKit.configure({
          codeBlock: false,
          horizontalRule: false,
        }),
        Underline,
        Highlight.configure({multicolor: true}),
        Link.configure({
          autolink: true,
          openOnClick: false,
          protocols: ["http", "https", "mailto", "tel"],
        }),
        TextAlign.configure({types: ["heading", "paragraph"]}),
        CodeBlockLowlight.configure({lowlight}),
        Placeholder.configure({
          placeholder: this.el.dataset.placeholder || "",
        }),
      ],
      editorProps: {
        attributes: {
          class: "tiptap-content min-h-[280px] px-4 py-3 text-sm leading-relaxed outline-none",
        },
        handleKeyDown: (_view, event) => this.handleKeydown(event),
      },
      onUpdate: ({editor}) => this.syncInput(editor),
      onSelectionUpdate: ({editor}) => this.updateActiveToolbar(editor),
      onTransaction: ({editor}) => this.updateActiveToolbar(editor),
    })

    this.setupToolbar()
    this.setupPopovers()
    this.externalCommandHandler = event => {
      const trigger = event.target.closest("[data-tiptap-command]")
      if (!trigger || trigger.dataset.tiptapTarget !== this.editorId) return

      event.preventDefault()
      this.runAction(trigger)
    }
    document.addEventListener("mousedown", this.externalCommandHandler)

    this.handleEvent("tiptap:clean", ({id}) => {
      if (id !== this.editorId) return

      this.initialContent = this.currentContent()
      this.setDirty(false)
    })
    this.handleEvent("tiptap:set-content", ({id, content}) => {
      if (id !== this.editorId) return

      const value = content || ""
      this.editor.commands.setContent(value, false)
      this.input.value = value
      this.initialContent = value
      this.setDirty(false)
    })
    this.updateActiveToolbar()
  },

  destroyed() {
    if (this.dirty) this.setDirty(false)
    document.removeEventListener("mousedown", this.externalCommandHandler)
    document.removeEventListener("mousedown", this.closePopoversOutsideHandler)
    this.editor?.destroy()
    Object.values(this.popperInstances).forEach(popper => popper?.destroy?.())
  },

  syncInput(editor) {
    const html = this.currentContent(editor)
    this.input.value = html
    this.input.dispatchEvent(new Event("input", {bubbles: true}))
    this.input.dispatchEvent(new Event("change", {bubbles: true}))
    this.setDirty(html !== this.initialContent)
  },

  setDirty(dirty) {
    if (this.dirty === dirty) return

    this.dirty = dirty
    const event = new CustomEvent("konevo:unsaved-change", {
      bubbles: true,
      detail: {dirty, source: this.editorId},
    })
    // Dispatch on el if still in DOM (mounted/updated), otherwise directly on document
    // (destroyed() is called after element removal, so el may be detached)
    ;(this.el.isConnected ? this.el : document).dispatchEvent(event)
  },

  currentContent(editor = this.editor) {
    return editor.isEmpty ? "" : editor.getHTML()
  },

  setupToolbar() {
    this.el.querySelectorAll("[data-action]").forEach(button => {
      button.addEventListener("mousedown", event => {
        event.preventDefault()
        this.runAction(button)
      })
    })
  },

  runAction(button) {
    const action = button.dataset.action
    const chain = this.editor.chain().focus()

    switch (action) {
      case "heading-toggle":
        this.togglePopover("heading", button)
        return
      case "bold":
        chain.toggleBold().run()
        break
      case "italic":
        chain.toggleItalic().run()
        break
      case "strike":
        chain.toggleStrike().run()
        break
      case "underline":
        chain.toggleUnderline().run()
        break
      case "highlight":
        this.togglePopover("highlight", button)
        return
      case "bulletList":
        chain.toggleBulletList().run()
        break
      case "orderedList":
        chain.toggleOrderedList().run()
        break
      case "codeblock":
        chain.toggleNode("codeBlock", "paragraph").run()
        break
      case "blockquote":
        chain.toggleBlockquote().run()
        break
      case "link":
        this.toggleLinkPopover(button)
        return
      case "emoji":
        this.togglePopover("emoji", button)
        return
      case "align-left":
        chain.setTextAlign("left").run()
        break
      case "align-center":
        chain.setTextAlign("center").run()
        break
      case "align-right":
        chain.setTextAlign("right").run()
        break
      case "align-justify":
        chain.setTextAlign("justify").run()
        break
      case "undo":
        this.editor.commands.undo()
        break
      case "redo":
        this.editor.commands.redo()
        break
    }

    this.updateActiveToolbar()
  },

  setupPopovers() {
    this.el.querySelectorAll("[data-heading-level]").forEach(button => {
      button.addEventListener("click", event => {
        event.preventDefault()
        const level = Number.parseInt(button.dataset.headingLevel, 10)
        const chain = this.editor.chain().focus()

        if (level === 0) {
          chain.setParagraph().run()
        } else {
          chain.toggleHeading({level}).run()
        }

        this.closePopover("heading")
        this.updateActiveToolbar()
      })
    })

    this.el.querySelectorAll("[data-highlight-color]").forEach(button => {
      button.addEventListener("click", event => {
        event.preventDefault()
        const color = button.dataset.highlightColor
        const chain = this.editor.chain().focus()

        if (color === "unset") {
          chain.unsetHighlight().run()
        } else {
          chain.setHighlight({color}).run()
        }

        this.closePopover("highlight")
        this.updateActiveToolbar()
      })
    })

    this.el.querySelectorAll("[data-emoji]").forEach(button => {
      button.addEventListener("click", event => {
        event.preventDefault()
        this.editor.chain().focus().insertContent(button.dataset.emoji).run()
        this.closePopover("emoji")
        this.updateActiveToolbar()
      })
    })

    this.el.querySelector("[data-link-apply]")?.addEventListener("click", event => {
      event.preventDefault()
      this.applyLink()
    })

    this.el.querySelector("[data-link-remove]")?.addEventListener("click", event => {
      event.preventDefault()
      this.editor.chain().focus().unsetLink().run()
      this.closePopover("link")
      this.updateActiveToolbar()
    })

    this.el.querySelector("[data-link-open]")?.addEventListener("click", event => {
      event.preventDefault()
      const href = this.editor.getAttributes("link").href
      if (href) window.open(href, "_blank", "noopener,noreferrer")
    })

    this.el.querySelectorAll("[data-link-input]").forEach(input => {
      input.addEventListener("keydown", event => {
        if (event.key === "Enter") {
          event.preventDefault()
          this.applyLink()
        }
      })
    })

    document.addEventListener("mousedown", this.closePopoversOutsideHandler)

  },

  closePopoversOutside(event) {
    const target = event.target

    ;["link", "highlight", "heading", "emoji"].forEach(name => {
      const popover = this.getPopover(name)
      if (!popover || popover.classList.contains("hidden")) return

      const clickedPopover = popover.contains(target)
      const clickedTrigger = target.closest(`[data-action="${name}"]`)

      if (!clickedPopover && !clickedTrigger) {
        this.closePopover(name)
      }
    })
  },

  toggleLinkPopover(button) {
    if (!this.linkPopover.classList.contains("hidden")) {
      this.closePopover("link")
      return
    }

    if (this.editor.isActive("link") && this.editor.state.selection.empty) {
      this.editor.commands.extendMarkRange("link")
    }

    const urlInput = this.el.querySelector("[data-link-url]")
    const textInput = this.el.querySelector("[data-link-text]")
    const selection = this.editor.state.selection
    const selectedText = selection.empty
      ? ""
      : this.editor.state.doc.textBetween(selection.from, selection.to, " ")

    urlInput.value = this.editor.getAttributes("link").href || ""
    textInput.value = selectedText

    this.openPopover("link", button)
    urlInput.focus({preventScroll: true})
  },

  applyLink() {
    const url = this.el.querySelector("[data-link-url]").value.trim()
    const text = this.el.querySelector("[data-link-text]").value.trim()

    if (url === "") {
      this.editor.chain().focus().unsetLink().run()
      this.closePopover("link")
      return
    }

    if (text !== "") {
      this.editor
        .chain()
        .focus()
        .insertContent([{type: "text", text, marks: [{type: "link", attrs: {href: url}}]}])
        .unsetMark("link")
        .run()
    } else {
      this.editor.chain().focus().setLink({href: url}).run()
    }

    this.closePopover("link")
    this.updateActiveToolbar()
  },

  togglePopover(name, button) {
    const popover = this.getPopover(name)
    if (!popover) return

    if (popover.classList.contains("hidden")) {
      this.openPopover(name, button)
    } else {
      this.closePopover(name)
    }
  },

  openPopover(name, button) {
    const popover = this.getPopover(name)
    if (!popover) return

    popover.classList.remove("hidden")
    this.popperInstances[name]?.destroy?.()
    this.popperInstances[name] = createPopper(button, popover, {
      placement: name === "heading" ? "bottom-start" : "bottom",
      strategy: "fixed",
      modifiers: [
        {name: "offset", options: {offset: [0, 8]}},
        {name: "preventOverflow", options: {boundary: "viewport", padding: 12}},
      ],
    })
  },

  closePopover(name) {
    this.getPopover(name)?.classList.add("hidden")
  },

  getPopover(name) {
    return {
      link: this.linkPopover,
      highlight: this.highlightPopover,
      heading: this.headingPopover,
      emoji: this.emojiPopover,
    }[name]
  },

  updateActiveToolbar(editor = this.editor) {
    if (!editor) return

    const activeTypes = ["bold", "italic", "strike", "underline", "highlight", "bulletList", "orderedList", "link", "blockquote"]

    activeTypes.forEach(type => {
      this.setButtonActive(type, editor.isActive(type))
    })

    this.setButtonActive("codeblock", editor.isActive("codeBlock"))

    ;["left", "center", "right", "justify"].forEach(alignment => {
      this.setButtonActive(`align-${alignment}`, editor.isActive({textAlign: alignment}))
    })

    const label = this.el.querySelector("[data-heading-label]")
    if (!label) return

    const activeHeading = [1, 2, 3, 4].find(level => editor.isActive("heading", {level}))
    label.textContent = activeHeading ? `Heading ${activeHeading}` : "Normal Text"
  },

  setButtonActive(action, active) {
    this.el.querySelectorAll(`[data-action="${action}"]`).forEach(button => {
      button.dataset.active = active ? "true" : "false"
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })
  },

  handleKeydown(event) {
    const {key, metaKey, ctrlKey, shiftKey, altKey} = event
    const isMod = metaKey || ctrlKey
    if (!isMod) return false

    const k = key.toLowerCase()
    const run = callback => {
      event.preventDefault()
      callback()
      this.updateActiveToolbar()
      return true
    }

    if (!shiftKey && !altKey && k === "k") {
      event.preventDefault()
      this.toggleLinkPopover(this.el.querySelector('[data-action="link"]'))
      return true
    }

    if (!shiftKey && !altKey && k === "b") return run(() => this.editor.chain().focus().toggleBold().run())
    if (!shiftKey && !altKey && k === "i") return run(() => this.editor.chain().focus().toggleItalic().run())
    if (!shiftKey && !altKey && k === "u") return run(() => this.editor.chain().focus().toggleUnderline().run())
    if (shiftKey && !altKey && k === "x") return run(() => this.editor.chain().focus().toggleStrike().run())
    if (shiftKey && !altKey && k === "8") return run(() => this.editor.chain().focus().toggleBulletList().run())
    if (shiftKey && !altKey && k === "7") return run(() => this.editor.chain().focus().toggleOrderedList().run())
    if (!shiftKey && altKey && k === "c") return run(() => this.editor.chain().focus().toggleNode("codeBlock", "paragraph").run())
    if (shiftKey && !altKey && k === "b") return run(() => this.editor.chain().focus().toggleBlockquote().run())

    if (!shiftKey && altKey && ["1", "2", "3", "4"].includes(k)) {
      return run(() => this.editor.chain().focus().toggleHeading({level: Number.parseInt(k, 10)}).run())
    }

    if (shiftKey && !altKey && ["l", "c", "r", "j"].includes(k)) {
      const alignment = {l: "left", c: "center", r: "right", j: "justify"}[k]
      return run(() => this.editor.chain().focus().setTextAlign(alignment).run())
    }

    return false
  },
}

export default TipTapRichText
