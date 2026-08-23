defmodule Konevo.Inbox.GmailClient do
  @moduledoc """
  Thin Req-based wrapper around the Gmail REST API and Google OAuth2 endpoints.

  All API calls are synchronous and return `{:ok, body}` or `{:error, reason}`.
  Token refresh and API calls should happen inside Oban workers, never in a LiveView process.
  """

  @auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @userinfo_url "https://openidconnect.googleapis.com/v1/userinfo"
  @gmail_base "https://gmail.googleapis.com/gmail/v1/users/me"
  @calendar_base "https://www.googleapis.com/calendar/v3"

  @scopes ~w(
    https://www.googleapis.com/auth/gmail.modify
    https://www.googleapis.com/auth/gmail.send
    https://www.googleapis.com/auth/gmail.settings.basic
    https://www.googleapis.com/auth/calendar.events.readonly
    https://www.googleapis.com/auth/userinfo.email
    openid
  )

  # ---------------------------------------------------------------------------
  # OAuth2
  # ---------------------------------------------------------------------------

  @doc """
  Builds the Google OAuth2 authorization URL.

  `state` is a random CSRF token you generate and store in the session before
  redirecting. Google will echo it back on the callback.
  """
  def authorize_url(state) do
    params = %{
      client_id: client_id(),
      redirect_uri: redirect_uri(),
      response_type: "code",
      scope: Enum.join(@scopes, " "),
      access_type: "offline",
      prompt: "consent",
      state: state
    }

    @auth_url <> "?" <> URI.encode_query(params)
  end

  @doc """
  Exchanges an authorization code for access + refresh tokens.

  Returns `{:ok, %{"access_token" => _, "refresh_token" => _, "expires_in" => _}}`.
  """
  def exchange_code(code) do
    Req.post(@token_url,
      form: %{
        code: code,
        client_id: client_id(),
        client_secret: client_secret(),
        redirect_uri: redirect_uri(),
        grant_type: "authorization_code"
      }
    )
    |> unwrap_response()
  end

  @doc """
  Uses a refresh token to obtain a new access token.

  Returns `{:ok, %{"access_token" => _, "expires_in" => _}}`.
  """
  def refresh_access_token(refresh_token) do
    Req.post(@token_url,
      form: %{
        refresh_token: refresh_token,
        client_id: client_id(),
        client_secret: client_secret(),
        grant_type: "refresh_token"
      }
    )
    |> unwrap_response()
  end

  def invalid_grant?(%{"error" => "invalid_grant"}), do: true
  def invalid_grant?({:token_refresh_failed, reason}), do: invalid_grant?(reason)
  def invalid_grant?(_reason), do: false

  @doc """
  Fetches the authenticated user's email address from the OpenID userinfo endpoint.
  """
  def get_user_email(access_token) do
    case Req.get(@userinfo_url, auth: {:bearer, access_token}) do
      {:ok, %{status: 200, body: %{"email" => email}}} -> {:ok, email}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Gmail API
  # ---------------------------------------------------------------------------

  @doc """
  Lists thread metadata for the user's inbox.

  Options:
    - `:max_results` – max threads to return (default 50)
    - `:q`           – Gmail search query (default "in:inbox")
    - `:page_token`  – for pagination
  """
  def list_threads(access_token, opts \\ []) do
    params =
      %{maxResults: Keyword.get(opts, :max_results, 50)}
      |> maybe_put(:q, Keyword.get(opts, :q, "in:inbox"))
      |> maybe_put(:pageToken, Keyword.get(opts, :page_token))

    Req.get(@gmail_base <> "/threads",
      auth: {:bearer, access_token},
      params: params
    )
    |> unwrap_response()
  end

  @doc """
  Fetches a full thread including all messages and headers.
  """
  def get_thread(access_token, thread_id) do
    Req.get(@gmail_base <> "/threads/#{thread_id}",
      auth: {:bearer, access_token},
      params: %{format: "full"}
    )
    |> unwrap_response()
  end

  @doc """
  Fetches a message attachment body.
  """
  def get_attachment(access_token, message_id, attachment_id) do
    Req.get(@gmail_base <> "/messages/#{message_id}/attachments/#{attachment_id}",
      auth: {:bearer, access_token}
    )
    |> unwrap_response()
  end

  @doc """
  Sends a raw RFC2822 message. `raw` should be a base64url-encoded string.

  Options:
    - `:thread_id` – Gmail thread ID to keep the message in an existing thread
  """
  def send_message(access_token, raw_message, opts \\ []) do
    body =
      case Keyword.get(opts, :thread_id) do
        nil -> %{raw: raw_message}
        thread_id -> %{raw: raw_message, threadId: thread_id}
      end

    Req.post(@gmail_base <> "/messages/send",
      auth: {:bearer, access_token},
      json: body
    )
    |> unwrap_response()
  end

  @doc """
  Adds or removes labels from every message in a Gmail thread.
  """
  def modify_thread_labels(access_token, thread_id, opts \\ []) when is_binary(thread_id) do
    Req.post(@gmail_base <> "/threads/#{thread_id}/modify",
      auth: {:bearer, access_token},
      json: %{
        addLabelIds: Keyword.get(opts, :add_label_ids, []),
        removeLabelIds: Keyword.get(opts, :remove_label_ids, [])
      }
    )
    |> unwrap_response()
  end

  @doc """
  Fetches the primary Gmail send-as signature.
  """
  def fetch_primary_signature(access_token) do
    case Req.get(@gmail_base <> "/settings/sendAs", auth: {:bearer, access_token}) do
      {:ok, %{status: 200, body: %{"sendAs" => aliases}}} ->
        aliases
        |> Enum.find(& &1["isPrimary"])
        |> case do
          %{"signature" => signature} -> {:ok, signature}
          _alias -> {:ok, nil}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Google Calendar API
  # ---------------------------------------------------------------------------

  @doc """
  Lists visible events from the authenticated user's primary Google Calendar.
  """
  def list_calendar_events(access_token, starts_at, ends_at, opts \\ []) do
    params =
      %{
        timeMin: DateTime.to_iso8601(starts_at),
        timeMax: DateTime.to_iso8601(ends_at),
        singleEvents: true,
        orderBy: "startTime",
        showDeleted: false,
        maxResults: Keyword.get(opts, :max_results, 250)
      }
      |> maybe_put(:pageToken, Keyword.get(opts, :page_token))

    Req.get(@calendar_base <> "/calendars/primary/events",
      auth: {:bearer, access_token},
      params: params
    )
    |> unwrap_response()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp unwrap_response({:ok, %{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp unwrap_response({:ok, %{status: _status, body: body}}), do: {:error, body}
  defp unwrap_response({:error, reason}), do: {:error, reason}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp client_id, do: Application.get_env(:konevo, :google_oauth)[:client_id]
  defp client_secret, do: Application.get_env(:konevo, :google_oauth)[:client_secret]
  defp redirect_uri, do: Application.get_env(:konevo, :google_oauth)[:redirect_uri]
end
