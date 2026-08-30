defmodule Konevo.Contacts do
  @moduledoc """
  The Contacts context.
  """

  import Ecto.Query, warn: false
  alias Konevo.Contacts.{Activity, Contact, Dedupe, Note, Policy}
  alias Konevo.Repo
  alias Konevo.Slugs

  @per_page 25

  @doc """
  Returns paginated contacts for the given scope, with optional search, filter, sort.

  Options:
    - `:search` – string matched against first_name, last_name, email
    - `:statuses` – list of status atoms to filter by
    - `:sort_by` – `:name` | `:status` | `:inserted_at`
    - `:sort_dir` – `:asc` | `:desc`
    - `:page` – 1-based integer
    - `:per_page` – integer (defaults to #{@per_page})

  Returns `{contacts, total_count}`.
  """
  def list_contacts(scope, opts \\ []) do
    search = Keyword.get(opts, :search, "")
    statuses = Keyword.get(opts, :statuses, [])
    company_ids = Keyword.get(opts, :company_ids, [])
    archive_filter = Keyword.get(opts, :archive_filter, :active)
    created_from = Keyword.get(opts, :created_from, nil)
    created_to = Keyword.get(opts, :created_to, nil)
    sort_by = Keyword.get(opts, :sort_by, :name)
    sort_dir = Keyword.get(opts, :sort_dir, :asc)
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, @per_page)

    base = contact_base_query(scope)

    filtered =
      base
      |> filter_archive(archive_filter)
      |> filter_search(search)
      |> filter_statuses(statuses)
      |> filter_companies(company_ids)
      |> filter_created_from(created_from)
      |> filter_created_to(created_to)

    total = Repo.aggregate(filtered, :count, :id)

    contacts =
      filtered
      |> sort_contacts(sort_by, sort_dir)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload([:company])
      |> Repo.all()

    {contacts, total}
  end

  def count_contacts_by_status(scope) do
    scope
    |> contact_base_query()
    |> filter_archive(:active)
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns a short list of contacts matching a search string, for autocomplete.
  """
  def search_contacts(scope, search \\ "", limit \\ 15) do
    pattern = "%#{search}%"

    scope
    |> contact_base_query()
    |> filter_archive(:active)
    |> where(
      [c],
      ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern) or
        ilike(c.email, ^pattern)
    )
    |> order_by([c], asc: c.first_name, asc: c.last_name)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns contacts with email addresses matching recipient autocomplete text.
  """
  def search_email_recipients(scope, search, limit \\ 8) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      search = normalize_search(search)

      recipients =
        if search == "" do
          []
        else
          pattern = "%#{search}%"

          scope
          |> contact_base_query()
          |> filter_archive(:active)
          |> join(:left, [c], co in assoc(c, :company))
          |> where([c, co], not is_nil(c.email) and c.email != "")
          |> where(
            [c, co],
            ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern) or
              ilike(c.email, ^pattern) or ilike(co.name, ^pattern)
          )
          |> order_by([c], asc: c.first_name, asc: c.last_name, asc: c.email)
          |> preload([_c, co], company: co)
          |> limit(^limit)
          |> Repo.all()
        end

      {:ok, recipients}
    end
  end

  defp normalize_search(nil), do: ""
  defp normalize_search(search), do: search |> to_string() |> String.trim()

  defp filter_archive(query, :archived), do: from(c in query, where: not is_nil(c.archived_at))
  defp filter_archive(query, :all), do: query
  defp filter_archive(query, _filter), do: from(c in query, where: is_nil(c.archived_at))

  defp filter_search(query, ""), do: query
  defp filter_search(query, nil), do: query

  defp filter_search(query, term) do
    pattern = "%#{term}%"

    from c in query,
      where:
        ilike(c.first_name, ^pattern) or
          ilike(c.last_name, ^pattern) or
          ilike(c.email, ^pattern)
  end

  defp filter_statuses(query, []), do: query

  defp filter_statuses(query, statuses) do
    from c in query, where: c.status in ^statuses
  end

  defp filter_companies(query, []), do: query

  defp filter_companies(query, ids) do
    from c in query, where: c.company_id in ^ids
  end

  defp filter_created_from(query, nil), do: query
  defp filter_created_from(query, ""), do: query

  defp filter_created_from(query, date) do
    case Date.from_iso8601(date) do
      {:ok, d} ->
        dt = DateTime.new!(d, ~T[00:00:00], "Etc/UTC")
        from c in query, where: c.inserted_at >= ^dt

      _ ->
        query
    end
  end

  defp filter_created_to(query, nil), do: query
  defp filter_created_to(query, ""), do: query

  defp filter_created_to(query, date) do
    case Date.from_iso8601(date) do
      {:ok, d} ->
        dt = DateTime.new!(d, ~T[23:59:59], "Etc/UTC")
        from c in query, where: c.inserted_at <= ^dt

      _ ->
        query
    end
  end

  defp sort_contacts(query, :name, dir) do
    from c in query, order_by: [{^dir, c.first_name}, {^dir, c.last_name}]
  end

  defp sort_contacts(query, :email, dir) do
    from c in query, order_by: [{^dir, c.email}]
  end

  defp sort_contacts(query, :status, dir) do
    from c in query, order_by: [{^dir, c.status}]
  end

  defp sort_contacts(query, :inserted_at, dir) do
    from c in query, order_by: [{^dir, c.inserted_at}]
  end

  defp sort_contacts(query, _, _) do
    from c in query, order_by: [asc: c.first_name, asc: c.last_name]
  end

  @doc """
  Gets a single contact owned by the scope's user, preloading company.

  Raises `Ecto.NoResultsError` if not found or not owned by user.
  """
  def get_contact!(scope, id) do
    contact_base_query(scope)
    |> where(id: ^id)
    |> Repo.one!()
    |> Repo.preload(:company)
  end

  def get_contact_by_slug_or_id!(scope, slug_or_id) when is_binary(slug_or_id) do
    case get_contact_by_slug(scope, slug_or_id) do
      nil -> get_contact_by_id_param!(scope, slug_or_id)
      contact -> contact
    end
  end

  def get_contact_by_slug_or_id!(scope, id), do: get_contact!(scope, id)

  @doc """
  Creates a contact.
  """
  def create_contact(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %Contact{user_id: scope.user.id, organization_id: scope.org && scope.org.id}
      |> Contact.changeset(attrs)
      |> Slugs.maybe_put_slug(Contact, scope.org.id, [:first_name, :last_name])
      |> Repo.insert()
    end
  end

  @doc """
  Finds an existing contact by email or creates a lead contact from that email.
  """
  def find_or_create_by_email(scope, email) when is_binary(email) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}),
         {:ok, email} <- normalize_contact_email(email) do
      case contact_by_email(scope, email) do
        %Contact{} = contact ->
          {:ok, contact}

        nil ->
          create_contact(scope, %{
            email: email,
            first_name: first_name_from_email(email),
            status: :lead
          })
      end
    end
  end

  def find_or_create_by_email(_scope, _email), do: {:error, :invalid_email}

  @doc """
  Updates a contact.
  """
  def update_contact(scope, %Contact{} = contact, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, contact: contact}) do
      contact
      |> Contact.changeset(attrs)
      |> Slugs.maybe_put_slug(Contact, scope.org.id, [:first_name, :last_name],
        exclude_id: contact.id
      )
      |> Repo.update()
    end
  end

  @doc """
  Authorizes an action against a tenant-scoped contact.
  """
  def authorize_contact(scope, action, %Contact{} = contact)
      when action in [:read, :update, :delete] do
    Bodyguard.permit(Policy, action, scope.user, %{org: scope.org, contact: contact})
  end

  @doc """
  Deletes a contact.
  """
  def delete_contact(scope, %Contact{} = contact) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org, contact: contact}) do
      Repo.delete(contact)
    end
  end

  @doc """
  Archives a contact while preserving linked deals, tasks, and activity.
  """
  def archive_contact(scope, %Contact{} = contact, reason \\ nil) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, contact: contact}) do
      contact
      |> Ecto.Changeset.change(archive_attrs(scope, reason))
      |> Repo.update()
    end
  end

  @doc """
  Restores an archived contact.
  """
  def restore_contact(scope, %Contact{} = contact) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, contact: contact}) do
      contact
      |> Ecto.Changeset.change(%{archived_at: nil, archived_by_id: nil, archive_reason: nil})
      |> Repo.update()
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking contact changes.
  """
  def change_contact(%Contact{} = contact, attrs \\ %{}) do
    Contact.changeset(contact, attrs)
  end

  # Scope query to org when available, fall back to user_id for backwards compat.
  defp contact_base_query(%{org: %{id: org_id}}) do
    from c in Contact, where: c.organization_id == ^org_id
  end

  defp contact_base_query(%{user: %{id: user_id}}) do
    from c in Contact, where: c.user_id == ^user_id
  end

  defp contact_by_email(scope, email) do
    scope
    |> contact_base_query()
    |> where([contact], fragment("lower(?)", contact.email) == ^email)
    |> order_by([contact], asc: contact.id)
    |> limit(1)
    |> Repo.one()
  end

  defp normalize_contact_email(email) do
    email = email |> String.trim() |> String.downcase()

    if Regex.match?(~r/^[^@,;\s]+@[^@,;\s]+$/, email),
      do: {:ok, email},
      else: {:error, :invalid_email}
  end

  defp first_name_from_email(email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.split([".", "_", "-"], trim: true)
    |> List.first()
    |> Phoenix.Naming.humanize()
  end

  defp get_contact_by_slug(scope, slug) do
    scope
    |> contact_base_query()
    |> where([c], c.slug == ^slug)
    |> Repo.one()
    |> Repo.preload(:company)
  end

  defp get_contact_by_id_param!(scope, value) do
    case Integer.parse(value) do
      {id, ""} -> get_contact!(scope, id)
      _ -> raise Ecto.NoResultsError, queryable: Contact
    end
  end

  defp archive_attrs(scope, reason) do
    %{
      archived_at: DateTime.utc_now(:second),
      archived_by_id: scope.user.id,
      archive_reason: reason
    }
  end

  # ---------------------------------------------------------------------------
  # Notes
  # ---------------------------------------------------------------------------

  @doc """
  Returns all notes for a contact, ordered newest first.
  """
  def list_notes(scope, %Contact{} = contact) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      notes =
        from(n in Note,
          where: n.contact_id == ^contact.id and n.organization_id == ^scope.org.id,
          order_by: [desc: n.inserted_at],
          preload: [:created_by]
        )
        |> Repo.all()

      {:ok, notes}
    end
  end

  @doc """
  Adds a note to a contact.
  """
  def add_note(scope, %Contact{} = contact, attrs) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %Note{
        contact_id: contact.id,
        organization_id: scope.org.id,
        created_by_id: scope.user.id
      }
      |> Note.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a note. Only the creator can update it.
  """
  def update_note(scope, %Note{created_by_id: user_id} = note, attrs)
      when user_id == scope.user.id do
    note
    |> Note.changeset(attrs)
    |> Repo.update()
  end

  def update_note(_scope, %Note{}, _attrs), do: {:error, :unauthorized}

  @doc """
  Deletes a note.
  """
  def delete_note(scope, %Note{} = note) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org}) do
      Repo.delete(note)
    end
  end

  @doc """
  Returns a changeset for tracking note changes.
  """
  def change_note(%Note{} = note, attrs \\ %{}) do
    Note.changeset(note, attrs)
  end

  # ---------------------------------------------------------------------------
  # Activities
  # ---------------------------------------------------------------------------

  @doc """
  Returns all activities for a contact, ordered newest first.
  """
  def list_activities(scope, %Contact{} = contact) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      activities =
        from(a in Activity,
          where: a.contact_id == ^contact.id and a.organization_id == ^scope.org.id,
          order_by: [desc: a.activity_date]
        )
        |> Repo.all()

      {:ok, activities}
    end
  end

  @doc """
  Records an activity on a contact. Typically called internally by other contexts.
  """
  def record_activity(scope, %Contact{} = contact, attrs) do
    %Activity{
      contact_id: contact.id,
      organization_id: scope.org.id
    }
    |> Activity.changeset(attrs)
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Deduplication
  # ---------------------------------------------------------------------------

  @doc """
  Records a merge between two contacts (primary absorbs duplicate).
  Deletes the duplicate contact after recording the merge.
  """
  def merge_contacts(scope, %Contact{} = primary, %Contact{} = duplicate, opts \\ []) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org}) do
      Repo.transaction(fn ->
        {:ok, dedupe} =
          %Dedupe{
            organization_id: scope.org.id,
            primary_contact_id: primary.id,
            duplicate_contact_id: duplicate.id,
            merged_by_id: scope.user.id
          }
          |> Dedupe.changeset(%{
            merge_notes: Keyword.get(opts, :notes),
            merged_at: DateTime.utc_now(:second)
          })
          |> Repo.insert()

        Repo.delete!(duplicate)
        dedupe
      end)
    end
  end
end
