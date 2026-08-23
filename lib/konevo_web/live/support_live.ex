defmodule KonevoWeb.SupportLive do
  use KonevoWeb, :live_view

  alias Konevo.Support

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Support"))
     |> assign(:support_form, Support.change_support_request() |> to_form(as: "support"))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :topic_options, support_topic_options())

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <div class="mx-auto max-w-3xl">
          <.form
            for={@support_form}
            id="support-form"
            phx-change="validate_support_request"
            phx-submit="send_support_request"
            class="space-y-5 rounded-xl border border-base-content/10 bg-base-100 p-5 shadow-sm sm:p-6"
          >
            <div class="flex items-start gap-3">
              <div class="flex size-11 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="icon-[tabler--lifebuoy]" class="size-5" />
              </div>
              <div>
                <h2 class="text-base font-semibold text-base-content">
                  {gettext("Contact support")}
                </h2>
                <p class="mt-1 text-sm leading-relaxed text-base-content/60">
                  {gettext("Send account, product, or billing questions for review.")}
                </p>
              </div>
            </div>

            <div class="grid gap-3 md:grid-cols-[14rem_minmax(0,1fr)]">
              <.input
                field={@support_form[:topic]}
                type="select"
                label={gettext("Topic")}
                options={@topic_options}
              />
              <.input
                field={@support_form[:subject]}
                type="text"
                label={gettext("Subject")}
                placeholder={gettext("Briefly describe the request")}
                maxlength="120"
                required
              />
            </div>

            <.input
              field={@support_form[:message]}
              type="textarea"
              label={gettext("Message")}
              placeholder={
                gettext("Share the details, what you expected, and anything already tried.")
              }
              rows="8"
              maxlength="4000"
              required
              class="textarea textarea-bordered min-h-56 w-full resize-y text-sm leading-relaxed"
            />

            <div class="flex justify-end border-t border-base-content/10 pt-4">
              <button
                type="submit"
                id="support-submit"
                class="btn btn-primary btn-sm w-full gap-1.5 sm:w-auto"
                phx-disable-with={gettext("Sending...")}
              >
                <.icon name="icon-[tabler--send]" class="size-4" />
                {gettext("Send request")}
              </button>
            </div>
          </.form>
        </div>
      </Layouts.page>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_support_request", %{"support" => params}, socket) do
    form =
      params
      |> Support.change_support_request()
      |> to_form(as: "support", action: :validate)

    {:noreply, assign(socket, :support_form, form)}
  end

  def handle_event("send_support_request", %{"support" => params}, socket) do
    case Support.deliver_support_request(socket.assigns.current_scope, params) do
      {:ok, _email} ->
        {:noreply,
         socket
         |> assign(:support_form, Support.change_support_request() |> to_form(as: "support"))
         |> put_flash(:success, gettext("Support request sent"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :support_form, to_form(changeset, as: "support", action: :insert))}

      {:error, :support_gmail_not_connected} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Connect the support Gmail account before using support")
         )}

      {:error, :gmail_reauthorization_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Reconnect the support Gmail account before using support")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not send support request"))}
    end
  end

  defp support_topic_options do
    [
      {gettext("Question"), "question"},
      {gettext("Bug"), "bug"},
      {gettext("Billing"), "billing"},
      {gettext("Feature request"), "feature"},
      {gettext("Other"), "other"}
    ]
  end
end
