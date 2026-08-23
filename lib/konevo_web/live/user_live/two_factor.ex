defmodule KonevoWeb.UserLive.TwoFactor do
  use KonevoWeb, :live_view

  alias KonevoWeb.UserAuth

  @impl true
  def mount(_params, session, socket) do
    case UserAuth.two_factor_challenge_user(session) do
      {:ok, _user} ->
        {:ok,
         assign(socket,
           form: to_form(%{"code" => ""}, as: "two_factor"),
           retry_after: rate_limit_retry_after(socket.assigns.flash)
         )}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Your verification session expired. Please sign in again."))
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth
      flash={@flash}
      current_scope={@current_scope}
      variant={:immersive}
      brand_placement={:inside}
    >
      <section
        id="two-factor-card"
        class="mx-auto w-full max-w-md rounded-2xl border border-secondary/35 bg-base-100/95 p-6 shadow-2xl shadow-base-content/10 backdrop-blur sm:p-8"
      >
        <Layouts.auth_brand />
        <div class="mt-5 text-center">
          <div class="mx-auto flex size-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
            <.icon name="icon-[tabler--shield-lock]" class="size-6" />
          </div>
          <h1 class="mt-4 text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Verify your sign-in")}
          </h1>
          <p class="mt-2 text-sm leading-6 text-base-content/65">
            {gettext("Enter the six-digit code from your authenticator app.")}
          </p>
        </div>

        <div
          :if={@retry_after > 0}
          id="two-factor-rate-limit"
          data-retry-after={@retry_after}
          role="status"
          class="mt-5 rounded-xl border border-warning/30 bg-warning/10 px-4 py-3 text-sm text-base-content/75"
        >
          {gettext("Too many attempts. Please wait before trying again.")}
        </div>

        <.form
          for={@form}
          id="two-factor-form"
          action={~p"/users/two-factor"}
          method="post"
          class="mt-6 space-y-5"
        >
          <.input
            field={@form[:code]}
            type="text"
            label={gettext("Authentication code")}
            placeholder="000000"
            inputmode="numeric"
            autocomplete="one-time-code"
            maxlength="6"
            pattern="[0-9]{6}"
            required
            autofocus
            class="input input-bordered w-full text-center font-mono text-2xl tracking-[0.5em]"
          />
          <button
            id="two-factor-submit"
            type="submit"
            class="btn btn-primary w-full"
            disabled={@retry_after > 0}
          >
            <.icon name="icon-[tabler--shield-check]" class="size-4" />
            {gettext("Verify and continue")}
          </button>
        </.form>
        <.link
          navigate={~p"/users/log-in"}
          class="mt-5 block text-center text-sm font-medium text-base-content/60 transition-colors hover:text-primary"
        >
          {gettext("Use a different account")}
        </.link>
      </section>
    </Layouts.auth>
    """
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
end
