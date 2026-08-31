defmodule KonevoWeb.InboxLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Contacts
  alias Konevo.Inbox
  alias Konevo.Uploads
  alias Konevo.Uploads.UploadConfig
  alias Konevo.Uploads.UploadProcessor

  @per_page 25
  @scheduled_refresh_interval 30_000
  @categories [:lead, :customer, :support, :billing, :internal, :uncategorised]
  @views [:inbox, :favorites, :sent, :scheduled, :archived, :bin]
  @sortable ~w(last_inbound_at last_activity_at revenue_at_risk)
  @recipient_fields ~w(to cc bcc)
  @attachment_accept ~w(.pdf .doc .docx .xls .xlsx .csv .ppt .pptx .jpg .jpeg .png .gif .webp .mp4 .webm .mov .mp3 .wav .ogg)

  @impl true
  def mount(_params, _session, socket) do
    config = UploadConfig.get!(:mixed_attachment)

    {:ok,
     socket
     |> assign(:page_title, gettext("Inbox"))
     |> assign(:search, "")
     |> assign(:filter_category, nil)
     |> assign(:filter_unresolved, nil)
     |> assign(:sort_by, :last_activity_at)
     |> assign(:sort_dir, :desc)
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:stats, %{})
     |> assign(:view_counts, %{})
     |> assign(:revenue_at_risk, Decimal.new(0))
     |> assign(:unresolved_count, 0)
     |> assign(:inbox_view, :inbox)
     |> assign(:compose_open?, false)
     |> assign(:compose_minimized?, false)
     |> assign(:compose_form, compose_form())
     |> assign(:compose_recipient_field, nil)
     |> assign(:compose_recipient_suggestions, [])
     |> assign(:compose_attachment_owner_id, Ecto.UUID.generate())
     |> assign(:compose_attachments, [])
     |> assign(:compose_attachment_max_entries, config.max_entries)
     |> assign(:select_all?, false)
     |> assign(:selected_thread_ids, MapSet.new())
     |> assign(:current_thread_ids, [])
     |> assign(:current_thread_select_groups, empty_select_groups())
     |> assign(:inbox_request_ref, nil)
     |> assign(:scheduled_refresh_ref, nil)
     |> assign(:gmail_syncing?, false)
     |> assign(:mailbox_emails, [])
     |> allow_upload(:compose_attachment,
       accept: @attachment_accept,
       auto_upload: true,
       max_entries: config.max_entries,
       max_file_size: config.max_file_size,
       progress: &handle_compose_attachment_progress/3
     )
     |> maybe_subscribe_gmail_sync()
     |> stream(:threads, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, load_threads(socket, params)}
  end

  defp load_threads(socket, params) do
    %{
      search: search,
      filter_category: filter_category,
      filter_unresolved: filter_unresolved,
      sort_by: sort_by,
      sort_dir: sort_dir,
      inbox_view: inbox_view,
      page: page
    } = parse_params(params)

    scope = socket.assigns.current_scope
    live_view = self()
    request_ref = make_ref()

    opts = [
      view: inbox_view,
      category: filter_category,
      search: search,
      unresolved: filter_unresolved,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page,
      per_page: @per_page
    ]

    socket
    |> assign(:search, search)
    |> assign(:filter_category, filter_category)
    |> assign(:filter_unresolved, filter_unresolved)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_dir, sort_dir)
    |> assign(:inbox_view, inbox_view)
    |> assign(:page, page)
    |> assign(:selected_thread_ids, MapSet.new())
    |> assign(:current_thread_ids, [])
    |> assign(:current_thread_select_groups, empty_select_groups())
    |> assign(:select_all?, false)
    |> assign(:inbox_request_ref, request_ref)
    |> schedule_scheduled_refresh()
    |> cancel_async(:threads)
    |> stream_async(:threads, fn ->
      case load_thread_data(scope, opts) do
        {:ok, data} ->
          send(live_view, {:inbox_loaded, request_ref, Map.delete(data, :threads)})
          {:ok, data.threads, reset: true}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp load_thread_data(scope, opts) do
    case list_inbox_view(scope, opts) do
      {:error, reason} ->
        {:error, reason}

      {records, total} ->
        count_opts =
          opts
          |> Keyword.take([:view, :search, :unresolved])

        view_counts =
          scope
          |> Inbox.count_threads_by_view()
          |> Map.put(:scheduled, scheduled_count(scope))

        {:ok,
         %{
           threads: records,
           total: total,
           stats: Inbox.count_threads_by_category(scope, count_opts),
           view_counts: view_counts,
           revenue_at_risk: Inbox.total_revenue_at_risk(scope),
           unresolved_count: unresolved_count(records, opts),
           current_thread_ids: current_thread_ids(records, opts),
           current_thread_select_groups: current_thread_select_groups(records, opts),
           mailbox_emails: mailbox_emails(scope)
         }}
    end
  end

  defp list_inbox_view(scope, opts) do
    if Keyword.get(opts, :view) == :scheduled do
      Inbox.list_scheduled_emails(scope, Keyword.take(opts, [:page, :per_page, :search]))
    else
      Inbox.list_threads(scope, opts)
    end
  end

  defp scheduled_count(scope) do
    scope
    |> Inbox.count_scheduled_emails_by_status()
    |> Map.values()
    |> Enum.sum()
  end

  defp unresolved_count(records, opts) do
    if Keyword.get(opts, :view) == :scheduled,
      do: 0,
      else: Enum.count(records, & &1.is_unresolved)
  end

  defp current_thread_ids(records, opts) do
    if Keyword.get(opts, :view) == :scheduled, do: [], else: Enum.map(records, & &1.id)
  end

  defp current_thread_select_groups(records, opts) do
    if Keyword.get(opts, :view) == :scheduled,
      do: empty_select_groups(),
      else: current_thread_select_groups(records)
  end

  defp parse_params(params) do
    %{
      search: Map.get(params, "search", ""),
      filter_category: parse_category(Map.get(params, "category", "")),
      filter_unresolved: parse_unresolved(Map.get(params, "unresolved", "")),
      sort_by: parse_sort_by(Map.get(params, "sort_by", "")),
      sort_dir: parse_sort_dir(Map.get(params, "sort_dir", "")),
      inbox_view: parse_view(Map.get(params, "view", "")),
      page: parse_page(Map.get(params, "page", ""))
    }
  end

  defp parse_category(cat)
       when cat in ["lead", "customer", "support", "billing", "internal"],
       do: String.to_existing_atom(cat)

  defp parse_category("uncategorised"), do: :uncategorised
  defp parse_category(_), do: nil

  defp parse_view(view)
       when view in ["inbox", "favorites", "sent", "scheduled", "archived", "bin"],
       do: String.to_existing_atom(view)

  defp parse_view(_), do: :inbox

  defp parse_unresolved("true"), do: true
  defp parse_unresolved("false"), do: false
  defp parse_unresolved(_), do: nil

  defp parse_sort_by(col) when col in @sortable, do: String.to_existing_atom(col)
  defp parse_sort_by(_), do: :last_activity_at

  defp parse_sort_dir("asc"), do: :asc
  defp parse_sort_dir(_), do: :desc

  defp parse_page(str) when is_binary(str) and str != "" do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  @impl true
  def handle_info({:inbox_loaded, request_ref, data}, socket) do
    if request_ref == socket.assigns.inbox_request_ref do
      {:noreply,
       socket
       |> assign(:total, data.total)
       |> assign(:stats, data.stats)
       |> assign(:view_counts, data.view_counts)
       |> assign(:revenue_at_risk, data.revenue_at_risk)
       |> assign(:unresolved_count, data.unresolved_count)
       |> assign(:current_thread_ids, data.current_thread_ids)
       |> assign(:current_thread_select_groups, data.current_thread_select_groups)
       |> assign(:mailbox_emails, data.mailbox_emails)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:scheduled_refresh, ref}, socket) do
    if ref == socket.assigns.scheduled_refresh_ref and socket.assigns.inbox_view == :scheduled do
      {:noreply, reload_threads(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:gmail_sync_finished, %{result: result}}, socket) do
    {:noreply, handle_gmail_sync_finished(socket, result)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: q, page: 1}), replace: true)}
  end

  def handle_event("open_compose", _, socket) do
    {:noreply, assign(socket, compose_open?: true, compose_minimized?: false)}
  end

  def handle_event("close_compose", _, socket) do
    {:noreply, socket |> discard_compose_attachments() |> reset_compose()}
  end

  def handle_event("toggle_minimize_compose", _, socket) do
    {:noreply, assign(socket, :compose_minimized?, !socket.assigns.compose_minimized?)}
  end

  def handle_event(
        "validate_compose",
        %{"_target" => ["compose", field], "compose" => params},
        socket
      )
      when field in @recipient_fields do
    {:noreply,
     socket
     |> assign(:compose_form, compose_form(socket, params))
     |> assign_recipient_suggestions(field, Map.get(params, field))}
  end

  def handle_event("validate_compose", %{"compose" => params}, socket) do
    {:noreply,
     socket
     |> assign(:compose_form, compose_form(socket, params))
     |> clear_recipient_suggestions()}
  end

  def handle_event("validate_compose", params, socket) do
    {:noreply,
     socket
     |> assign(:compose_form, compose_form(socket, params))
     |> clear_recipient_suggestions()}
  end

  def handle_event("select_compose_recipient", %{"field" => field, "email" => email}, socket)
      when field in @recipient_fields do
    params = compose_form_attrs(socket.assigns.compose_form)
    value = params |> Map.get(field, "") |> insert_recipient_email(email)

    {:noreply,
     socket
     |> assign(:compose_form, params |> Map.put(field, value) |> compose_form())
     |> clear_recipient_suggestions()}
  end

  def handle_event("cancel_compose_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :compose_attachment, ref)}
  end

  def handle_event("delete_compose_attachment", %{"id" => id}, socket) do
    case Uploads.delete_email_draft_attachment(
           socket.assigns.current_scope,
           id,
           socket.assigns.compose_attachment_owner_id
         ) do
      {:ok, _file} ->
        {:noreply, assign(socket, :compose_attachments, reject_attachment(socket, id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove attachment"))}
    end
  end

  def handle_event("toggle_select_all", _, socket) do
    if socket.assigns.select_all? do
      {:noreply, clear_selected_threads(socket)}
    else
      {:noreply, select_thread_group(socket, :all)}
    end
  end

  def handle_event("clear_selected", _, socket) do
    {:noreply, clear_selected_threads(socket)}
  end

  def handle_event("select_all", _, socket) do
    {:noreply, select_thread_group(socket, :all)}
  end

  def handle_event("select_none", _, socket) do
    {:noreply, clear_selected_threads(socket)}
  end

  def handle_event("select_thread_group", %{"group" => group}, socket) do
    {:noreply, select_thread_group(socket, parse_select_group(group))}
  end

  def handle_event("toggle_select_thread", %{"id" => id}, socket) do
    selected_thread_ids =
      socket.assigns.selected_thread_ids
      |> toggle_selected_id(parse_id(id))

    {:noreply,
     socket
     |> assign(:selected_thread_ids, selected_thread_ids)
     |> assign(:select_all?, all_current_threads_selected?(socket, selected_thread_ids))
     |> push_thread_selection(selected_thread_ids)}
  end

  def handle_event("refresh", _, socket) do
    {:noreply, socket |> enqueue_gmail_sync() |> reload_threads()}
  end

  def handle_event("switch_view", %{"view" => view}, socket) do
    {:noreply,
     push_patch(socket, to: build_url(socket, %{inbox_view: parse_view(view), page: 1}))}
  end

  def handle_event("send_message", %{"compose" => params}, socket) do
    cond do
      compose_uploading?(socket) ->
        {:noreply, put_flash(socket, :error, gettext("Wait for attachments to finish uploading"))}

      Map.get(params, "schedule_preset") ->
        schedule_message(socket, params)

      true ->
        send_message_now(socket, params)
    end
  end

  def handle_event("cancel_scheduled_email", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with {scheduled_id, ""} <- Integer.parse(to_string(id)),
         scheduled_email <- Inbox.get_scheduled_email!(scope, scheduled_id),
         {:ok, _cancelled} <- Inbox.cancel_scheduled_email(scope, scheduled_email) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Scheduled email cancelled"))
       |> reload_threads()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not cancel scheduled email"))}
    end
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: "", page: 1}), replace: true)}
  end

  def handle_event("filter_category", %{"category" => cat} = params, socket) do
    category = parse_category(cat)

    new_cat =
      if params["select"] == "true" do
        category
      else
        if socket.assigns.filter_category == category, do: nil, else: category
      end

    {:noreply, push_patch(socket, to: build_url(socket, %{filter_category: new_cat, page: 1}))}
  end

  def handle_event("filter_unresolved", %{"value" => val}, socket) do
    new_val = parse_unresolved(val)

    new_val =
      if socket.assigns.filter_unresolved == new_val, do: nil, else: new_val

    {:noreply, push_patch(socket, to: build_url(socket, %{filter_unresolved: new_val, page: 1}))}
  end

  def handle_event("clear_filters", _, socket) do
    {:noreply,
     push_patch(socket,
       to: build_url(socket, %{filter_category: nil, filter_unresolved: nil, page: 1})
     )}
  end

  def handle_event("sort", %{"by" => by}, socket) do
    sort_by = parse_sort_by(by)

    sort_dir =
      if socket.assigns.sort_by == sort_by,
        do: if(socket.assigns.sort_dir == :asc, do: :desc, else: :asc),
        else: :desc

    {:noreply,
     push_patch(socket, to: build_url(socket, %{sort_by: sort_by, sort_dir: sort_dir, page: 1}))}
  end

  def handle_event("page", %{"n" => n_str}, socket) do
    case Integer.parse(n_str) do
      {n, ""} when n > 0 ->
        {:noreply, push_patch(socket, to: build_url(socket, %{page: n}))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("resolve", %{"id" => id}, socket) do
    {:noreply, apply_thread_action(socket, id, &Inbox.resolve_thread/2)}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    {:noreply, apply_thread_action(socket, id, &Inbox.archive_thread/2)}
  end

  def handle_event("unarchive", %{"id" => id}, socket) do
    {:noreply, apply_thread_action(socket, id, &Inbox.unarchive_thread/2)}
  end

  def handle_event("toggle_favorite", %{"id" => id}, socket) do
    {:noreply, toggle_favorite_thread(socket, id)}
  end

  def handle_event("categorize", %{"id" => id, "category" => category}, socket) do
    {:noreply, categorize_thread(socket, id, category)}
  end

  def handle_event("mark_read", %{"id" => id}, socket) do
    {:noreply, apply_thread_action(socket, id, &Inbox.mark_read/2)}
  end

  def handle_event("mark_unread", %{"id" => id}, socket) do
    {:noreply, apply_thread_action(socket, id, &Inbox.mark_unread/2)}
  end

  def handle_event("move_to_bin", %{"id" => id}, socket) do
    {:noreply, apply_thread_action(socket, id, &Inbox.move_to_bin/2)}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    {:noreply, apply_thread_action(socket, id, &Inbox.restore_thread/2)}
  end

  def handle_event("bulk_action", %{"action" => action}, socket) do
    {:noreply, apply_bulk_action(socket, action)}
  end

  defp schedule_message(socket, params) do
    do_schedule_message(socket, put_compose_attachment_params(socket, params))
  end

  defp do_schedule_message(socket, params) do
    params = Map.put(params, "scheduled_at", scheduled_at_from_params(params))

    case Inbox.schedule_message(socket.assigns.current_scope, params) do
      {:ok, _scheduled_email} ->
        {:noreply,
         socket
         |> reset_compose()
         |> reload_threads()
         |> put_flash(:success, gettext("Email scheduled"))}

      {:error, {:invalid_recipients, errors}} ->
        {:noreply,
         socket
         |> assign(:compose_form, compose_form_with_recipient_errors(params, errors))
         |> put_flash(:error, gettext("Correct the highlighted email addresses"))}

      {:error, :missing_body} ->
        {:noreply,
         assign(
           socket,
           :compose_form,
           compose_form_with_body_error(params, gettext("Write a message before scheduling"))
         )}

      {:error, :missing_recipient} ->
        {:noreply,
         assign(
           socket,
           :compose_form,
           compose_form_with_to_error(params, gettext("Add at least one recipient"))
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:compose_form, compose_form(params))
         |> put_flash(:error, schedule_error(reason))}
    end
  end

  defp send_message_now(socket, params) do
    params = put_compose_attachment_params(socket, params)

    case Inbox.send_message(socket.assigns.current_scope, params) do
      {:ok, _email} ->
        {:noreply,
         socket
         |> reset_compose()
         |> reload_threads()
         |> put_flash(:success, gettext("Message sent"))}

      {:error, :no_integration} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("No Gmail account connected. Please connect Gmail in Settings")
         )}

      {:error, :missing_recipient} ->
        {:noreply,
         socket
         |> assign(
           :compose_form,
           compose_form_with_to_error(params, gettext("Add at least one recipient"))
         )}

      {:error, :missing_body} ->
        {:noreply,
         socket
         |> assign(
           :compose_form,
           compose_form_with_body_error(params, gettext("Write a message before sending"))
         )}

      {:error, {:invalid_recipients, errors}} ->
        {:noreply,
         socket
         |> assign(:compose_form, compose_form_with_recipient_errors(params, errors))
         |> put_flash(:error, gettext("Correct the highlighted email addresses"))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:compose_form, compose_form(params))
         |> put_flash(:error, gettext("Failed to send message"))}
    end
  end

  defp apply_thread_action(socket, id, action_fun) do
    scope = socket.assigns.current_scope

    with {thread_id, ""} <- Integer.parse(to_string(id)),
         thread <- Inbox.get_thread!(scope, thread_id),
         {:ok, _updated} <- action_fun.(scope, thread) do
      socket
      |> reload_threads()
      |> put_flash(:info, gettext("Thread updated"))
    else
      _ ->
        put_flash(socket, :error, gettext("Could not update thread"))
    end
  end

  defp apply_bulk_action(socket, action) do
    scope = socket.assigns.current_scope
    selected_thread_ids = socket.assigns.selected_thread_ids

    if MapSet.size(selected_thread_ids) == 0 do
      put_flash(socket, :error, gettext("Select threads first"))
    else
      run_bulk_thread_action(selected_thread_ids, action, scope)

      socket
      |> reload_threads()
      |> put_flash(:info, bulk_action_flash(action))
    end
  end

  defp run_bulk_thread_action(thread_ids, action, scope) do
    Enum.each(thread_ids, fn id ->
      thread = Inbox.get_thread!(scope, id)
      ignore_bulk_result(bulk_thread_action(action, scope, thread))
    end)
  end

  defp ignore_bulk_result({:ok, _}), do: :ok
  defp ignore_bulk_result(_), do: :error

  defp bulk_thread_action("archive", scope, thread), do: Inbox.archive_thread(scope, thread)
  defp bulk_thread_action("move_to_bin", scope, thread), do: Inbox.move_to_bin(scope, thread)
  defp bulk_thread_action("mark_read", scope, thread), do: Inbox.mark_read(scope, thread)
  defp bulk_thread_action("mark_unread", scope, thread), do: Inbox.mark_unread(scope, thread)
  defp bulk_thread_action("favorite", scope, thread), do: Inbox.toggle_favorite(scope, thread)
  defp bulk_thread_action("restore", scope, thread), do: Inbox.restore_thread(scope, thread)
  defp bulk_thread_action(_action, _scope, _thread), do: {:error, :unknown_action}

  defp toggle_favorite_thread(socket, id) do
    scope = socket.assigns.current_scope

    with {thread_id, ""} <- Integer.parse(to_string(id)),
         thread <- Inbox.get_thread_for_list!(scope, thread_id),
         {:ok, updated} <- Inbox.toggle_favorite(scope, thread) do
      socket
      |> update_favorite_count(thread, updated)
      |> apply_visible_thread_update(thread, updated)
      |> put_flash(:info, favorite_flash(updated))
    else
      _ ->
        put_flash(socket, :error, gettext("Could not update thread"))
    end
  end

  defp categorize_thread(socket, id, category) do
    scope = socket.assigns.current_scope

    with {thread_id, ""} <- Integer.parse(to_string(id)),
         category when category != :invalid <- parse_category_update(category),
         thread <- Inbox.get_thread_for_list!(scope, thread_id),
         {:ok, updated} <- Inbox.categorize_thread(scope, thread, category) do
      socket
      |> update_category_counts(thread, updated)
      |> apply_visible_thread_update(thread, updated)
      |> put_flash(:info, gettext("Category updated"))
    else
      _ ->
        put_flash(socket, :error, gettext("Could not update category"))
    end
  end

  defp favorite_flash(%{is_favorite: true}), do: gettext("Added to favorites")
  defp favorite_flash(_thread), do: gettext("Removed from favorites")

  defp bulk_action_flash("archive"), do: gettext("Threads archived")
  defp bulk_action_flash("move_to_bin"), do: gettext("Threads moved to bin")
  defp bulk_action_flash("mark_read"), do: gettext("Threads marked as read")
  defp bulk_action_flash("mark_unread"), do: gettext("Threads marked as unread")
  defp bulk_action_flash("favorite"), do: gettext("Favorites updated")
  defp bulk_action_flash("restore"), do: gettext("Threads restored")
  defp bulk_action_flash(_action), do: gettext("Threads updated")

  defp update_favorite_count(socket, thread, updated) do
    if is_nil(thread.trashed_at) and thread.is_favorite != updated.is_favorite do
      delta = if updated.is_favorite, do: 1, else: -1
      assign(socket, :view_counts, bump_count(socket.assigns.view_counts, :favorites, delta))
    else
      socket
    end
  end

  defp update_category_counts(socket, thread, updated) do
    if thread.category != updated.category do
      stats =
        Inbox.count_threads_by_category(
          socket.assigns.current_scope,
          category_count_opts_from_assigns(socket)
        )

      assign(socket, :stats, stats)
    else
      socket
    end
  end

  defp category_count_opts_from_assigns(socket) do
    [
      view: socket.assigns.inbox_view,
      search: socket.assigns.search,
      unresolved: socket.assigns.filter_unresolved
    ]
  end

  defp bump_count(counts, key, delta) do
    Map.update(counts, key, max(delta, 0), fn count -> max(count + delta, 0) end)
  end

  defp apply_visible_thread_update(socket, thread, updated) do
    was_visible? = thread_visible?(thread, socket)
    visible? = thread_visible?(updated, socket)

    socket
    |> update_visible_total(was_visible?, visible?)
    |> update_current_thread_tracking(thread, was_visible?, visible?)
    |> patch_thread_stream(updated, was_visible?, visible?)
  end

  defp update_visible_total(socket, true, false),
    do: assign(socket, :total, max(socket.assigns.total - 1, 0))

  defp update_visible_total(socket, false, true),
    do: assign(socket, :total, socket.assigns.total + 1)

  defp update_visible_total(socket, _was_visible?, _visible?), do: socket

  defp update_current_thread_tracking(socket, thread, true, false) do
    selected_thread_ids = MapSet.delete(socket.assigns.selected_thread_ids, thread.id)
    current_thread_ids = List.delete(socket.assigns.current_thread_ids, thread.id)

    current_thread_select_groups =
      Map.new(socket.assigns.current_thread_select_groups, fn {group, ids} ->
        {group, List.delete(ids, thread.id)}
      end)

    socket
    |> assign(:selected_thread_ids, selected_thread_ids)
    |> assign(:current_thread_ids, current_thread_ids)
    |> assign(:current_thread_select_groups, current_thread_select_groups)
    |> assign(:select_all?, all_thread_ids_selected?(current_thread_ids, selected_thread_ids))
  end

  defp update_current_thread_tracking(socket, _thread, _was_visible?, _visible?), do: socket

  defp patch_thread_stream(socket, updated, true, false),
    do: stream_delete(socket, :threads, updated)

  defp patch_thread_stream(socket, updated, _was_visible?, true),
    do: stream_insert(socket, :threads, updated)

  defp patch_thread_stream(socket, _updated, _was_visible?, _visible?), do: socket

  defp thread_visible?(thread, socket) do
    thread_matches_view?(thread, socket.assigns.inbox_view) and
      thread_matches_category?(thread, socket.assigns.filter_category) and
      thread_matches_unresolved?(thread, socket.assigns.filter_unresolved) and
      thread_matches_search?(thread, socket.assigns.search)
  end

  defp thread_matches_view?(thread, :favorites),
    do: is_nil(thread.trashed_at) and thread.is_favorite == true

  defp thread_matches_view?(thread, :sent),
    do: is_nil(thread.trashed_at) and not is_nil(thread.last_outbound_at)

  defp thread_matches_view?(thread, :archived),
    do: is_nil(thread.trashed_at) and thread.is_archived == true

  defp thread_matches_view?(thread, :bin), do: not is_nil(thread.trashed_at)

  defp thread_matches_view?(thread, _view),
    do: is_nil(thread.trashed_at) and thread.is_archived == false

  defp thread_matches_category?(_thread, nil), do: true
  defp thread_matches_category?(thread, :uncategorised), do: is_nil(thread.category)
  defp thread_matches_category?(thread, category), do: thread.category == category

  defp thread_matches_unresolved?(_thread, nil), do: true
  defp thread_matches_unresolved?(thread, unresolved?), do: thread.is_unresolved == unresolved?

  defp thread_matches_search?(_thread, search) when search in [nil, ""], do: true

  defp thread_matches_search?(thread, search) do
    needle = search |> String.trim() |> String.downcase()
    values = [thread.subject, thread.snippet] ++ (thread.participants || [])

    needle == "" or
      Enum.any?(values, fn
        value when is_binary(value) -> String.contains?(String.downcase(value), needle)
        _ -> false
      end)
  end

  defp parse_category_update("uncategorised"), do: nil

  defp parse_category_update(category)
       when category in ["lead", "customer", "support", "billing", "internal"],
       do: String.to_existing_atom(category)

  defp parse_category_update(_), do: :invalid

  defp maybe_subscribe_gmail_sync(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Konevo.PubSub, gmail_sync_topic(socket.assigns.current_scope))
    end

    socket
  end

  defp enqueue_gmail_sync(socket) do
    case Inbox.enqueue_gmail_sync(socket.assigns.current_scope) do
      {:ok, _job} ->
        socket
        |> assign(:gmail_syncing?, true)
        |> put_flash(:info, gettext("Checking Gmail for new mail"))

      {:error, :no_integration} ->
        put_flash(socket, :error, gettext("Connect Gmail in Settings to check for new mail"))

      {:error, :unauthorized} ->
        put_flash(socket, :error, gettext("You are not allowed to check Gmail"))

      {:error, _reason} ->
        put_flash(socket, :error, gettext("Could not check Gmail right now"))
    end
  end

  defp handle_gmail_sync_finished(socket, {:ok, _count}) do
    socket
    |> maybe_put_gmail_checked_flash()
    |> assign(:gmail_syncing?, false)
    |> reload_threads()
  end

  defp handle_gmail_sync_finished(socket, {:error, _reason}) do
    socket =
      if socket.assigns.gmail_syncing? do
        put_flash(socket, :error, gettext("Gmail check failed"))
      else
        socket
      end

    socket
    |> assign(:gmail_syncing?, false)
    |> reload_threads()
  end

  defp maybe_put_gmail_checked_flash(socket) do
    if socket.assigns.gmail_syncing? do
      put_flash(socket, :info, gettext("Gmail checked"))
    else
      socket
    end
  end

  defp gmail_sync_topic(%{org: %{id: org_id}}), do: "inbox:gmail_sync:#{org_id}"

  defp reload_threads(socket), do: load_threads(socket, params_from_assigns(socket))

  defp schedule_scheduled_refresh(socket) do
    if connected?(socket) and socket.assigns.inbox_view == :scheduled do
      ref = make_ref()
      Process.send_after(self(), {:scheduled_refresh, ref}, @scheduled_refresh_interval)
      assign(socket, :scheduled_refresh_ref, ref)
    else
      assign(socket, :scheduled_refresh_ref, nil)
    end
  end

  defp params_from_assigns(socket) do
    %{
      "view" => to_string(socket.assigns.inbox_view),
      "search" => socket.assigns.search,
      "category" => category_param(socket.assigns.filter_category),
      "unresolved" => unresolved_param(socket.assigns.filter_unresolved),
      "sort_by" => to_string(socket.assigns.sort_by),
      "sort_dir" => to_string(socket.assigns.sort_dir),
      "page" => to_string(socket.assigns.page)
    }
  end

  defp category_param(nil), do: ""
  defp category_param(category), do: to_string(category)

  defp unresolved_param(nil), do: ""
  defp unresolved_param(value), do: to_string(value)

  defp toggle_selected_id(selected_thread_ids, :error), do: selected_thread_ids

  defp toggle_selected_id(selected_thread_ids, id) do
    if MapSet.member?(selected_thread_ids, id) do
      MapSet.delete(selected_thread_ids, id)
    else
      MapSet.put(selected_thread_ids, id)
    end
  end

  defp empty_select_groups, do: %{all: [], unresolved: [], resolved: []}

  defp current_thread_select_groups(threads) do
    %{
      all: Enum.map(threads, & &1.id),
      unresolved: threads |> Enum.filter(& &1.is_unresolved) |> Enum.map(& &1.id),
      resolved: threads |> Enum.reject(& &1.is_unresolved) |> Enum.map(& &1.id)
    }
  end

  defp select_thread_group(socket, :unknown), do: socket

  defp select_thread_group(socket, group) do
    selected_thread_ids =
      socket.assigns.current_thread_select_groups
      |> Map.get(group, [])
      |> MapSet.new()

    socket
    |> assign(:selected_thread_ids, selected_thread_ids)
    |> assign(:select_all?, all_current_threads_selected?(socket, selected_thread_ids))
    |> push_thread_selection(selected_thread_ids)
  end

  defp clear_selected_threads(socket) do
    selected_thread_ids = MapSet.new()

    socket
    |> assign(:select_all?, false)
    |> assign(:selected_thread_ids, selected_thread_ids)
    |> push_thread_selection(selected_thread_ids)
  end

  defp push_thread_selection(socket, selected_thread_ids) do
    push_event(socket, "inbox-thread-selection", %{
      ids: Enum.map(selected_thread_ids, &to_string/1)
    })
  end

  defp parse_select_group("all"), do: :all
  defp parse_select_group("unresolved"), do: :unresolved
  defp parse_select_group("resolved"), do: :resolved
  defp parse_select_group(_), do: :unknown

  defp all_current_threads_selected?(socket, selected_thread_ids) do
    all_thread_ids_selected?(socket.assigns.current_thread_ids, selected_thread_ids)
  end

  defp all_thread_ids_selected?([], _selected_thread_ids), do: false

  defp all_thread_ids_selected?(thread_ids, selected_thread_ids) do
    MapSet.size(selected_thread_ids) == length(thread_ids) and
      Enum.all?(thread_ids, &MapSet.member?(selected_thread_ids, &1))
  end

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {thread_id, ""} -> thread_id
      _ -> :error
    end
  end

  defp build_url(socket, overrides) do
    search = Map.get(overrides, :search, socket.assigns.search)
    cat = Map.get(overrides, :filter_category, socket.assigns.filter_category)
    unresolved = Map.get(overrides, :filter_unresolved, socket.assigns.filter_unresolved)
    sort_by = Map.get(overrides, :sort_by, socket.assigns.sort_by)
    sort_dir = Map.get(overrides, :sort_dir, socket.assigns.sort_dir)
    inbox_view = Map.get(overrides, :inbox_view, socket.assigns.inbox_view)
    page = Map.get(overrides, :page, socket.assigns.page)

    params =
      []
      |> push_param("view", to_string(inbox_view), "inbox")
      |> push_param("search", search, "")
      |> push_param("category", if(cat, do: to_string(cat), else: ""), "")
      |> push_param("unresolved", if(is_nil(unresolved), do: "", else: to_string(unresolved)), "")
      |> push_param("sort_by", to_string(sort_by), "last_activity_at")
      |> push_param("sort_dir", to_string(sort_dir), "desc")
      |> push_param("page", to_string(page), "1")
      |> Map.new()

    if map_size(params) == 0, do: ~p"/inbox", else: ~p"/inbox?#{params}"
  end

  defp push_param(list, _key, default, default), do: list
  defp push_param(list, key, value, _default), do: [{key, value} | list]

  defp total_pages(total), do: max(1, ceil(total / @per_page))

  defp page_display(_current, total_pages) when total_pages <= 7,
    do: Enum.to_list(1..total_pages)

  defp page_display(current, total_pages) do
    pages =
      [1, total_pages, max(2, current - 1), current, min(total_pages - 1, current + 1)]
      |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
      |> Enum.sort()
      |> Enum.uniq()

    Enum.reduce(tl(pages), [hd(pages)], fn n, acc ->
      if n - List.last(acc) > 1, do: acc ++ [:gap, n], else: acc ++ [n]
    end)
  end

  defp category_count(stats, nil, _total), do: stats |> Map.values() |> Enum.sum()
  defp category_count(stats, :uncategorised, _total), do: Map.get(stats, nil, 0)
  defp category_count(stats, category, _total), do: Map.get(stats, category, 0)

  defp category_filter_options do
    [
      {gettext("All"), nil, "all", "icon-[tabler--inbox]"},
      {gettext("Leads"), :lead, "lead", "icon-[tabler--user-dollar]"},
      {gettext("Customers"), :customer, "customer", "icon-[tabler--users]"},
      {gettext("Support"), :support, "support", "icon-[tabler--headset]"},
      {gettext("Billing"), :billing, "billing", "icon-[tabler--receipt]"},
      {gettext("Internal"), :internal, "internal", "icon-[tabler--building]"},
      {gettext("Uncategorised"), :uncategorised, "uncategorised", "icon-[tabler--tag-off]"}
    ]
  end

  defp category_filter_option(category) do
    Enum.find(category_filter_options(), fn {_label, option_category, _id, _icon} ->
      option_category == category
    end) || List.first(category_filter_options())
  end

  attr(:tip, :string, required: true)
  slot(:inner_block, required: true)

  defp action_popover(assigns) do
    ~H"""
    <span class="group relative inline-flex shrink-0">
      {render_slot(@inner_block)}
      <span class="pointer-events-none absolute bottom-full left-1/2 z-[80] mb-2 hidden -translate-x-1/2 whitespace-nowrap rounded-md border border-base-content/10 bg-base-100 px-2.5 py-1.5 text-xs font-medium text-base-content shadow-xl shadow-base-content/10 group-hover:block">
        {@tip}
      </span>
    </span>
    """
  end

  defp mailbox_emails(scope) do
    emails =
      scope
      |> Inbox.list_integrations()
      |> Enum.filter(&(&1.provider == :gmail and &1.sync_enabled))
      |> Enum.map(&normalize_email(&1.email_address))

    if emails == [], do: [scope |> scope_email() |> normalize_email()], else: emails
  end

  defp thread_sender(thread, mailbox_emails)

  defp thread_sender(%{participants: participants}, mailbox_emails) when is_list(participants) do
    case participants do
      [first, second | _] ->
        if own_participant?(first, mailbox_emails) do
          gettext("me, %{sender}", sender: participant_display_name(second))
        else
          participant_display_name(first)
        end

      [first] ->
        if own_participant?(first, mailbox_emails),
          do: gettext("me"),
          else: participant_display_name(first)

      [] ->
        gettext("Unknown")
    end
  end

  defp thread_sender(%{contact: %{first_name: first, last_name: last}} = _thread, _scope)
       when not is_nil(first) or not is_nil(last) do
    [first, last] |> Enum.filter(& &1) |> Enum.join(" ")
  end

  defp thread_sender(_thread, _scope), do: gettext("Unknown")

  defp sender_initials(thread, mailbox_emails) do
    thread
    |> thread_sender(mailbox_emails)
    |> String.replace_prefix("me, ", "")
    |> String.split(" ")
    |> Enum.map(&String.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(2)
    |> Enum.join()
  end

  defp sender_details(thread, mailbox_emails)

  defp sender_details(%{participants: participants}, mailbox_emails) when is_list(participants) do
    participants
    |> Enum.map(&extract_participant_email/1)
    |> Enum.reject(&(&1 == "" or &1 in mailbox_emails))
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp sender_details(_thread, _scope), do: ""

  defp sender_info?(thread, mailbox_emails), do: sender_details(thread, mailbox_emails) != ""

  defp participant_display_name(participant) do
    participant = to_string(participant)
    name = participant_name(participant)
    email = extract_participant_email(participant)

    cond do
      name != "" and normalize_email(name) != email -> name
      email != "" -> email |> String.split("@") |> hd() |> humanize_email_local()
      true -> String.trim(participant)
    end
  end

  defp participant_name(participant) do
    participant
    |> String.split("<", parts: 2)
    |> List.first()
    |> String.replace("\"", "")
    |> String.trim()
  end

  defp extract_participant_email(participant) do
    case Regex.run(~r/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, participant) do
      [email] -> normalize_email(email)
      _ -> ""
    end
  end

  defp own_participant?(_participant, []), do: false

  defp own_participant?(participant, mailbox_emails) do
    participant |> extract_participant_email() |> Kernel.in(mailbox_emails)
  end

  defp scope_email(%{user: %{email: email}}), do: email
  defp scope_email(_scope), do: ""

  defp normalize_email(email), do: email |> to_string() |> String.downcase() |> String.trim()

  defp humanize_email_local(local) do
    local
    |> String.replace(~r/[._-]+/, " ")
    |> String.trim()
    |> Phoenix.Naming.humanize()
  end

  attr(:thread, :map, required: true)
  attr(:compact, :boolean, default: false)

  defp category_picker(assigns) do
    category = category_for_ui(assigns.thread.category)
    {icon, label} = category_meta(category)

    assigns =
      assign(assigns,
        category: category,
        icon: icon,
        label: label,
        options: category_options()
      )

    ~H"""
    <div
      id={"thread-category-#{@thread.id}#{if(@compact, do: "-mobile", else: "")}"}
      phx-hook="RowMenu"
      class="relative"
    >
      <button
        type="button"
        data-toggle
        aria-label={gettext("Change category")}
        class={[
          "inline-flex cursor-pointer items-center gap-1 border border-base-content/15 bg-base-100 font-medium text-base-content/65 transition-colors hover:border-primary/30 hover:bg-base-200 hover:text-base-content",
          if(@compact,
            do: "max-w-full rounded-full px-2 py-0.5 text-[11px]",
            else: "rounded-md px-2.5 py-1 text-xs"
          )
        ]}
      >
        <.icon name={@icon} class="size-3.5 shrink-0 text-base-content/50" />
        <span class="truncate">{@label}</span>
        <.icon name="icon-[tabler--chevron-down]" class="size-3 shrink-0 opacity-60" />
      </button>
      <ul
        data-panel
        class="row-menu-closed z-50 w-44 space-y-0.5 overflow-hidden rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
        role="menu"
      >
        <li :for={{value, icon, label} <- @options}>
          <button
            type="button"
            phx-click="categorize"
            phx-value-id={@thread.id}
            phx-value-category={value}
            class={[
              "inline-flex w-full cursor-pointer items-center gap-1.5 rounded-md px-2.5 py-2 text-xs font-medium transition-colors",
              if(@category == value,
                do: "bg-primary/10 text-primary",
                else: "text-base-content/70 hover:bg-base-200 hover:text-base-content"
              )
            ]}
            role="menuitem"
          >
            <.icon name={icon} class="size-3.5 shrink-0 text-base-content/50" />
            <span>{label}</span>
            <.icon
              :if={@category == value}
              name="icon-[tabler--check]"
              class="ml-auto size-3 shrink-0"
            />
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp category_for_ui(category) when category in [nil, :uncategorised, :noise],
    do: :uncategorised

  defp category_for_ui(category), do: category

  defp category_options do
    [
      {:lead, "icon-[tabler--user-dollar]", gettext("Lead")},
      {:customer, "icon-[tabler--users]", gettext("Customer")},
      {:support, "icon-[tabler--headset]", gettext("Support")},
      {:billing, "icon-[tabler--receipt]", gettext("Billing")},
      {:internal, "icon-[tabler--building]", gettext("Internal")},
      {:uncategorised, "icon-[tabler--tag-off]", gettext("Uncategorised")}
    ]
  end

  defp category_meta(category) do
    case Enum.find(category_options(), fn {value, _, _} ->
           value == category_for_ui(category)
         end) do
      {_, icon, label} -> {icon, label}
      nil -> {"icon-[tabler--tag-off]", gettext("Uncategorised")}
    end
  end

  defp unread?(thread), do: is_nil(thread.read_at)

  defp new_unread?(%{last_inbound_at: %DateTime{} = last_inbound_at} = thread) do
    age = DateTime.diff(DateTime.utc_now(:second), last_inbound_at, :second)

    unread?(thread) and age >= 0 and age <= 300
  end

  defp new_unread?(_thread), do: false

  defp email_count(%{email_count: count}) when is_integer(count), do: count
  defp email_count(_thread), do: 0

  defp thread_selected?(selected_thread_ids, id), do: MapSet.member?(selected_thread_ids, id)

  defp display_activity_at(%{last_activity_at: %DateTime{} = dt}), do: dt
  defp display_activity_at(%{last_inbound_at: %DateTime{} = dt}), do: dt
  defp display_activity_at(%{last_outbound_at: %DateTime{} = dt}), do: dt
  defp display_activity_at(_thread), do: nil

  defp compose_form(attrs \\ %{}) do
    defaults = %{
      "to" => "",
      "cc" => "",
      "bcc" => "",
      "subject" => "",
      "body" => "",
      "scheduled_at" => ""
    }

    to_form(Map.merge(defaults, stringify_keys(attrs)), as: :compose)
  end

  defp compose_form_with_recipient_errors(attrs, errors) do
    form_errors =
      for field <- [:to, :cc, :bcc], Map.has_key?(errors, field) do
        {field, {gettext("Enter a valid email address"), []}}
      end

    compose_form_with_errors(attrs, form_errors)
  end

  defp compose_form_with_body_error(attrs, message) do
    compose_form_with_errors(attrs, body: {message, []})
  end

  defp compose_form_with_to_error(attrs, message) do
    compose_form_with_errors(attrs, to: {message, []})
  end

  defp compose_form_with_errors(attrs, errors) do
    attrs
    |> compose_form()
    |> Map.put(:errors, errors)
  end

  defp compose_form(socket, attrs) do
    socket.assigns.compose_form
    |> compose_form_attrs()
    |> Map.merge(stringify_keys(attrs))
    |> compose_form()
  end

  defp compose_form_attrs(%Phoenix.HTML.Form{params: params}) when is_map(params) do
    Map.take(params, ["to", "cc", "bcc", "subject", "body", "scheduled_at"])
  end

  defp compose_form_attrs(_form), do: %{}

  defp assign_recipient_suggestions(socket, field, value) do
    query = current_recipient_query(value)

    if query == "" do
      clear_recipient_suggestions(socket)
    else
      suggestions =
        case Contacts.search_email_recipients(socket.assigns.current_scope, query, 6) do
          {:ok, contacts} -> Enum.map(contacts, &recipient_suggestion/1)
          {:error, _reason} -> []
        end

      assign(socket,
        compose_recipient_field: field,
        compose_recipient_suggestions: suggestions
      )
    end
  end

  defp clear_recipient_suggestions(socket) do
    assign(socket, compose_recipient_field: nil, compose_recipient_suggestions: [])
  end

  defp current_recipient_query(nil), do: ""

  defp current_recipient_query(value) do
    value
    |> to_string()
    |> String.split(",")
    |> List.last()
    |> to_string()
    |> String.trim()
  end

  defp insert_recipient_email(value, email) do
    parts = value |> to_string() |> String.split(",")

    parts
    |> List.replace_at(length(parts) - 1, " #{email}")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
    |> Kernel.<>(", ")
  end

  defp recipient_suggestion(contact) do
    name = contact_full_name(contact)

    %{
      id: contact.id,
      email: contact.email,
      label: if(name == "", do: contact.email, else: name),
      meta: recipient_suggestion_meta(contact)
    }
  end

  defp recipient_suggestion_meta(contact) do
    case loaded_company_name(contact) do
      "" -> contact.email
      company_name -> "#{contact.email} - #{company_name}"
    end
  end

  defp contact_full_name(contact) do
    [contact.first_name, contact.last_name]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" ")
  end

  defp loaded_company_name(%{company: %{name: name}}) when is_binary(name), do: name
  defp loaded_company_name(_contact), do: ""

  defp scheduled_at_from_params(%{"schedule_preset" => "tomorrow"}) do
    scheduled_local_datetime(Date.add(Konevo.DateTime.local_today(), 1), ~T[09:00:00])
  end

  defp scheduled_at_from_params(%{"schedule_preset" => "monday"}) do
    Konevo.DateTime.local_today()
    |> next_monday()
    |> scheduled_local_datetime(~T[09:00:00])
  end

  defp scheduled_at_from_params(%{"scheduled_at" => value}), do: value
  defp scheduled_at_from_params(_params), do: nil

  defp schedule_preset_input_value(:tomorrow) do
    schedule_input_value(Date.add(Konevo.DateTime.local_today(), 1), ~T[09:00:00])
  end

  defp schedule_preset_input_value(:monday) do
    Konevo.DateTime.local_today()
    |> next_monday()
    |> schedule_input_value(~T[09:00:00])
  end

  defp schedule_input_value(date, time) do
    date
    |> NaiveDateTime.new!(time)
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp scheduled_local_datetime(date, time) do
    date
    |> NaiveDateTime.new!(time)
    |> Konevo.DateTime.from_local_naive!()
  end

  defp next_monday(today) do
    days = rem(8 - Date.day_of_week(today), 7)
    Date.add(today, if(days == 0, do: 7, else: days))
  end

  defp schedule_error(:missing_recipient), do: gettext("Add at least one recipient")
  defp schedule_error(:missing_body), do: gettext("Write a message before scheduling")

  defp schedule_error(:no_integration),
    do: gettext("No Gmail account connected. Please connect Gmail in Settings")

  defp schedule_error(:invalid_scheduled_at), do: gettext("Choose a valid schedule time")

  defp schedule_error(:scheduled_at_in_past),
    do: gettext("Choose a schedule time at least one minute from now")

  defp schedule_error(:scheduled_at_too_soon),
    do: gettext("Choose a schedule time at least one minute from now")

  defp schedule_error(%Ecto.Changeset{}), do: gettext("Could not schedule email")
  defp schedule_error(_reason), do: gettext("Could not schedule email")

  defp put_compose_attachment_params(socket, params) do
    params
    |> Map.put("attachment_owner_id", socket.assigns.compose_attachment_owner_id)
    |> Map.put("attachment_ids", Enum.map(socket.assigns.compose_attachments, & &1.id))
  end

  defp reset_compose(socket) do
    assign(socket,
      compose_open?: false,
      compose_minimized?: false,
      compose_form: compose_form(),
      compose_recipient_field: nil,
      compose_recipient_suggestions: [],
      compose_attachments: [],
      compose_attachment_owner_id: Ecto.UUID.generate()
    )
  end

  defp discard_compose_attachments(%{assigns: %{compose_attachments: []}} = socket), do: socket

  defp discard_compose_attachments(socket) do
    case delete_draft_attachments(
           socket.assigns.current_scope,
           socket.assigns.compose_attachment_owner_id,
           socket.assigns.compose_attachments
         ) do
      :ok ->
        socket

      {:error, _reason} ->
        put_flash(socket, :warning, gettext("Some attachments could not be removed"))
    end
  end

  defp delete_draft_attachments(scope, owner_id, attachments) do
    results =
      Enum.map(attachments, fn attachment ->
        Uploads.delete_email_draft_attachment(scope, attachment.id, owner_id)
      end)

    if Enum.all?(results, &match?({:ok, _file}, &1)), do: :ok, else: {:error, :cleanup_failed}
  end

  defp reject_attachment(socket, id) do
    Enum.reject(socket.assigns.compose_attachments, &(to_string(&1.id) == to_string(id)))
  end

  defp compose_uploading?(%{assigns: %{uploads: uploads}}),
    do: compose_uploading?(uploads.compose_attachment)

  defp compose_uploading?(upload) do
    Enum.any?(upload.entries, &(not &1.done?))
  end

  defp handle_compose_attachment_progress(:compose_attachment, entry, socket) do
    if entry.done? do
      save_compose_attachment(socket, entry)
    else
      {:noreply, socket}
    end
  end

  defp save_compose_attachment(socket, entry) do
    scope = socket.assigns.current_scope

    result =
      consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
        {:ok,
         UploadProcessor.process(
           temp_path,
           :mixed_attachment,
           to_string(scope.org.id),
           socket.assigns.compose_attachment_owner_id,
           "email_draft",
           entry.client_name
         )}
      end)

    case result do
      {:ok, file} ->
        {:noreply,
         socket
         |> update(:compose_attachments, &[file | &1])
         |> put_flash(:success, gettext("File attached"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not attach file"))}
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes < 1_024 -> "#{bytes} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1_024, 1)} KB"
      bytes < 1_073_741_824 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
    end
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 ->
        gettext("just now")

      diff < 3600 ->
        ngettext("1m ago", "%{count}m ago", div(diff, 60), count: div(diff, 60))

      diff < 86_400 ->
        ngettext("1h ago", "%{count}h ago", div(diff, 3600), count: div(diff, 3600))

      diff < 86_400 * 7 ->
        ngettext("1d ago", "%{count}d ago", div(diff, 86_400), count: div(diff, 86_400))

      true ->
        Konevo.DateTime.format_local(dt, "%b %d")
    end
  end

  defp format_scheduled_at(nil), do: ""

  defp format_scheduled_at(%DateTime{} = dt) do
    Konevo.DateTime.format_local(dt, "%b %d, %Y at %H:%M")
  end

  defp scheduled_status_label(:pending), do: gettext("Pending")
  defp scheduled_status_label(:sent), do: gettext("Sent")
  defp scheduled_status_label(:cancelled), do: gettext("Cancelled")
  defp scheduled_status_label(:failed), do: gettext("Failed")
  defp scheduled_status_label(status), do: Phoenix.Naming.humanize(status)

  defp scheduled_status_class(:pending), do: "badge badge-warning badge-sm"
  defp scheduled_status_class(:sent), do: "badge badge-success badge-sm"
  defp scheduled_status_class(:cancelled), do: "badge badge-ghost badge-sm"
  defp scheduled_status_class(:failed), do: "badge badge-error badge-sm"
  defp scheduled_status_class(_status), do: "badge badge-ghost badge-sm"

  attr :field, :any, required: true
  attr :recipient_name, :string, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :active_field, :string, default: nil
  attr :suggestions, :list, default: []
  attr :wrapper_class, :string, default: "border-b border-base-content/8 px-3 py-2"

  defp compose_recipient_input(assigns) do
    errors = Enum.map(assigns.field.errors, &translate_error/1)
    assigns = assign(assigns, :errors, errors)

    ~H"""
    <div class={["relative", @wrapper_class]}>
      <div class="flex items-center gap-3">
        <label for={@field.id} class="w-12 shrink-0 text-xs font-semibold text-base-content/45">
          {@label}
        </label>
        <input
          type="text"
          name={@field.name}
          id={@field.id}
          value={@field.value}
          placeholder={@placeholder}
          autocomplete="off"
          aria-invalid={if(@errors == [], do: "false", else: "true")}
          aria-describedby={if(@errors == [], do: nil, else: "#{@field.id}-error")}
          class={[
            "min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-base-content/30",
            @errors != [] && "text-error"
          ]}
        />
      </div>

      <p
        :if={@errors != []}
        id={"#{@field.id}-error"}
        class="ml-15 mt-1 text-xs font-medium text-error"
      >
        {Enum.join(@errors, ", ")}
      </p>

      <div
        :if={@active_field == @recipient_name and @suggestions != []}
        id={"compose-#{@recipient_name}-suggestions"}
        class="absolute left-0 right-0 top-full z-[120] mt-1 max-h-40 overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-2xl"
      >
        <button
          :for={suggestion <- @suggestions}
          type="button"
          id={"compose-recipient-suggestion-#{@recipient_name}-#{suggestion.id}"}
          phx-click="select_compose_recipient"
          phx-value-field={@recipient_name}
          phx-value-email={suggestion.email}
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left transition-colors hover:bg-primary/8 focus:bg-primary/8 focus:outline-none"
        >
          <span class="flex size-7 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
            <.icon name="icon-[tabler--mail]" class="size-3.5" />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-semibold text-base-content">
              {suggestion.label}
            </span>
            <span class="block truncate text-xs text-base-content/45">{suggestion.meta}</span>
          </span>
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    total_pages = total_pages(assigns.total)

    assigns =
      assigns
      |> assign(:total_pages, total_pages)
      |> assign(:page_numbers, page_display(assigns.page, total_pages))
      |> assign(
        :page_from,
        if(assigns.total > 0, do: (assigns.page - 1) * @per_page + 1, else: 0)
      )
      |> assign(:page_to, min(assigns.page * @per_page, assigns.total))
      |> assign(:all_categories, @categories)
      |> assign(:all_views, @views)
      |> assign(:per_page, @per_page)
      |> assign(:selected_thread_count, MapSet.size(assigns.selected_thread_ids))
      |> assign(
        :has_active_filters,
        assigns.filter_category != nil or assigns.filter_unresolved != nil
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <%!-- Main inbox layout: left sidebar + right content --%>
        <div class="flex items-start gap-2">
          <%!-- Left sidebar — no bg, no border, blends into page --%>
          <div class="sticky top-4 hidden max-h-[calc(100vh-6rem)] w-52 shrink-0 flex-col overflow-y-auto rounded-xl border border-neutral/30 bg-base-100 py-3 sm:flex">
            <%!-- Compose button --%>
            <button
              id="inbox-desktop-compose"
              type="button"
              phx-click="open_compose"
              class="mx-2 mb-4 flex items-center justify-center gap-1.5 rounded-lg border border-primary/30 bg-primary/8 px-3 py-2 text-sm font-semibold text-primary shadow-sm transition-all hover:bg-primary/15 hover:shadow-md"
            >
              {gettext("Compose")}
              <span class="icon-[tabler--send] size-3.5 font-semibold" />
            </button>

            <%= for {label, view, icon, count} <- [
                {gettext("Inbox"), :inbox, "icon-[tabler--inbox]", Map.get(@view_counts, :inbox, 0)},
                {gettext("Favorites"), :favorites, "icon-[tabler--star]", Map.get(@view_counts, :favorites, 0)},
                {gettext("Sent"), :sent, "icon-[tabler--send]", Map.get(@view_counts, :sent, 0)},
                {gettext("Scheduled"), :scheduled, "icon-[tabler--clock]", Map.get(@view_counts, :scheduled, 0)},
              {gettext("Archived"), :archived, "icon-[tabler--archive]", Map.get(@view_counts, :archived, 0)},
              {gettext("Bin"), :bin, "icon-[tabler--trash]", Map.get(@view_counts, :bin, 0)}
            ] do %>
              <button
                type="button"
                phx-click="switch_view"
                phx-value-view={view}
                class={[
                  "mx-2 flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                  if(@inbox_view == view,
                    do: "bg-primary/10 text-primary",
                    else: "text-base-content/80 hover:bg-base-200 hover:text-base-content"
                  )
                ]}
              >
                <span class={[icon, "size-4 shrink-0"]} />
                {label}
                <span
                  :if={count > 0}
                  class={[
                    "ml-auto rounded-full px-1.5 py-0.5 text-xs font-semibold leading-none tabular-nums",
                    if(@inbox_view == view,
                      do: "bg-primary/15 text-primary",
                      else: "bg-base-content/8 text-base-content/40"
                    )
                  ]}
                >
                  {count}
                </span>
              </button>
            <% end %>
          </div>

          <%!-- Right: toolbar + tabs + list --%>
          <div class="min-w-0 flex-1 flex flex-col rounded-xl border border-neutral/30 bg-base-100">
            <%!-- Mobile compose action + view switcher --%>
            <div class="flex items-center gap-2 border-b border-base-content/10 px-3 py-2.5 sm:hidden">
              <button
                id="inbox-mobile-compose"
                type="button"
                phx-click="open_compose"
                class="btn btn-primary btn-sm btn-square h-8 w-8 shrink-0 rounded-md p-0 shadow-sm"
                aria-label={gettext("Compose")}
                title={gettext("Compose")}
              >
                <span class="icon-[tabler--pencil] size-3.5" />
              </button>
              <div aria-hidden="true" class="h-6 w-px shrink-0 bg-base-content/10" />
              <div class="flex min-w-0 flex-1 gap-1 overflow-x-auto scrollbar-none">
                <%= for {label, view, icon} <- [
                  {gettext("Inbox"), :inbox, "icon-[tabler--inbox]"},
                  {gettext("Favorites"), :favorites, "icon-[tabler--star]"},
                  {gettext("Sent"), :sent, "icon-[tabler--send]"},
                  {gettext("Scheduled"), :scheduled, "icon-[tabler--clock]"},
                  {gettext("Archived"), :archived, "icon-[tabler--archive]"},
                  {gettext("Bin"), :bin, "icon-[tabler--trash]"}
                ] do %>
                  <button
                    type="button"
                    phx-click="switch_view"
                    phx-value-view={view}
                    aria-pressed={@inbox_view == view}
                    class={[
                      "flex shrink-0 items-center gap-1.5 rounded-full border px-2.5 py-1.5 text-xs font-medium transition-colors",
                      if(@inbox_view == view,
                        do: "border-primary/25 bg-primary/10 text-primary shadow-sm",
                        else:
                          "border-transparent bg-base-200/70 text-base-content/60 hover:border-base-content/10 hover:bg-base-200 hover:text-base-content"
                      )
                    ]}
                  >
                    <span class={[icon, "size-3.5"]} />
                    {label}
                  </button>
                <% end %>
              </div>
            </div>

            <%!-- Toolbar --%>
            <div class="flex flex-wrap items-center gap-2 px-3 py-2.5 sm:py-3">
              <%!-- Search --%>
              <div class="relative order-1 min-w-0 flex-1 sm:order-none sm:w-64 sm:flex-none">
                <span class="icon-[tabler--search] pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40" />
                <form phx-change="search" phx-submit="search" id="inbox-search-form">
                  <input
                    type="text"
                    name="q"
                    value={@search}
                    placeholder={gettext("Search subjects...")}
                    phx-debounce="300"
                    class={[
                      "input input-sm input-bordered w-full pl-8 pr-8 transition-colors",
                      @search != "" && "border-primary/60"
                    ]}
                    autocomplete="off"
                  />
                </form>
                <button
                  :if={@search != ""}
                  phx-click="clear_search"
                  type="button"
                  aria-label={gettext("Clear search")}
                  class="absolute right-2.5 top-1/2 -translate-y-1/2 text-base-content/40 hover:text-base-content transition-colors"
                >
                  <span class="icon-[tabler--x] size-3.5" />
                </button>
              </div>

              <%!-- Mobile category selector --%>
              <div
                :if={@inbox_view != :scheduled}
                id="inbox-mobile-category-filter"
                class="relative order-3 w-full sm:hidden"
                phx-hook="FilterPanel"
              >
                <button
                  type="button"
                  data-toggle
                  class="btn btn-sm min-w-36 justify-between border border-base-content/20 bg-base-100 px-3 text-base-content transition-colors hover:border-base-content/30"
                >
                  <span class="flex min-w-0 items-center gap-2">
                    <.icon
                      name={elem(category_filter_option(@filter_category), 3)}
                      class="size-3.5 shrink-0 text-primary"
                    />
                    <span class="truncate text-sm font-semibold">
                      {elem(category_filter_option(@filter_category), 0)}
                    </span>
                  </span>
                  <span class="flex items-center gap-2 text-base-content/50">
                    <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-base-content/8 text-[10px] font-bold leading-none tabular-nums">
                      {category_count(@stats, @filter_category, @total)}
                    </span>
                    <.icon name="icon-[tabler--chevron-down]" class="size-3.5" />
                  </span>
                </button>

                <div
                  data-panel
                  class="row-menu-closed z-30 w-[calc(100vw-2rem)] max-w-sm overflow-hidden rounded-xl border border-base-content/20 bg-base-100 p-1 shadow-xl"
                >
                  <button
                    :for={{label, category, id, icon} <- category_filter_options()}
                    type="button"
                    phx-click="filter_category"
                    phx-value-category={id}
                    phx-value-select="true"
                    data-close-panel
                    class={[
                      "flex w-full items-center gap-2.5 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
                      if(@filter_category == category,
                        do: "bg-primary/10 text-primary",
                        else: "text-base-content/70 hover:bg-base-200 hover:text-base-content"
                      )
                    ]}
                  >
                    <.icon name={icon} class="size-3.5 shrink-0" />
                    <span class="min-w-0 flex-1 text-left">{label}</span>
                    <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-base-content/8 text-[10px] font-bold leading-none tabular-nums">
                      {category_count(@stats, category, @total)}
                    </span>
                    <.icon
                      :if={@filter_category == category}
                      name="icon-[tabler--check]"
                      class="size-3.5 shrink-0"
                    />
                  </button>
                </div>
              </div>

              <button
                type="button"
                id="inbox-refresh"
                phx-click="refresh"
                disabled={@gmail_syncing?}
                aria-label={gettext("Check mail now")}
                title={gettext("Check mail now")}
                class={[
                  "order-2 btn btn-sm btn-square rounded-md border border-primary/25 bg-primary/10 text-primary shadow-sm transition-all hover:border-primary/40 hover:bg-primary/15 disabled:cursor-wait disabled:border-primary/20 disabled:bg-primary/10 disabled:text-primary sm:order-none",
                  @gmail_syncing? && "shadow-primary/10"
                ]}
              >
                <.icon
                  name="icon-[tabler--refresh]"
                  class={["size-5 shrink-0", @gmail_syncing? && "animate-spin"]}
                />
              </button>

              <%!-- Actions --%>
              <div class="relative z-20 hidden max-w-full items-center gap-1 overflow-visible sm:ml-auto sm:flex">
                <.action_popover tip={gettext("Select all visible threads")}>
                  <label class="flex size-7 cursor-pointer items-center justify-center">
                    <input
                      type="checkbox"
                      id="inbox-select-all"
                      class="checkbox checkbox-xs m-0 shrink-0 -translate-y-px rounded-sm"
                      phx-click="toggle_select_all"
                      checked={@select_all?}
                      aria-label={gettext("Select all visible threads")}
                    />
                  </label>
                </.action_popover>

                <%!-- Separator --%>
                <span class="mx-1 h-5 w-px bg-base-content/15" />

                <%!-- Action icons --%>
                <.action_popover tip={gettext("Restore selected threads to Inbox")}>
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="restore"
                    aria-label={gettext("Restore selected threads to Inbox")}
                    class="flex size-7 items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-200 hover:text-base-content"
                  >
                    <span class="icon-[tabler--inbox] size-4" />
                  </button>
                </.action_popover>
                <.action_popover tip={gettext("Toggle favorite for selected threads")}>
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="favorite"
                    aria-label={gettext("Toggle favorite for selected threads")}
                    class="flex size-7 items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-200 hover:text-warning"
                  >
                    <.icon name="icon-[tabler--star]" class="size-4" />
                  </button>
                </.action_popover>
                <.action_popover tip={gettext("Move selected threads to Bin")}>
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="move_to_bin"
                    aria-label={gettext("Move selected threads to Bin")}
                    class="flex size-7 items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-200 hover:text-error"
                  >
                    <span class="icon-[tabler--trash] size-4" />
                  </button>
                </.action_popover>

                <%!-- Separator --%>
                <span class="mx-1 h-5 w-px bg-base-content/15" />

                <.action_popover tip={gettext("Mark selected threads as read")}>
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="mark_read"
                    aria-label={gettext("Mark selected threads as read")}
                    class="flex size-7 items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-200 hover:text-base-content"
                  >
                    <span class="icon-[tabler--mail] size-4" />
                  </button>
                </.action_popover>
                <.action_popover tip={gettext("Archive selected threads")}>
                  <button
                    id="inbox-bulk-archive-desktop"
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="archive"
                    aria-label={gettext("Archive selected threads")}
                    class="flex size-7 items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-200 hover:text-base-content"
                  >
                    <span class="icon-[tabler--archive] size-4" />
                  </button>
                </.action_popover>
              </div>

              <div
                :if={@selected_thread_count > 0}
                id="inbox-mobile-selection-actions"
                class="order-4 flex w-full items-center gap-1.5 rounded-lg border border-primary/20 bg-primary/5 px-2 py-1.5 sm:hidden"
              >
                <button
                  type="button"
                  phx-click="clear_selected"
                  class="flex items-center gap-1 rounded-md px-1.5 py-1 text-xs font-semibold text-primary transition-colors hover:bg-primary/10"
                >
                  <.icon name="icon-[tabler--x]" class="size-3.5" />
                  {gettext("%{count} selected", count: @selected_thread_count)}
                </button>
                <div class="ml-auto flex items-center gap-0.5">
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="restore"
                    aria-label={gettext("Restore selected threads to Inbox")}
                    class="flex size-8 items-center justify-center rounded-md text-base-content/55 transition-colors hover:bg-base-100 hover:text-base-content"
                  >
                    <.icon name="icon-[tabler--inbox]" class="size-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="favorite"
                    aria-label={gettext("Toggle favorite for selected threads")}
                    class="flex size-8 items-center justify-center rounded-md text-base-content/55 transition-colors hover:bg-base-100 hover:text-warning"
                  >
                    <.icon name="icon-[tabler--star]" class="size-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="mark_read"
                    aria-label={gettext("Mark selected threads as read")}
                    class="flex size-8 items-center justify-center rounded-md text-base-content/55 transition-colors hover:bg-base-100 hover:text-base-content"
                  >
                    <.icon name="icon-[tabler--mail]" class="size-4" />
                  </button>
                  <button
                    id="inbox-bulk-archive-mobile"
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="archive"
                    aria-label={gettext("Archive selected threads")}
                    class="flex size-8 items-center justify-center rounded-md text-base-content/55 transition-colors hover:bg-base-100 hover:text-base-content"
                  >
                    <.icon name="icon-[tabler--archive]" class="size-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="bulk_action"
                    phx-value-action="move_to_bin"
                    aria-label={gettext("Move selected threads to Bin")}
                    class="flex size-8 items-center justify-center rounded-md text-base-content/55 transition-colors hover:bg-base-100 hover:text-error"
                  >
                    <.icon name="icon-[tabler--trash]" class="size-4" />
                  </button>
                </div>
              </div>
            </div>

            <%!-- Desktop category tabs --%>
            <nav
              :if={@inbox_view != :scheduled}
              id="inbox-category-tabs"
              role="tablist"
              class="hidden min-h-12 overflow-x-auto border-b border-base-content/10 px-1 sm:flex"
              aria-label={gettext("Inbox categories")}
            >
              <%= for {label, cat, tab_id, icon} <- category_filter_options() do %>
                <button
                  type="button"
                  id={"inbox-tab-#{tab_id}"}
                  role="tab"
                  phx-click="filter_category"
                  phx-value-category={tab_id}
                  data-tab={"tabs-icon-#{tab_id}"}
                  aria-controls="inbox-threads"
                  aria-selected={@filter_category == cat}
                  class={[
                    "flex min-w-[7.75rem] items-center justify-center gap-2 whitespace-nowrap rounded-none border-b-2 px-4 py-3 text-sm font-semibold transition-colors duration-150 !rounded-none",
                    if(@filter_category == cat,
                      do: "border-primary text-primary",
                      else:
                        "border-transparent text-base-content/80 hover:border-base-content/20 hover:text-base-content"
                    )
                  ]}
                >
                  <.icon name={icon} class="size-4 shrink-0" />
                  {label}
                  <span class={[
                    "rounded-full px-2 py-0.5 text-xs font-bold leading-none tabular-nums",
                    if(@filter_category == cat,
                      do: "bg-primary/15 text-primary",
                      else: "bg-base-content/8 text-base-content/40"
                    )
                  ]}>
                    {category_count(@stats, cat, @total)}
                  </span>
                </button>
              <% end %>
            </nav>

            <div
              :if={@inbox_view == :scheduled}
              class="flex items-center gap-2 border-b border-base-content/10 px-4 py-3"
            >
            </div>

            <%!-- Thread list --%>
            <.async_result :let={_stream_ready?} assign={@threads}>
              <:loading>
                <div
                  id="inbox-threads-loading"
                  class="flex flex-col divide-y divide-base-content/8 border-t border-base-content/10 sm:border-t-0"
                  aria-busy="true"
                  aria-label={gettext("Loading threads")}
                >
                  <div :for={row <- 1..8} id={"thread-skeleton-#{row}"} class="px-4 py-3">
                    <div class="hidden items-center gap-3 sm:flex">
                      <div class="flex w-14 shrink-0 items-center justify-center gap-1.5">
                        <div class="skeleton size-4 rounded-sm" />
                        <div class="skeleton size-4 rounded-md" />
                      </div>
                      <div class="w-44 shrink-0 space-y-2">
                        <div class="skeleton h-3.5 w-28 rounded-md" />
                        <div class="skeleton h-3 w-14 rounded-md" />
                      </div>
                      <div class="min-w-0 flex-1 space-y-2">
                        <div class="skeleton h-3.5 w-3/4 rounded-md" />
                        <div class="skeleton h-3 w-full max-w-lg rounded-md" />
                      </div>
                      <div class="flex w-52 shrink-0 justify-end">
                        <div class="skeleton h-6 w-28 rounded-md" />
                      </div>
                    </div>

                    <div class="flex items-start gap-3 sm:hidden">
                      <div class="skeleton size-10 shrink-0 rounded-lg" />
                      <div class="min-w-0 flex-1 space-y-2">
                        <div class="flex items-center justify-between gap-3">
                          <div class="skeleton h-3.5 w-28 rounded-md" />
                          <div class="skeleton h-3 w-10 rounded-md" />
                        </div>
                        <div class="skeleton h-3.5 w-4/5 rounded-md" />
                        <div class="skeleton h-3 w-full rounded-md" />
                      </div>
                    </div>
                  </div>
                </div>
              </:loading>
              <:failed :let={_reason}>
                <div
                  id="inbox-threads-error"
                  class="flex flex-col items-center py-20 text-center"
                  role="alert"
                >
                  <.icon
                    name="icon-[tabler--alert-circle]"
                    class="mb-4 size-12 text-error/70"
                  />
                  <p class="font-medium text-error">{gettext("Failed to load threads")}</p>
                  <p class="mt-1 text-sm text-base-content/40">
                    {gettext("Please refresh the inbox and try again.")}
                  </p>
                </div>
              </:failed>

              <div
                id="inbox-threads"
                phx-update="stream"
                class="flex flex-col divide-y divide-base-content/8 border-t border-base-content/10 sm:border-t-0"
              >
                <div
                  id="threads-empty"
                  class="hidden flex-col items-center py-20 text-center only:flex"
                >
                  <.icon
                    name="icon-[tabler--inbox]"
                    class="mb-4 size-12 text-base-content/20"
                  />
                  <p class="font-medium text-base-content/50">{gettext("No threads found")}</p>
                  <p class="mt-1 text-sm text-base-content/30">
                    {gettext("Try adjusting your filters or search.")}
                  </p>
                </div>

                <%!-- Thread row --%>
                <div
                  :for={{id, scheduled_email} <- @streams.threads}
                  :if={@inbox_view == :scheduled}
                  id={id}
                  class="group border-b border-base-content/8 transition-colors hover:bg-primary/5"
                >
                  <div class="flex items-center gap-3 px-4 py-2.5">
                    <div class="flex size-8 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
                      <.icon name="icon-[tabler--clock]" class="size-4" />
                    </div>
                    <div class="min-w-0 flex-1">
                      <div class="flex flex-wrap items-center gap-2">
                        <p class="truncate text-sm font-semibold text-base-content">
                          {scheduled_email.subject || gettext("(no subject)")}
                        </p>
                        <span class={scheduled_status_class(scheduled_email.status)}>
                          {scheduled_status_label(scheduled_email.status)}
                        </span>
                      </div>
                      <div class="mt-0.5 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-base-content/45">
                        <span class="truncate">
                          {gettext("To:")} {Enum.join(scheduled_email.to || [], ", ")}
                        </span>
                        <span class="hidden text-base-content/25 sm:inline">/</span>
                        <span class="inline-flex shrink-0 items-center gap-1">
                          <.icon name="icon-[tabler--calendar-time]" class="size-3.5" />
                          {format_scheduled_at(scheduled_email.scheduled_at)}
                        </span>
                      </div>
                    </div>
                    <button
                      :if={scheduled_email.status == :pending}
                      type="button"
                      id={"scheduled-email-cancel-#{scheduled_email.id}"}
                      phx-click="cancel_scheduled_email"
                      phx-value-id={scheduled_email.id}
                      class="btn btn-xs shrink-0 border-base-content bg-base-content px-3 text-base-100 hover:border-base-content/85 hover:bg-base-content/85 hover:text-base-100"
                    >
                      {gettext("Cancel")}
                    </button>
                  </div>
                </div>

                <div
                  :for={{id, thread} <- @streams.threads}
                  :if={@inbox_view != :scheduled}
                  id={id}
                  class={[
                    "group transition-colors hover:bg-primary/5",
                    unread?(thread) && "bg-base-100",
                    !unread?(thread) && "bg-base-content/[0.03]"
                  ]}
                >
                  <%!-- Desktop layout --%>
                  <div class="hidden sm:flex items-center gap-2 px-4 py-2.5">
                    <%!-- Checkbox + star --%>
                    <div class="flex w-14 shrink-0 items-center justify-center gap-1.5">
                      <input
                        type="checkbox"
                        id={"thread-select-#{thread.id}"}
                        aria-label={gettext("Select thread")}
                        class="checkbox checkbox-xs rounded-sm"
                        phx-click="toggle_select_thread"
                        phx-value-id={thread.id}
                        data-inbox-thread-select={thread.id}
                        checked={thread_selected?(@selected_thread_ids, thread.id)}
                      />
                      <button
                        type="button"
                        id={"thread-star-#{thread.id}"}
                        phx-click="toggle_favorite"
                        phx-value-id={thread.id}
                        aria-label={gettext("Toggle favorite")}
                        class="flex size-7 items-center justify-center rounded-md text-base-content/30 transition-colors hover:bg-base-content/8 hover:text-warning"
                      >
                        <span class={[
                          "size-4",
                          if(thread.is_favorite,
                            do: "icon-[tabler--star-filled] text-warning",
                            else: "icon-[tabler--star] text-base-content/25"
                          )
                        ]} />
                      </button>
                    </div>

                    <.link
                      navigate={~p"/inbox/#{thread.id}"}
                      class="flex min-w-0 flex-1 items-center gap-2"
                    >
                      <%!-- Sender + time --%>
                      <div class="w-44 shrink-0">
                        <div class="flex min-w-0 items-center gap-1.5">
                          <p
                            class={[
                              "truncate text-sm leading-tight",
                              if(unread?(thread),
                                do: "font-bold text-base-content",
                                else: "font-normal text-base-content/40"
                              )
                            ]}
                            id={"thread-sender-#{thread.id}"}
                          >
                            {thread_sender(thread, @mailbox_emails)}
                          </p>
                          <span
                            :if={sender_info?(thread, @mailbox_emails)}
                            class="sender-info-trigger"
                            data-sender-details={sender_details(thread, @mailbox_emails)}
                          >
                            <.icon name="icon-[tabler--info-circle]" class="size-3.5" />
                            <span class="sender-info-popover">
                              {sender_details(thread, @mailbox_emails)}
                            </span>
                          </span>
                          <span
                            :if={new_unread?(thread)}
                            class="inline-flex shrink-0 items-center rounded-full bg-emerald-500/12 px-1.5 py-0.5 text-[10px] font-bold uppercase leading-none text-emerald-600 ring-1 ring-emerald-500/20"
                          >
                            {gettext("New")}
                          </span>
                        </div>
                        <p class={[
                          "mt-0.5 text-xs",
                          if(unread?(thread),
                            do: "text-base-content/50",
                            else: "text-base-content/30"
                          )
                        ]}>
                          {format_time(display_activity_at(thread))}
                        </p>
                      </div>

                      <%!-- Subject + snippet --%>
                      <div class="min-w-0 flex-1 overflow-hidden">
                        <p class={[
                          "truncate text-sm leading-snug",
                          if(unread?(thread),
                            do: "font-semibold text-base-content",
                            else: "font-normal text-base-content/40"
                          )
                        ]}>
                          {thread.subject || gettext("(no subject)")}
                          <span
                            :if={email_count(thread) > 1}
                            id={"thread-message-count-#{thread.id}"}
                            class="ml-1 font-semibold text-base-content/35"
                          >
                            {"(#{email_count(thread)})"}
                          </span>
                        </p>
                        <p class={[
                          "mt-0.5 truncate text-xs leading-tight",
                          if(unread?(thread),
                            do: "text-base-content/50",
                            else: "text-base-content/30"
                          )
                        ]}>
                          {thread.snippet}
                        </p>
                      </div>
                    </.link>

                    <%!-- Right: category pill --%>
                    <div class="flex w-52 shrink-0 items-center justify-end gap-1.5 pr-4">
                      <span
                        :if={thread.has_attachments}
                        class="icon-[tabler--paperclip] size-3.5 text-base-content/35"
                      />
                      <span
                        :if={thread.is_unresolved}
                        class="icon-[tabler--alert-circle] size-3.5 text-warning"
                      />
                      <.category_picker thread={thread} />
                    </div>
                  </div>

                  <%!-- Mobile layout --%>
                  <div class="flex items-start gap-2.5 px-3 py-3 sm:hidden">
                    <input
                      type="checkbox"
                      id={"thread-select-mobile-#{thread.id}"}
                      aria-label={gettext("Select thread")}
                      class="checkbox checkbox-xs mt-2 shrink-0 rounded-sm"
                      phx-click="toggle_select_thread"
                      phx-value-id={thread.id}
                      data-inbox-thread-select={thread.id}
                      checked={thread_selected?(@selected_thread_ids, thread.id)}
                    />
                    <div class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-bold text-primary">
                      {sender_initials(thread, @mailbox_emails)}
                    </div>

                    <div class="min-w-0 flex-1">
                      <div class="flex min-w-0 items-center gap-1.5">
                        <.link
                          navigate={~p"/inbox/#{thread.id}"}
                          class="flex min-w-0 flex-1 items-center gap-1.5"
                        >
                          <p
                            class={[
                              "min-w-0 flex-1 truncate text-sm leading-tight",
                              if(unread?(thread),
                                do: "font-semibold text-base-content",
                                else: "font-normal text-base-content/55"
                              )
                            ]}
                            id={"thread-sender-mobile-#{thread.id}"}
                          >
                            {thread_sender(thread, @mailbox_emails)}
                          </p>
                          <span
                            :if={new_unread?(thread)}
                            class="inline-flex shrink-0 items-center rounded-full bg-emerald-500/12 px-1.5 py-0.5 text-[10px] font-bold uppercase leading-none text-emerald-600 ring-1 ring-emerald-500/20"
                          >
                            {gettext("New")}
                          </span>
                          <span class={[
                            "shrink-0 text-[11px] tabular-nums",
                            if(unread?(thread),
                              do: "text-base-content/50",
                              else: "text-base-content/35"
                            )
                          ]}>
                            {format_time(display_activity_at(thread))}
                          </span>
                        </.link>
                        <button
                          type="button"
                          phx-click="toggle_favorite"
                          phx-value-id={thread.id}
                          aria-label={gettext("Toggle favorite")}
                          class="flex size-8 shrink-0 items-center justify-center rounded-full text-base-content/35 transition-colors hover:bg-warning/10 hover:text-warning"
                        >
                          <span class={[
                            "size-4",
                            if(thread.is_favorite,
                              do: "icon-[tabler--star-filled] text-warning",
                              else: "icon-[tabler--star] text-base-content/30"
                            )
                          ]} />
                        </button>
                      </div>

                      <.link navigate={~p"/inbox/#{thread.id}"} class="block min-w-0 pt-1">
                        <p class={[
                          "truncate text-sm leading-snug",
                          if(unread?(thread),
                            do: "font-semibold text-base-content",
                            else: "font-normal text-base-content/55"
                          )
                        ]}>
                          {thread.subject || gettext("(no subject)")}
                          <span
                            :if={email_count(thread) > 1}
                            id={"thread-message-count-mobile-#{thread.id}"}
                            class="ml-1 font-semibold text-base-content/35"
                          >
                            {"(#{email_count(thread)})"}
                          </span>
                        </p>
                        <p class={[
                          "mt-0.5 truncate text-xs leading-tight",
                          if(unread?(thread),
                            do: "text-base-content/50",
                            else: "text-base-content/35"
                          )
                        ]}>
                          {thread.snippet}
                        </p>
                      </.link>

                      <div class="mt-2 flex items-center justify-between gap-2">
                        <.category_picker thread={thread} compact />
                        <div class="flex shrink-0 items-center gap-1.5 text-base-content/40">
                          <span
                            :if={sender_info?(thread, @mailbox_emails)}
                            class="sender-info-trigger"
                            data-sender-details={sender_details(thread, @mailbox_emails)}
                          >
                            <.icon name="icon-[tabler--info-circle]" class="size-3.5" />
                            <span class="sender-info-popover">
                              {sender_details(thread, @mailbox_emails)}
                            </span>
                          </span>
                          <span
                            :if={thread.has_attachments}
                            class="icon-[tabler--paperclip] size-3.5"
                          />
                          <span
                            :if={thread.is_unresolved}
                            class="icon-[tabler--alert-circle] size-3.5 text-warning"
                          />
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </.async_result>

            <%!-- Pagination --%>
            <div
              :if={@threads.ok? and !@threads.loading and @total > @per_page}
              class="flex items-center justify-between border-t border-base-content/10 px-4 py-3 text-sm text-base-content/50"
            >
              <span>
                {gettext("Showing %{from}–%{to} of %{total}",
                  from: @page_from,
                  to: @page_to,
                  total: @total
                )}
              </span>
              <div class="flex items-center gap-1">
                <button
                  type="button"
                  phx-click="page"
                  phx-value-n={@page - 1}
                  disabled={@page <= 1}
                  class="btn btn-xs btn-ghost"
                >
                  <span class="icon-[tabler--chevron-left] size-3.5" />
                </button>
                <%= for n <- @page_numbers do %>
                  <%= if n == :gap do %>
                    <span class="px-1 text-base-content/30">…</span>
                  <% else %>
                    <button
                      type="button"
                      phx-click="page"
                      phx-value-n={n}
                      class={[
                        "btn btn-xs",
                        if(n == @page, do: "btn-primary", else: "btn-ghost")
                      ]}
                    >
                      {n}
                    </button>
                  <% end %>
                <% end %>
                <button
                  type="button"
                  phx-click="page"
                  phx-value-n={@page + 1}
                  disabled={@page >= @total_pages}
                  class="btn btn-xs btn-ghost"
                >
                  <span class="icon-[tabler--chevron-right] size-3.5" />
                </button>
              </div>
            </div>
          </div>
          <%!-- /right column --%>
        </div>
        <%!-- /sidebar layout --%>

        <%!-- Compose window (fixed bottom-right, Gmail style) --%>
        <div
          :if={@compose_open?}
          id="compose-window"
          class={[
            "inbox-compose-window fixed bottom-0 left-2 right-2 z-50 flex max-w-[calc(100vw-1rem)] flex-col overflow-hidden rounded-t-xl border border-base-content/20 bg-base-100 shadow-2xl sm:left-auto sm:right-6 sm:w-[560px]",
            if(@compose_minimized?, do: "h-10", else: "h-[min(620px,calc(100dvh-1rem))]")
          ]}
        >
          <%!-- Header --%>
          <div class="flex items-center gap-2 border-b border-secondary/35 bg-secondary/10 px-4 py-2.5">
            <button
              type="button"
              id="compose-header-toggle"
              phx-click="toggle_minimize_compose"
              class="flex min-w-0 flex-1 items-center gap-2 text-left"
              aria-label={gettext("Toggle compose window")}
            >
              <span class="icon-[tabler--pencil] size-4 text-base-content/70" />
              <span class="truncate text-sm font-semibold text-base-content">
                {gettext("New message")}
              </span>
            </button>
            <div class="flex items-center gap-1">
              <button
                type="button"
                phx-click="toggle_minimize_compose"
                class="topbar-action btn btn-sm btn-square btn-ghost"
                title={gettext("Minimize")}
              >
                <span class="icon-[tabler--minus] size-3.5" />
              </button>
              <button
                type="button"
                phx-click="close_compose"
                data-unsaved-confirm
                class="topbar-action btn btn-sm btn-square btn-ghost"
                title={gettext("Close")}
              >
                <span class="icon-[tabler--x] size-3.5" />
              </button>
            </div>
          </div>

          <%!-- Compose form (hidden when minimized) --%>
          <.form
            :if={!@compose_minimized?}
            for={@compose_form}
            id="compose-form"
            phx-change="validate_compose"
            phx-submit="send_message"
            phx-drop-target={@uploads.compose_attachment.ref}
            data-unsaved-form
            class="flex min-h-0 flex-1 flex-col"
          >
            <%!-- Recipients --%>
            <div class="overflow-visible border-b border-base-content/10 bg-base-200/20 px-4 py-2">
              <div class="rounded-md border border-base-content/10 bg-base-100 shadow-sm">
                <.compose_recipient_input
                  field={@compose_form[:to]}
                  recipient_name="to"
                  label={gettext("To")}
                  placeholder={gettext("name@example.com, team@example.com")}
                  active_field={@compose_recipient_field}
                  suggestions={@compose_recipient_suggestions}
                />

                <div class="grid gap-0 md:grid-cols-2 md:divide-x md:divide-base-content/8">
                  <.compose_recipient_input
                    field={@compose_form[:cc]}
                    recipient_name="cc"
                    label={gettext("Cc")}
                    placeholder={gettext("optional")}
                    active_field={@compose_recipient_field}
                    suggestions={@compose_recipient_suggestions}
                    wrapper_class="border-b border-base-content/8 px-3 py-2 md:border-b-0"
                  />

                  <.compose_recipient_input
                    field={@compose_form[:bcc]}
                    recipient_name="bcc"
                    label={gettext("Bcc")}
                    placeholder={gettext("optional")}
                    active_field={@compose_recipient_field}
                    suggestions={@compose_recipient_suggestions}
                    wrapper_class="px-3 py-2"
                  />
                </div>
              </div>
            </div>

            <%!-- Subject field --%>
            <div class="flex items-center gap-3 border-b border-base-content/10 px-4 py-2.5">
              <label
                for={@compose_form[:subject].id}
                class="w-16 shrink-0 text-xs font-semibold text-base-content/45"
              >
                {gettext("Subject")}
              </label>
              <input
                type="text"
                name={@compose_form[:subject].name}
                id={@compose_form[:subject].id}
                value={@compose_form[:subject].value}
                placeholder={gettext("Subject")}
                class="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-base-content/30"
              />
            </div>

            <%!-- Body — Tiptap editor (compact for compose) --%>
            <div class="min-h-0 flex-1 overflow-hidden">
              <.rich_text_input
                id="compose-body"
                field={@compose_form[:body]}
                placeholder={gettext("Write your message…")}
                fill_height={true}
                class="inbox-compose-editor !min-h-0 !rounded-none !border-0 !shadow-none tiptap-compact"
              />
            </div>

            <div
              :if={@compose_attachments != [] or @uploads.compose_attachment.entries != []}
              id="compose-attachments"
              class="max-h-36 space-y-1 overflow-y-auto border-t border-base-content/10 bg-base-200/30 px-4 py-2"
            >
              <div
                :for={entry <- @uploads.compose_attachment.entries}
                id={"compose-upload-#{entry.ref}"}
                class="flex items-center gap-2 rounded-md border border-base-content/10 bg-base-100 px-2.5 py-1.5 text-xs"
              >
                <span class="icon-[tabler--file-upload] size-4 shrink-0 text-primary" />
                <span class="min-w-0 flex-1 truncate">{entry.client_name}</span>
                <span class="w-10 text-right tabular-nums text-base-content/45">
                  {entry.progress}%
                </span>
                <button
                  type="button"
                  phx-click="cancel_compose_attachment"
                  phx-value-ref={entry.ref}
                  class="btn btn-ghost btn-xs btn-square"
                  aria-label={gettext("Cancel upload")}
                >
                  <span class="icon-[tabler--x] size-3.5" />
                </button>
              </div>

              <div
                :for={file <- @compose_attachments}
                id={"compose-attachment-#{file.id}"}
                class="flex items-center gap-2 rounded-md border border-base-content/10 bg-base-100 px-2.5 py-1.5 text-xs"
              >
                <span class="icon-[tabler--paperclip] size-4 shrink-0 text-base-content/40" />
                <span class="min-w-0 flex-1 truncate font-medium">{file.original_filename}</span>
                <span class="shrink-0 text-base-content/40">{format_bytes(file.byte_size)}</span>
                <button
                  type="button"
                  phx-click="delete_compose_attachment"
                  phx-value-id={file.id}
                  class="btn btn-ghost btn-xs btn-square"
                  aria-label={gettext("Remove attachment")}
                >
                  <span class="icon-[tabler--x] size-3.5" />
                </button>
              </div>
            </div>

            <%!-- Bottom bar --%>
            <div class="flex items-center gap-2 border-t border-base-content/10 bg-base-200/50 px-4 py-3">
              <.live_file_input upload={@uploads.compose_attachment} class="sr-only" />
              <div class="flex items-center gap-0.5 text-base-content/40">
                <span class="tooltip" data-tip={gettext("Attach files")}>
                  <label
                    for={@uploads.compose_attachment.ref}
                    class="btn btn-xs btn-ghost phx-submit-loading:pointer-events-none phx-submit-loading:opacity-50"
                  >
                    <span class="icon-[tabler--paperclip] size-4" />
                  </label>
                </span>
                <span class="tooltip" data-tip={gettext("Emoji")}>
                  <button
                    type="button"
                    class="btn btn-xs btn-ghost"
                    data-tiptap-command
                    data-tiptap-target="compose-body"
                    data-action="emoji"
                  >
                    <span class="icon-[tabler--mood-smile] size-4" />
                  </button>
                </span>
              </div>
              <div class="ml-auto flex items-center gap-1">
                <div
                  id="compose-schedule-dropdown"
                  class={[
                    "relative",
                    compose_uploading?(@uploads.compose_attachment) &&
                      "pointer-events-none opacity-50"
                  ]}
                  phx-hook="ScheduleDropdown"
                  data-schedule-dropdown
                >
                  <button
                    type="button"
                    id="compose-schedule-menu"
                    data-toggle
                    class="btn btn-primary btn-sm btn-square rounded-md"
                    title={gettext("Schedule send")}
                    aria-disabled={compose_uploading?(@uploads.compose_attachment)}
                  >
                    <span class="icon-[tabler--clock] size-4" />
                  </button>
                  <div
                    data-panel
                    class="absolute bottom-full right-0 z-[60] mb-2 hidden w-80 rounded-lg border border-base-content/10 bg-base-100 p-3 shadow-xl"
                  >
                    <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
                      {gettext("Schedule send")}
                    </p>
                    <button
                      type="button"
                      data-schedule-preset-target={@compose_form[:scheduled_at].id}
                      data-schedule-preset-value={schedule_preset_input_value(:tomorrow)}
                      disabled={compose_uploading?(@uploads.compose_attachment)}
                      class="mb-1 flex h-9 w-full items-center gap-2.5 rounded-md border border-base-content/10 px-3 text-sm font-medium text-base-content/70 transition-colors hover:border-primary/30 hover:bg-base-200 hover:text-base-content"
                    >
                      <span class="icon-[tabler--sun] size-4 shrink-0 text-warning" />
                      {gettext("Tomorrow morning")}
                    </button>
                    <button
                      type="button"
                      data-schedule-preset-target={@compose_form[:scheduled_at].id}
                      data-schedule-preset-value={schedule_preset_input_value(:monday)}
                      disabled={compose_uploading?(@uploads.compose_attachment)}
                      class="flex h-9 w-full items-center gap-2.5 rounded-md border border-base-content/10 px-3 text-sm font-medium text-base-content/70 transition-colors hover:border-primary/30 hover:bg-base-200 hover:text-base-content"
                    >
                      <span class="icon-[tabler--calendar-week] size-4 shrink-0 text-primary" />
                      {gettext("Monday morning")}
                    </button>
                    <div class="mt-2 border-t border-base-content/10 pt-2">
                      <label
                        for={@compose_form[:scheduled_at].id}
                        class="mb-1 block text-xs font-medium text-base-content/50"
                      >
                        {gettext("Custom time")}
                      </label>
                      <input
                        type="datetime-local"
                        name={@compose_form[:scheduled_at].name}
                        id={@compose_form[:scheduled_at].id}
                        value={@compose_form[:scheduled_at].value}
                        class="input input-sm input-bordered w-full"
                      />
                      <button
                        type="submit"
                        name="compose[schedule_preset]"
                        value="custom"
                        disabled={compose_uploading?(@uploads.compose_attachment)}
                        class="btn btn-sm btn-primary mt-2 w-full gap-2"
                      >
                        <span class="icon-[tabler--clock-plus] size-4" />
                        {gettext("Schedule")}
                      </button>
                    </div>
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={compose_uploading?(@uploads.compose_attachment)}
                  class="btn btn-primary btn-sm gap-2 rounded-md px-5"
                >
                  {gettext("Send")}
                  <span class="icon-[tabler--send] size-3.5" />
                </button>
              </div>
            </div>
          </.form>
        </div>
      </Layouts.page>
    </Layouts.app>
    """
  end
end
