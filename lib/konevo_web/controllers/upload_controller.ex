defmodule KonevoWeb.UploadController do
  @moduledoc """
  Authenticated file serving for uploaded files.

  All file access is gated by this controller, not served via static files.
  Each request re-validates authorization before serving.
  """

  use KonevoWeb, :controller

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Konevo.Inbox.Email
  alias Konevo.Permissions
  alias Konevo.Repo
  alias Konevo.Tasks.Task
  alias Konevo.Uploads.{UploadConfig, UploadedFile, UploadPath}

  plug :authorize_request

  @doc """
  Serve a file by context and file ID.

  Route: GET /uploads/:context/:id

  Authorization checks:
  1. Tenant isolation (outermost gate)
  2. Context-specific ownership/permission rules
  3. Defense-in-depth path containment checks
  """
  def show(conn, %{"context" => context_str, "id" => file_id}) do
    with {:ok, context} <- UploadConfig.cast_context(context_str),
         {:ok, file} <- fetch_file(file_id, context),
         :ok <- check_tenant_isolation(conn, file),
         :ok <- check_authorization(conn, file),
         {:ok, validated_path} <-
           UploadPath.resolve_for_serving(file.storage_path, file.tenant_id) do
      serve_file(conn, file, validated_path)
    else
      {:error, _reason} ->
        # Return 404 for any auth/permission failure (don't distinguish "exists but denied" from "not found")
        send_resp(conn, :not_found, "")
    end
  end

  # Private

  defp authorize_request(conn, _opts) do
    # Requires authentication
    case conn.assigns[:current_scope] do
      nil ->
        conn
        |> put_flash(:error, "You must be logged in to access uploads")
        |> redirect(to: ~p"/users/log-in")
        |> halt()

      _scope ->
        conn
    end
  end

  defp fetch_file(file_id, context) do
    file =
      Repo.one(
        from file in UploadedFile,
          where: file.id == ^file_id and is_nil(file.deleted_at)
      )

    case file do
      %UploadedFile{context: ^context} = file ->
        {:ok, file}

      %UploadedFile{} ->
        # Wrong context for this file ID
        {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  defp check_tenant_isolation(conn, file) do
    case conn.assigns[:current_scope] do
      %{org: %{id: org_id}} when not is_nil(org_id) ->
        if to_string(org_id) == file.tenant_id do
          :ok
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp check_authorization(conn, file) do
    case file.context do
      :avatar ->
        # Avatar: any authenticated user in the tenant can access
        check_tenant_isolation(conn, file)

      :document ->
        # Document: owner only (or org members if org-owned)
        check_owner_authorization(conn, file)

      :post_media ->
        # Post media: owner or readers of the parent post
        check_post_media_authorization(conn, file)

      :mixed_attachment ->
        # Mixed attachment: owner or parent resource readers
        check_parent_authorization(conn, file)
    end
  end

  defp check_owner_authorization(conn, file) do
    case conn.assigns[:current_scope] do
      %{user: %{id: user_id}} when not is_nil(user_id) ->
        if to_string(user_id) == file.owner_id do
          :ok
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp check_post_media_authorization(conn, file) do
    # Simplified: check owner for now
    # In production, you'd load the post and check visibility
    check_owner_authorization(conn, file)
  end

  defp check_parent_authorization(conn, %{owner_type: "task"} = file) do
    with %{org: %{id: org_id}} <- conn.assigns[:current_scope],
         {task_id, ""} <- Integer.parse(file.owner_id),
         %Task{} <- Repo.get_by(Task, id: task_id, organization_id: org_id) do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp check_parent_authorization(conn, %{owner_type: "email"} = file) do
    with %{user: user, org: %{id: org_id} = org} <- conn.assigns[:current_scope],
         true <- Permissions.can?(user, org, :inbox, :read),
         {email_id, ""} <- Integer.parse(file.owner_id),
         %Email{} <- Repo.get_by(Email, id: email_id, organization_id: org_id) do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp check_parent_authorization(conn, file) do
    check_owner_authorization(conn, file)
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp serve_file(conn, file, validated_path) do
    case File.exists?(validated_path) do
      true ->
        conn
        |> put_resp_header("content-type", file.content_type)
        |> put_resp_header("x-content-type-options", "nosniff")
        |> allow_same_origin_pdf_preview(file.content_type, conn.params["preview"])
        |> put_resp_header(
          "content-disposition",
          "#{disposition_type(file.content_type, conn.params["preview"])}; filename=\"#{escape_filename(file.original_filename)}\""
        )
        |> send_file(200, validated_path)

      false ->
        # File missing on disk but record exists - log and return 404
        Logger.error(
          "[UploadController] File missing on disk: #{file.storage_path} (record ID: #{file.id})"
        )

        send_resp(conn, :not_found, "")
    end
  end

  defp disposition_type("application/pdf", "true"), do: "inline"
  defp disposition_type("image/" <> _subtype, "true"), do: "inline"
  defp disposition_type("video/" <> _subtype, "true"), do: "inline"
  defp disposition_type("audio/" <> _subtype, "true"), do: "inline"

  defp disposition_type(content_type, _preview) do
    # Return "inline" for images/video/audio that browsers can display
    # Return "attachment" for documents/spreadsheets to force download
    case content_type do
      "image/" <> _ -> "inline"
      "video/" <> _ -> "inline"
      "audio/" <> _ -> "inline"
      _ -> "attachment"
    end
  end

  defp allow_same_origin_pdf_preview(conn, "application/pdf", "true") do
    policy =
      conn
      |> get_resp_header("content-security-policy")
      |> List.first("frame-ancestors 'none'")
      |> String.replace("frame-ancestors 'none'", "frame-ancestors 'self'")

    put_resp_header(conn, "content-security-policy", policy)
  end

  defp allow_same_origin_pdf_preview(conn, _content_type, _preview), do: conn

  defp escape_filename(filename) do
    # Remove control characters and quotes from filename for header injection prevention
    filename
    |> String.replace(~r/[\x00-\x1f\x7f"\\]/, "")
    |> String.replace("\"", "")
  end
end
