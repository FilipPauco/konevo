defmodule KonevoWeb.GmailAuthController do
  @moduledoc """
  Handles the Gmail OAuth2 connect/callback flow.

  The `connect/2` action redirects the user to Google's consent screen.
  The `callback/2` action exchanges the authorization code for tokens,
  stores them on the integration record, and triggers an initial sync.
  """

  use KonevoWeb, :controller

  require Logger

  alias Konevo.Accounts
  alias Konevo.Accounts.Scope
  alias Konevo.Inbox
  alias Konevo.Inbox.GmailClient
  alias Konevo.Oban, as: KonevoOban
  alias Konevo.Permissions
  alias Konevo.Workers.GmailSyncWorker

  @doc """
  Renders the Gmail data-use disclosure shown immediately before Google consent.

  Google requires this in-product disclosure in addition to the public privacy policy.
  """
  def consent(conn, _params) do
    render(conn, :consent)
  end

  @doc """
  Records the user's acknowledgement and continues to the Google authorization flow.
  """
  def confirm_consent(conn, %{"gmail" => %{"acknowledged" => "true"}}) do
    conn
    |> put_session(:gmail_oauth_disclosure_confirmed, true)
    |> redirect(to: ~p"/integrations/gmail/connect")
  end

  def confirm_consent(conn, _params) do
    conn
    |> put_flash(
      :error,
      gettext("Please acknowledge the Gmail data-use notice before continuing")
    )
    |> redirect(to: ~p"/integrations/gmail/consent")
  end

  @doc """
  Redirects to Google's OAuth2 consent screen after the in-product disclosure is acknowledged.

  Stores a random CSRF state token and the org_id in the session so the
  callback can verify the request and load the correct org context.
  """
  def connect(conn, _params) do
    case get_session(conn, :gmail_oauth_disclosure_confirmed) do
      true -> start_authorization(conn)
      _ -> redirect(conn, to: ~p"/integrations/gmail/consent")
    end
  end

  @doc """
  Handles the OAuth2 callback from Google.

  Verifies CSRF state, exchanges the code for tokens, resolves the org from
  session, upserts the integration, and triggers an initial Gmail sync.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    session_state = get_session(conn, :gmail_oauth_state)
    org_id = get_session(conn, :gmail_oauth_org_id)
    return_to = get_session(conn, :gmail_oauth_return_to) || "/settings"

    cond do
      state != session_state ->
        conn
        |> delete_oauth_session()
        |> put_flash(:error, gettext("Invalid OAuth state. Please try again"))
        |> redirect(external: return_to)

      is_nil(org_id) ->
        conn
        |> delete_oauth_session()
        |> put_flash(:error, gettext("Session expired. Please try connecting again"))
        |> redirect(external: return_to)

      true ->
        do_callback(conn, code, org_id, return_to)
    end
  end

  def callback(conn, %{"error" => error}) do
    return_to = get_session(conn, :gmail_oauth_return_to) || "/settings"

    Logger.warning("Gmail OAuth cancelled or denied: #{error}")

    conn
    |> delete_oauth_session()
    |> put_flash(:info, gettext("Gmail connection was cancelled"))
    |> redirect(external: return_to)
  end

  # Fallback for unexpected callback params
  def callback(conn, _params) do
    conn
    |> delete_oauth_session()
    |> put_flash(:error, gettext("Unexpected OAuth callback. Please try again"))
    |> redirect(to: ~p"/settings")
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp start_authorization(conn) do
    state = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    scope = conn.assigns.current_scope
    return_to = build_return_url(conn, "/settings")
    url = GmailClient.authorize_url(state)

    conn
    |> delete_session(:gmail_oauth_disclosure_confirmed)
    |> put_session(:gmail_oauth_state, state)
    |> put_session(:gmail_oauth_org_id, scope.org.id)
    |> put_session(:gmail_oauth_return_to, return_to)
    |> redirect(external: url)
  end

  defp do_callback(conn, code, org_id, return_to) do
    user = conn.assigns.current_scope.user

    with {:ok, org} <- load_org(org_id),
         {:ok, membership} <- load_membership(user, org),
         scope = Scope.for_user_in_org(user, org, membership),
         {:ok, tokens} <- GmailClient.exchange_code(code),
         {:ok, email} <- GmailClient.get_user_email(tokens["access_token"]),
         expires_at = token_expires_at(tokens["expires_in"]),
         token_attrs = %{
           access_token: tokens["access_token"],
           refresh_token: tokens["refresh_token"],
           token_expires_at: expires_at
         },
         {:ok, integration} <- Inbox.connect_gmail(scope, email, token_attrs) do
      %{"integration_id" => integration.id}
      |> GmailSyncWorker.new()
      |> KonevoOban.insert()

      conn
      |> delete_oauth_session()
      |> put_flash(:success, gettext("Gmail connected as %{email}", email: email))
      |> redirect(external: return_to)
    else
      {:error, reason} ->
        Logger.error("Gmail OAuth callback failed: #{inspect(reason)}")

        conn
        |> delete_oauth_session()
        |> put_flash(:error, gettext("Failed to connect Gmail. Please try again"))
        |> redirect(external: return_to)
    end
  end

  defp load_org(org_id) do
    case Accounts.get_organization!(org_id) do
      org -> {:ok, org}
    end
  rescue
    Ecto.NoResultsError -> {:error, :org_not_found}
  end

  defp load_membership(user, org) do
    case Permissions.get_membership(user, org) do
      nil -> {:error, :no_membership}
      membership -> {:ok, membership}
    end
  end

  defp token_expires_at(nil), do: nil

  defp token_expires_at(expires_in) when is_integer(expires_in),
    do: DateTime.add(DateTime.utc_now(:second), expires_in, :second)

  defp token_expires_at(expires_in) when is_binary(expires_in),
    do: token_expires_at(String.to_integer(expires_in))

  defp build_return_url(conn, path) do
    scheme = Atom.to_string(conn.scheme)
    host = conn.host
    port = conn.port

    port_suffix =
      cond do
        scheme == "http" and port == 80 -> ""
        scheme == "https" and port == 443 -> ""
        true -> ":#{port}"
      end

    "#{scheme}://#{host}#{port_suffix}#{path}"
  end

  defp delete_oauth_session(conn) do
    conn
    |> delete_session(:gmail_oauth_state)
    |> delete_session(:gmail_oauth_org_id)
    |> delete_session(:gmail_oauth_return_to)
    |> delete_session(:gmail_oauth_disclosure_confirmed)
  end
end
