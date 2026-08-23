defmodule KonevoWeb.TenantInvitationLive.Accept do
  use KonevoWeb, :live_view

  alias Konevo.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      socket
      |> assign(:token, token)
      |> assign(:invitation, nil)
      |> assign(:existing_user?, false)
      |> assign(:form, invitation_form())

    if connected?(socket) do
      case Accounts.get_tenant_invitation(token) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, gettext("This invitation link is invalid or has expired"))
           |> push_navigate(to: ~p"/users/log-in")}

        invitation ->
          {:ok,
           socket
           |> assign(:invitation, invitation)
           |> assign(:existing_user?, Accounts.tenant_invitation_existing_user?(invitation))}
      end
    else
      {:ok, socket}
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
      <Layouts.auth_card id="tenant-invitation-card">
        <Layouts.auth_brand />
        <%= if @invitation do %>
          <Layouts.auth_header
            eyebrow={gettext("Workspace invitation")}
            title={
              if @existing_user?,
                do: gettext("Join %{organization}", organization: @invitation.organization.name),
                else: gettext("Set up %{organization}", organization: @invitation.organization.name)
            }
            subtitle={
              if @existing_user?,
                do: gettext("Use your existing Konevo password. Your account will stay the same."),
                else: gettext("Create the password for your Konevo account.")
            }
          />

          <div class="rounded-xl border border-base-content/10 bg-base-200/50 px-4 py-3 text-sm text-base-content/70">
            <span class="font-medium text-base-content">{gettext("Invited email:")}</span>
            {@invitation.email}
          </div>

          <.form
            for={@form}
            id="tenant-invitation-accept-form"
            action={~p"/tenant-invitations/#{@token}/accept"}
            class="space-y-4"
          >
            <.input
              field={@form[:password]}
              type="password"
              label={
                if @existing_user?, do: gettext("Your password"), else: gettext("Create password")
              }
              autocomplete={if @existing_user?, do: "current-password", else: "new-password"}
              required
              phx-mounted={JS.focus()}
            />
            <.input
              :if={not @existing_user?}
              field={@form[:password_confirmation]}
              type="password"
              label={gettext("Confirm password")}
              autocomplete="new-password"
              required
            />
            <p :if={not @existing_user?} class="text-xs leading-5 text-base-content/55">
              {gettext("Use 6–35 characters with uppercase, lowercase, and a number or symbol.")}
            </p>
            <.button
              id="tenant-invitation-accept-button"
              class="btn btn-primary w-full transition-transform hover:-translate-y-0.5"
              type="submit"
              phx-disable-with={gettext("Preparing workspace...")}
            >
              {if @existing_user?,
                do: gettext("Join workspace"),
                else: gettext("Create account and join")}
            </.button>
          </.form>
        <% else %>
          <div id="tenant-invitation-loading" class="space-y-3" aria-busy="true">
            <div class="skeleton mx-auto h-7 w-52 rounded-md" />
            <div class="skeleton mx-auto h-4 w-72 rounded-md" />
            <div class="skeleton h-12 w-full rounded-xl" />
          </div>
        <% end %>
      </Layouts.auth_card>
    </Layouts.auth>
    """
  end

  defp invitation_form do
    to_form(%{"password" => "", "password_confirmation" => ""}, as: "tenant_invitation")
  end
end
