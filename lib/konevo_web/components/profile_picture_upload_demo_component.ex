defmodule KonevoWeb.Components.ProfilePictureUploadDemoComponent do
  @moduledoc """
  FlyonUI-style local profile picture upload preview demo.
  """

  use KonevoWeb, :html

  attr :id, :string, required: true

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-box border border-base-200 bg-base-100 p-5 shadow-sm"
      phx-hook=".ProfilePicturePreview"
      phx-update="ignore"
    >
      <input id={"#{@id}-input"} type="file" accept="image/*" class="sr-only" />

      <div class="flex flex-wrap items-center gap-3 sm:gap-5">
        <div class="relative flex size-20 shrink-0 items-center justify-center overflow-hidden rounded-full border-2 border-dotted border-base-content/30 bg-base-200/40 text-base-content/50">
          <span data-placeholder>
            <.icon name="icon-[tabler--user-square]" class="size-9 shrink-0" />
          </span>
          <img class="hidden size-full object-cover" alt="Selected profile preview" data-preview />
        </div>

        <div class="grow">
          <p class="mb-3 text-sm text-base-content/60">
            {gettext("Choose one JPG, PNG, GIF, or WebP image.")}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <label for={"#{@id}-input"} class="btn btn-primary cursor-pointer gap-2">
              <.icon name="icon-[tabler--upload]" class="size-4 shrink-0" />
              {gettext("Upload photo")}
            </label>
            <button type="button" class="btn btn-error btn-danger" data-clear disabled>
              {gettext("Delete")}
            </button>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ProfilePicturePreview">
        export default {
          mounted() {
            this.input = this.el.querySelector('input[type="file"]')
            this.preview = this.el.querySelector('[data-preview]')
            this.placeholder = this.el.querySelector('[data-placeholder]')
            this.clearButton = this.el.querySelector('[data-clear]')
            this.objectUrl = null

            this.input.addEventListener('change', () => this.showPreview())
            this.clearButton.addEventListener('click', () => this.clearPreview())
          },

          destroyed() {
            this.revokeObjectUrl()
          },

          showPreview() {
            const [file] = this.input.files
            if (!file) return

            this.revokeObjectUrl()
            this.objectUrl = URL.createObjectURL(file)
            this.preview.src = this.objectUrl
            this.preview.classList.remove('hidden')
            this.placeholder.classList.add('hidden')
            this.clearButton.disabled = false
          },

          clearPreview() {
            this.input.value = ''
            this.preview.removeAttribute('src')
            this.preview.classList.add('hidden')
            this.placeholder.classList.remove('hidden')
            this.clearButton.disabled = true
            this.revokeObjectUrl()
          },

          revokeObjectUrl() {
            if (!this.objectUrl) return
            URL.revokeObjectURL(this.objectUrl)
            this.objectUrl = null
          }
        }
      </script>
    </div>
    """
  end
end
