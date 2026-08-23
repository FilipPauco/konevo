defmodule KonevoWeb.UserLive.Login do
  use KonevoWeb, :live_view

  @impl true
  def render(assigns) do
    subtitle =
      if assigns.current_scope do
        gettext("You need to reauthenticate to perform sensitive actions on your account.")
      else
        gettext("Sign in to your private Konevo workspace.")
      end

    assigns = assign(assigns, :subtitle, subtitle)

    ~H"""
    <Layouts.auth
      flash={@flash}
      current_scope={@current_scope}
      variant={:immersive}
      brand_placement={:inside}
    >
      <Layouts.auth_card id="login-card">
        <Layouts.auth_brand />
        <Layouts.auth_header title={gettext("Welcome back")} subtitle={@subtitle} />

        <div
          :if={@retry_after > 0}
          id="login-rate-limit"
          phx-hook=".RateLimitCountdown"
          phx-update="ignore"
          data-retry-after={@retry_after}
          data-submit-button-id="login-submit-button"
          role="status"
          aria-live="polite"
          class="flex gap-3 rounded-xl border border-warning/30 bg-warning/10 px-4 py-3 text-left shadow-sm"
        >
          <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-warning/15 text-warning">
            <.icon name="icon-[tabler--clock-hour-4]" class="size-4" />
          </div>
          <div class="min-w-0">
            <p class="text-sm font-semibold text-base-content">
              {gettext("Too many sign-in attempts")}
            </p>
            <p class="mt-0.5 text-sm leading-5 text-base-content/70">
              {gettext("Please wait")}
              <span data-countdown class="font-semibold tabular-nums text-base-content">
                {format_retry_after(@retry_after)}
              </span>
              {gettext("before trying again.")}
            </p>
          </div>
        </div>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
          class="space-y-5"
        >
          <div class="space-y-5">
            <.input
              readonly={!!@current_scope}
              field={@form[:email]}
              type="email"
              label={gettext("Email address")}
              placeholder={gettext("Enter your email address")}
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              placeholder="••••••••••••"
              autocomplete="current-password"
              spellcheck="false"
            />
          </div>
          <div class="space-y-6">
            <div class="flex items-center">
              <.input
                field={@form[:remember_me]}
                type="checkbox"
                label={gettext("Remember me")}
                class="checkbox checkbox-primary checkbox-xs mr-2"
              />
              <.link
                navigate={~p"/users/reset-password"}
                class="ml-auto text-sm font-medium text-primary transition-colors hover:text-primary/75 hover:underline"
              >
                {gettext("Forgot password?")}
              </.link>
            </div>
            <.button
              id="login-submit-button"
              class="btn btn-primary w-full transition-all disabled:cursor-not-allowed disabled:opacity-60"
              type="submit"
              disabled={@retry_after > 0}
            >
              {gettext("Sign in")}
            </.button>
          </div>
        </.form>
      </Layouts.auth_card>
    </Layouts.auth>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".RateLimitCountdown">
      export default {
        mounted() {
          let remaining = Number(this.el.dataset.retryAfter)
          const countdown = this.el.querySelector("[data-countdown]")
          const submitButton = document.getElementById(this.el.dataset.submitButtonId)

          const format = seconds => {
            const minutes = Math.floor(seconds / 60)
            return `${minutes}:${String(seconds % 60).padStart(2, "0")}`
          }

          const update = () => {
            if (remaining <= 0) {
              clearInterval(this.timer)
              this.el.remove()
              submitButton?.removeAttribute("disabled")
              return
            }

            countdown.textContent = format(remaining)
            remaining -= 1
          }

          update()
          this.timer = setInterval(update, 1000)
        },

        destroyed() {
          clearInterval(this.timer)
        }
      }
    </script>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       retry_after: rate_limit_retry_after(socket.assigns.flash),
       trigger_submit: false
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  defp rate_limit_retry_after(flash) do
    case Phoenix.Flash.get(flash, :rate_limit_retry_after) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {seconds, ""} when seconds > 0 -> seconds
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp format_retry_after(seconds) do
    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
