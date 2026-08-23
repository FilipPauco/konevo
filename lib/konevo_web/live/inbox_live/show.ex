defmodule KonevoWeb.InboxLive.Show do
  use KonevoWeb, :live_view

  alias Konevo.AI
  alias Konevo.Companies.Company
  alias Konevo.Contacts.Contact
  alias Konevo.Deals
  alias Konevo.Deals.Deal
  alias Konevo.Inbox
  alias Konevo.Tasks
  alias Konevo.Uploads
  alias Konevo.Uploads.UploadConfig
  alias Konevo.Uploads.UploadProcessor
  alias KonevoWeb.CompaniesLive.FormComponent, as: CompanyFormComponent
  alias KonevoWeb.ContactsLive.FormComponent, as: ContactFormComponent
  alias KonevoWeb.DealsLive.FormComponent, as: DealFormComponent

  @attachment_accept ~w(.pdf .doc .docx .xls .xlsx .csv .ppt .pptx .jpg .jpeg .png .gif .webp .mp4 .webm .mov .mp3 .wav .ogg)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    config = UploadConfig.get!(:mixed_attachment)

    {:ok,
     socket
     |> assign(:page_title, gettext("Thread"))
     |> assign(:thread_id, id)
     |> assign(:loaded?, false)
     |> assign(:thread, nil)
     |> assign(:emails, [])
     |> assign(:email_attachments, %{})
     |> assign(:thread_attachments, [])
     |> assign(:reply_open, false)
     |> assign(:generating_reply?, false)
     |> assign(:reply_draft_content, "")
     |> assign(:ai_reply_open?, false)
     |> assign(:ai_reply_form, ai_reply_form())
     |> assign(:reply_to, nil)
     |> assign(:reply_form, reply_form())
     |> assign(:reply_attachment_owner_id, Ecto.UUID.generate())
     |> assign(:reply_attachments, [])
     |> assign(:contact, nil)
     |> assign(:company, nil)
     |> assign(:deal, nil)
     |> assign(:task, nil)
     |> assign(:selection_context, nil)
     |> assign(:extracting_tasks?, false)
     |> assign(:task_suggestions, [])
     |> assign(:existing_thread_tasks, [])
     |> assign(:task_extraction_error, nil)
     |> assign(:task_types, [])
     |> assign(:task_options, [])
     |> allow_upload(:reply_attachment,
       accept: @attachment_accept,
       auto_upload: true,
       max_entries: config.max_entries,
       max_file_size: config.max_file_size,
       progress: &handle_reply_attachment_progress/3
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      if connected?(socket) do
        load_thread(socket)
      else
        socket
      end

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new_contact, _params) do
    assign(socket, :contact, contact_from_source(socket))
  end

  defp apply_action(socket, :new_company, _params) do
    assign(socket, :company, company_from_source(socket))
  end

  defp apply_action(socket, :new_task, %{"mode" => "manual"}) do
    socket =
      socket
      |> reset_task_extraction()
      |> load_existing_thread_tasks()

    if socket.assigns.thread do
      assign(socket, :task_suggestions, [manual_task_suggestion(socket)])
    else
      socket
    end
  end

  defp apply_action(socket, :new_task, _params) do
    if selected_text(socket) do
      socket
      |> reset_task_extraction()
      |> load_existing_thread_tasks()
      |> assign(:task_suggestions, [manual_task_suggestion(socket, selected_text(socket))])
    else
      socket
      |> reset_task_extraction()
      |> load_existing_thread_tasks()
      |> start_task_extraction()
    end
  end

  defp apply_action(socket, :new_deal, _params) do
    assign(socket, :deal, deal_from_source(socket))
  end

  defp apply_action(socket, _action, _params) do
    socket
    |> assign(:contact, nil)
    |> assign(:company, nil)
    |> assign(:deal, nil)
    |> assign(:task, nil)
    |> assign(:selection_context, nil)
    |> reset_task_extraction()
  end

  @impl true
  def handle_info({ContactFormComponent, {:saved, contact, :created}}, socket) do
    scope = socket.assigns.current_scope

    case Inbox.update_thread(scope, socket.assigns.thread, %{contact_id: contact.id}) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:success, gettext("Contact created and linked"))
         |> push_patch(to: ~p"/inbox/#{socket.assigns.thread_id}")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:warning, gettext("Contact created, but could not link it to this thread"))
         |> push_patch(to: ~p"/inbox/#{socket.assigns.thread_id}")}
    end
  end

  def handle_info({ContactFormComponent, {:saved, _contact, _action}}, socket) do
    {:noreply, load_thread(socket)}
  end

  def handle_info({CompanyFormComponent, {:saved, _company, :created}}, socket) do
    {:noreply,
     socket
     |> load_thread()
     |> put_flash(:success, gettext("Company created"))}
  end

  def handle_info({CompanyFormComponent, {:saved, _company, _action}}, socket) do
    {:noreply, load_thread(socket)}
  end

  def handle_info({:saved, %Deal{} = deal}, socket) do
    scope = socket.assigns.current_scope

    case Inbox.link_deal(scope, socket.assigns.thread, deal.id) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:success, gettext("Deal created and linked"))
         |> push_patch(to: ~p"/inbox/#{socket.assigns.thread_id}")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:warning, gettext("Deal created, but could not link it to this thread"))
         |> push_patch(to: ~p"/inbox/#{socket.assigns.thread_id}")}
    end
  end

  def handle_info({:reply_draft_chunk, thread_id, chunk}, socket) when is_binary(chunk) do
    if socket.assigns.generating_reply? and
         to_string(thread_id) == to_string(socket.assigns.thread_id) do
      draft = socket.assigns.reply_draft_content <> chunk
      content = AI.format_reply_draft(draft)

      {:noreply,
       socket
       |> assign(:reply_draft_content, draft)
       |> assign(:reply_form, reply_form(%{"body" => content}))
       |> push_event("tiptap:set-content", %{id: "reply-body", content: content})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:reply_draft_chunk, _thread_id, _chunk}, socket), do: {:noreply, socket}

  defp contact_from_source(socket) do
    case selected_text(socket) do
      nil -> contact_from_sender(socket)
      text -> contact_from_selection(socket, text)
    end
  end

  defp contact_from_selection(%{assigns: %{current_scope: scope, thread: thread}} = socket, text) do
    email = extract_email(text)
    name = text |> String.replace(email, "") |> selection_first_line()
    {first_name, last_name} = split_name(name, email)

    %Contact{
      organization_id: scope.org.id,
      user_id: scope.user.id,
      email: email,
      first_name: first_name,
      last_name: last_name,
      phone: extract_phone(text),
      status: contact_status_from_thread(thread),
      notes: selection_note(thread, selected_email(socket), text)
    }
  end

  defp contact_from_sender(%{assigns: %{thread: thread, current_scope: scope}})
       when not is_nil(thread) do
    sender = sender_for_prefill(thread)
    %{email: email, first_name: first_name, last_name: last_name} = parse_sender(sender)

    %Contact{
      organization_id: scope.org.id,
      user_id: scope.user.id,
      email: email,
      first_name: first_name,
      last_name: last_name,
      status: contact_status_from_thread(thread),
      notes: sender_note(thread, sender)
    }
  end

  defp contact_from_sender(%{assigns: %{current_scope: scope}}) do
    %Contact{organization_id: scope.org.id, user_id: scope.user.id}
  end

  defp company_from_source(socket) do
    case selected_text(socket) do
      nil -> company_from_sender(socket)
      text -> company_from_selection(socket, text)
    end
  end

  defp company_from_selection(%{assigns: %{current_scope: scope, thread: thread}} = socket, text) do
    domain = selection_domain(text)

    %Company{
      organization_id: scope.org.id,
      user_id: scope.user.id,
      name: selection_company_name(text, domain),
      website: website_from_domain(domain),
      phone: extract_phone(text),
      notes: selection_note(thread, selected_email(socket), text)
    }
  end

  defp company_from_sender(%{assigns: %{thread: thread, current_scope: scope}})
       when not is_nil(thread) do
    sender = sender_for_prefill(thread)
    %{email: email} = parse_sender(sender)
    domain = email_domain(email)

    %Company{
      organization_id: scope.org.id,
      user_id: scope.user.id,
      name: company_name_from_domain(domain),
      website: website_from_domain(domain),
      notes: sender_note(thread, sender)
    }
  end

  defp company_from_sender(%{assigns: %{current_scope: scope}}) do
    %Company{organization_id: scope.org.id, user_id: scope.user.id}
  end

  defp deal_from_source(socket) do
    case selected_text(socket) do
      nil -> deal_from_thread(socket)
      text -> deal_from_selection(socket, text)
    end
  end

  defp deal_from_selection(%{assigns: %{current_scope: scope, thread: thread}}, text) do
    %Deal{
      organization_id: scope.org.id,
      owner_id: scope.user.id,
      stage_id: first_stage_id(scope),
      currency: "EUR",
      title: selected_title(text, thread && thread.subject),
      source: "email",
      contact_id: thread && thread.contact_id
    }
  end

  defp deal_from_thread(%{assigns: %{current_scope: scope, thread: thread}}) do
    params = if thread, do: extract_deal_params(thread), else: %{}

    %Deal{
      organization_id: scope.org.id,
      owner_id: scope.user.id,
      stage_id: first_stage_id(scope),
      currency: "EUR",
      title: Map.get(params, :title),
      source: Map.get(params, :source),
      contact_id: Map.get(params, :contact_id)
    }
  end

  defp first_stage_id(scope) do
    scope
    |> Deals.list_stages()
    |> List.first()
    |> case do
      nil -> nil
      stage -> stage.id
    end
  end

  defp default_due_date, do: DateTime.utc_now(:second) |> DateTime.add(86_400, :second)

  defp sender_for_prefill(%{emails: emails, participants: participants}) do
    emails
    |> Enum.filter(& &1.is_inbound)
    |> Enum.max_by(& &1.received_at, DateTime, fn -> nil end)
    |> case do
      nil -> List.first(participants) || ""
      email -> email.from
    end
  end

  defp parse_sender(sender) when is_binary(sender) do
    email = extract_email(sender)
    name = extract_sender_name(sender, email)
    {first_name, last_name} = split_name(name, email)

    %{email: email, first_name: first_name, last_name: last_name}
  end

  defp extract_email(sender) do
    case Regex.run(~r/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, sender) do
      [email] -> String.downcase(email)
      _ -> ""
    end
  end

  defp extract_phone(text) do
    case Regex.run(~r/(?:\+?\d[\d\s().-]{7,}\d)/, text) do
      [phone] -> String.trim(phone)
      _ -> nil
    end
  end

  defp extract_sender_name(sender, email) do
    sender
    |> String.replace(email, "")
    |> String.replace(["<", ">", "\""], "")
    |> String.trim()
  end

  defp split_name("", email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.replace([".", "_", "-"], " ")
    |> split_name_from_text()
  end

  defp split_name(name, _email), do: split_name_from_text(name)

  defp split_name_from_text(text) do
    parts = text |> String.split(" ", trim: true) |> Enum.take(2)

    case parts do
      [] -> {"", ""}
      [first] -> {Phoenix.Naming.humanize(first), ""}
      [first, last] -> {Phoenix.Naming.humanize(first), Phoenix.Naming.humanize(last)}
    end
  end

  defp email_domain(""), do: nil

  defp email_domain(email) do
    email
    |> String.split("@", parts: 2)
    |> case do
      [_local, domain] -> domain
      _ -> nil
    end
  end

  defp company_name_from_domain(nil), do: ""

  defp company_name_from_domain(domain) do
    domain
    |> String.replace_prefix("www.", "")
    |> String.split(".")
    |> List.first()
    |> Phoenix.Naming.humanize()
  end

  defp website_from_domain(nil), do: ""
  defp website_from_domain(domain), do: "https://#{domain}"

  defp sender_note(thread, sender) do
    gettext("Created from inbox sender %{sender} in thread \"%{subject}\"",
      sender: sender,
      subject: thread.subject || gettext("(no subject)")
    )
  end

  defp selection_note(thread, email, text) do
    [
      gettext("Created from selected email text in thread \"%{subject}\"",
        subject: (thread && thread.subject) || gettext("(no subject)")
      ),
      email &&
        gettext("Source email: %{subject}", subject: email.subject || gettext("(no subject)")),
      text
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp selection_domain(text) do
    email = extract_email(text)

    cond do
      present_string?(email) ->
        email_domain(email)

      domain = extract_domain(text) ->
        domain

      true ->
        nil
    end
  end

  defp extract_domain(text) do
    case Regex.run(~r/(?:https?:\/\/)?(?:www\.)?([a-z0-9-]+(?:\.[a-z0-9-]+)+)/i, text) do
      [_match, domain] -> String.downcase(domain)
      _ -> nil
    end
  end

  defp selection_company_name(_text, domain) when is_binary(domain) do
    company_name_from_domain(domain)
  end

  defp selection_company_name(text, _domain),
    do: text |> selection_first_line() |> selected_title()

  defp selection_first_line(text) do
    text
    |> to_string()
    |> String.split(~r/\R/, parts: 2)
    |> List.first()
    |> String.trim()
  end

  defp selected_title(text, fallback \\ nil) do
    text
    |> selection_first_line()
    |> present_or(fallback || gettext("(no subject)"))
    |> String.slice(0, 120)
  end

  defp selection_context(text, email_id) do
    text = text |> to_string() |> String.trim() |> String.slice(0, 4_000)

    if text == "" do
      nil
    else
      %{text: text, email_id: normalize_id(email_id)}
    end
  end

  defp selection_action_path(%{assigns: %{thread_id: thread_id}}, "contact"),
    do: ~p"/inbox/#{thread_id}/contact/new"

  defp selection_action_path(%{assigns: %{thread_id: thread_id}}, "company"),
    do: ~p"/inbox/#{thread_id}/company/new"

  defp selection_action_path(%{assigns: %{thread_id: thread_id}}, "task"),
    do: ~p"/inbox/#{thread_id}/task/new"

  defp selection_action_path(%{assigns: %{thread_id: thread_id}}, "deal"),
    do: ~p"/inbox/#{thread_id}/deal/new"

  defp selection_action_path(_socket, _action), do: nil

  defp selected_text(%{assigns: %{selection_context: %{text: text}}}) when text != "", do: text
  defp selected_text(_socket), do: nil

  defp selected_text_active?(%{selection_context: %{text: text}}) when text != "", do: true
  defp selected_text_active?(_assigns), do: false

  defp selected_email(%{assigns: %{emails: emails, selection_context: %{email_id: email_id}}}) do
    Enum.find(emails, &(to_string(&1.id) == to_string(email_id)))
  end

  defp selected_email(_socket), do: nil

  defp selection_source_email_id(socket) do
    case selected_email(socket) do
      nil -> nil
      email -> email.id
    end
  end

  defp normalize_id(nil), do: nil
  defp normalize_id(""), do: nil
  defp normalize_id(id), do: to_string(id)

  defp contact_status_from_thread(%{category: :customer}), do: :customer
  defp contact_status_from_thread(_thread), do: :lead

  defp sender_prefill_available?(%{thread: nil}), do: false

  defp sender_prefill_available?(%{thread: thread}) do
    thread |> sender_for_prefill() |> extract_email() |> present_string?()
  end

  defp source_email_id(%{emails: emails}) do
    emails
    |> Enum.filter(& &1.is_inbound)
    |> Enum.max_by(& &1.received_at, DateTime, fn -> List.first(emails) end)
    |> case do
      nil -> nil
      email -> email.id
    end
  end

  defp extract_task_params(thread) do
    %{
      title: thread.subject || gettext("(no subject)"),
      source_thread_id: thread.id,
      source_email_id: source_email_id(thread),
      contact_id: thread.contact_id,
      deal_id: thread.deal_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp extract_task_params(thread, socket) do
    thread
    |> extract_task_params()
    |> Map.put(:source_email_id, selection_source_email_id(socket) || source_email_id(thread))
  end

  defp reset_task_extraction(socket) do
    socket
    |> assign(:extracting_tasks?, false)
    |> assign(:task_suggestions, [])
    |> assign(:existing_thread_tasks, [])
    |> assign(:task_extraction_error, nil)
  end

  defp load_existing_thread_tasks(%{assigns: %{thread: nil}} = socket), do: socket

  defp load_existing_thread_tasks(socket) do
    case Tasks.list_tasks_for_source_thread(
           socket.assigns.current_scope,
           socket.assigns.thread.id
         ) do
      {:ok, tasks} -> assign(socket, :existing_thread_tasks, tasks)
      {:error, _reason} -> assign(socket, :existing_thread_tasks, [])
    end
  end

  defp start_task_extraction(%{assigns: %{thread: nil}} = socket), do: socket

  defp start_task_extraction(socket) do
    scope = socket.assigns.current_scope
    thread = Inbox.get_thread!(scope, socket.assigns.thread_id)

    socket
    |> assign(:extracting_tasks?, true)
    |> assign(:task_suggestions, [])
    |> assign(:task_extraction_error, nil)
    |> start_async({:task_extraction, thread.id}, fn ->
      AI.extract_tasks_from_thread(scope, thread, %{
        "instructions" => "Extract current, actionable follow-up tasks for this CRM thread."
      })
    end)
  end

  defp build_task_suggestions(socket, tasks, source_email_id) do
    base_attrs = extract_task_params(socket.assigns.thread)

    tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, index} ->
      attrs = suggestion_task_attrs(task, base_attrs, source_email_id)
      filing = suggested_task_filing(socket.assigns.current_scope, attrs)

      attrs
      |> Map.merge(%{
        id: Integer.to_string(index),
        selected: not duplicate_task_suggestion?(socket.assigns.existing_thread_tasks, attrs),
        confidence: Map.get(task, "confidence"),
        duplicate?: duplicate_task_suggestion?(socket.assigns.existing_thread_tasks, attrs),
        filing: filing
      })
    end)
  end

  defp suggestion_task_attrs(task, base_attrs, source_email_id) do
    base_attrs
    |> Map.merge(%{
      title: Map.get(task, "title") || "",
      description: Map.get(task, "description") || "",
      due_date: task_due_date_input(Map.get(task, "due_date")),
      priority: Map.get(task, "priority") || "normal",
      source_email_id: source_email_id || Map.get(base_attrs, :source_email_id)
    })
  end

  defp suggested_task_filing(scope, attrs) do
    case Tasks.suggested_parent_epic(scope, attrs) do
      {:ok, nil} -> %{title: gettext("No parent"), icon: "icon-[tabler--ban]"}
      {:ok, filing} -> filing
      {:error, _reason} -> %{title: gettext("Other"), icon: "icon-[tabler--inbox]"}
    end
  end

  defp duplicate_task_suggestion?(existing_tasks, attrs) do
    title = attrs |> Map.get(:title, "") |> normalize_title()
    Enum.any?(existing_tasks, &(normalize_title(&1.title) == title))
  end

  defp normalize_title(title) do
    title
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end

  defp task_due_date_input(nil), do: default_due_date_input()
  defp task_due_date_input(""), do: default_due_date_input()

  defp task_due_date_input(value) when is_binary(value) do
    with {:error, _reason} <- DateTime.from_iso8601(value),
         {:error, _reason} <- Date.from_iso8601(value),
         {:error, _reason} <- NaiveDateTime.from_iso8601(value) do
      default_due_date_input()
    else
      {:ok, due_date, _offset} -> datetime_input(DateTime.shift_zone!(due_date, "Etc/UTC"))
      {:ok, %Date{} = date} -> datetime_input(DateTime.new!(date, ~T[17:00:00], "Etc/UTC"))
      {:ok, %NaiveDateTime{} = naive} -> datetime_input(DateTime.from_naive!(naive, "Etc/UTC"))
    end
  end

  defp task_due_date_input(_value), do: default_due_date_input()

  defp default_due_date_input, do: datetime_input(default_due_date())

  defp datetime_input(date_time) do
    Calendar.strftime(date_time, "%Y-%m-%dT%H:%M")
  end

  defp manual_task_suggestion(socket, text \\ "") do
    base_attrs = extract_task_params(socket.assigns.thread, socket)

    attrs =
      Map.merge(base_attrs, %{
        title: selected_task_title(text),
        description: String.trim(text || ""),
        due_date: default_due_date_input(),
        priority: "normal"
      })

    attrs
    |> Map.merge(%{
      id: Ecto.UUID.generate(),
      selected: true,
      confidence: nil,
      duplicate?: false,
      filing: suggested_task_filing(socket.assigns.current_scope, attrs)
    })
  end

  defp create_selected_task_suggestions(socket, suggestions) do
    suggestions
    |> Map.values()
    |> Enum.filter(&(Map.get(&1, "selected") == "true"))
    |> Enum.map(&create_task_suggestion(socket, &1))
    |> split_created_tasks()
  end

  defp create_task_suggestion(socket, params) do
    attrs =
      socket.assigns.thread
      |> extract_task_params()
      |> Map.merge(%{
        title: Map.get(params, "title"),
        description: Map.get(params, "description"),
        due_date: Map.get(params, "due_date"),
        priority: Map.get(params, "priority", "normal"),
        source_email_id:
          Map.get(params, "source_email_id") || selection_source_email_id(socket) ||
            source_email_id(socket.assigns.thread)
      })

    Tasks.create_task(socket.assigns.current_scope, attrs)
  end

  defp selected_task_title(text) do
    text
    |> selected_title(gettext("Follow up from selected email text"))
    |> String.slice(0, 90)
  end

  defp split_created_tasks(results) do
    {ok, errors} =
      Enum.split_with(results, fn
        {:ok, _task} -> true
        _ -> false
      end)

    if errors == [] do
      {:ok, Enum.map(ok, fn {:ok, task} -> task end)}
    else
      {:error, errors}
    end
  end

  defp extract_deal_params(thread) do
    %{
      title: thread.subject || gettext("(no subject)"),
      source: "email",
      contact_id: thread.contact_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp load_thread(socket) do
    scope = socket.assigns.current_scope
    thread = Inbox.get_thread!(scope, socket.assigns.thread_id)

    thread =
      if is_nil(thread.read_at) do
        case Inbox.mark_read(scope, thread) do
          {:ok, _} -> Inbox.get_thread!(scope, thread.id)
          _ -> thread
        end
      else
        thread
      end

    {email_attachments, thread_attachments} = load_attachments(scope, thread)

    socket
    |> assign(:page_title, thread.subject || gettext("Thread"))
    |> assign(:loaded?, true)
    |> assign(:thread, thread)
    |> assign(:emails, thread.emails)
    |> assign(:email_attachments, email_attachments)
    |> assign(:thread_attachments, thread_attachments)
  end

  defp load_attachments(scope, thread) do
    email_attachments =
      thread.emails
      |> Map.new(fn email ->
        attachments =
          case Uploads.list_email_attachments(scope, email.id) do
            {:ok, files} -> files
            _ -> []
          end

        {email.id, attachments}
      end)

    thread_attachments =
      case Uploads.list_thread_attachments(scope, thread.id) do
        {:ok, files} -> files
        _ -> []
      end

    {email_attachments, thread_attachments}
  end

  @impl true
  def handle_event("resolve", _, socket) do
    scope = socket.assigns.current_scope

    case Inbox.resolve_thread(scope, socket.assigns.thread) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:success, gettext("Marked resolved"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not mark resolved"))}
    end
  end

  def handle_event("archive", _, socket) do
    scope = socket.assigns.current_scope

    case Inbox.archive_thread(scope, socket.assigns.thread) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Thread archived"))
         |> push_navigate(to: ~p"/inbox")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not archive thread"))}
    end
  end

  def handle_event("unarchive", _, socket) do
    scope = socket.assigns.current_scope

    case Inbox.unarchive_thread(scope, socket.assigns.thread) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:success, gettext("Moved to inbox"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not move to inbox"))}
    end
  end

  def handle_event("toggle_favorite", _, socket) do
    scope = socket.assigns.current_scope

    message =
      if socket.assigns.thread.is_favorite,
        do: gettext("Removed from favorites"),
        else: gettext("Added to favorites")

    case Inbox.toggle_favorite(scope, socket.assigns.thread) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:success, message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update favorite"))}
    end
  end

  def handle_event("move_to_bin", _, socket) do
    scope = socket.assigns.current_scope

    case Inbox.move_to_bin(scope, socket.assigns.thread) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Moved to bin"))
         |> push_navigate(to: ~p"/inbox?view=bin")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not move to bin"))}
    end
  end

  def handle_event("restore", _, socket) do
    scope = socket.assigns.current_scope

    case Inbox.restore_thread(scope, socket.assigns.thread) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:success, gettext("Thread restored"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not restore thread"))}
    end
  end

  def handle_event("reopen", _, socket) do
    scope = socket.assigns.current_scope

    case Inbox.update_thread(scope, socket.assigns.thread, %{is_unresolved: true}) do
      {:ok, _thread} ->
        {:noreply,
         socket
         |> load_thread()
         |> put_flash(:success, gettext("Thread reopened"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not reopen thread"))}
    end
  end

  def handle_event("open_reply", _, socket) do
    {:noreply,
     socket
     |> assign(:reply_open, true)
     |> assign(:reply_to, reply_target(socket.assigns.thread))
     |> push_event("inbox:scroll-to-reply", %{})}
  end

  def handle_event("close_reply", _, socket) do
    {:noreply, socket |> discard_reply_attachments() |> reset_reply()}
  end

  def handle_event("open_ai_reply_draft", _, socket) do
    {:noreply, assign(socket, :ai_reply_open?, true)}
  end

  def handle_event("close_ai_reply_draft", _, socket) do
    {:noreply, assign(socket, ai_reply_open?: false, ai_reply_form: ai_reply_form())}
  end

  def handle_event("generate_reply_draft", %{"ai_reply" => params}, socket) do
    instruction = params |> Map.get("instruction", "") |> String.trim()

    if instruction == "" do
      {:noreply,
       socket
       |> assign(:ai_reply_open?, true)
       |> assign(
         :ai_reply_form,
         ai_reply_form(params, errors: [instruction: {"can't be blank", []}])
       )}
    else
      generate_reply_draft(socket, params)
    end
  end

  def handle_event(
        "email_selection_action",
        %{"action" => action, "text" => text} = params,
        socket
      ) do
    scope = socket.assigns.current_scope
    thread = Inbox.get_thread!(scope, socket.assigns.thread_id)

    socket =
      socket
      |> assign(:thread, thread)
      |> assign(:selection_context, selection_context(text, Map.get(params, "email_id")))

    case selection_action_path(socket, action) do
      nil -> {:noreply, socket}
      path -> {:noreply, push_patch(socket, to: path)}
    end
  end

  def handle_event("retry_task_extraction", _, socket) do
    {:noreply, start_task_extraction(socket)}
  end

  def handle_event("create_extracted_tasks", %{"task_review" => params}, socket) do
    suggestions = Map.get(params, "suggestions", %{})

    case create_selected_task_suggestions(socket, suggestions) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, gettext("Select at least one task"))}

      {:ok, tasks} ->
        {:noreply,
         socket
         |> put_flash(
           :success,
           ngettext("Task created", "%{count} tasks created", length(tasks), count: length(tasks))
         )
         |> load_thread()
         |> push_patch(to: ~p"/inbox/#{socket.assigns.thread_id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create selected tasks"))}
    end
  end

  def handle_event("validate_reply", %{"reply" => params}, socket) do
    {:noreply, assign(socket, :reply_form, reply_form(socket, params))}
  end

  def handle_event("validate_reply", params, socket) do
    {:noreply, assign(socket, :reply_form, reply_form(socket, params))}
  end

  def handle_event("cancel_reply_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :reply_attachment, ref)}
  end

  def handle_event("delete_reply_attachment", %{"id" => id}, socket) do
    case Uploads.delete_email_draft_attachment(
           socket.assigns.current_scope,
           id,
           socket.assigns.reply_attachment_owner_id
         ) do
      {:ok, _file} ->
        {:noreply, assign(socket, :reply_attachments, reject_reply_attachment(socket, id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove attachment"))}
    end
  end

  def handle_event("send_reply", %{"reply" => params}, socket) do
    send_reply_from_params(socket, params)
  end

  def handle_event("send_reply", params, socket) do
    send_reply_from_params(socket, params)
  end

  defp generate_reply_draft(socket, params) do
    scope = socket.assigns.current_scope
    thread = Inbox.get_thread!(scope, socket.assigns.thread_id)
    live_view = self()
    instruction = Map.get(params, "instruction", "")
    tone = Map.get(params, "tone", "professional")

    {:noreply,
     socket
     |> assign(:reply_open, true)
     |> assign(:generating_reply?, true)
     |> assign(:reply_draft_content, "")
     |> assign(:ai_reply_open?, false)
     |> assign(:ai_reply_form, ai_reply_form())
     |> assign(:reply_to, reply_target(thread))
     |> assign(:reply_form, reply_form(%{"body" => ""}))
     |> push_event("tiptap:set-content", %{id: "reply-body", content: ""})
     |> push_event("inbox:scroll-to-reply", %{})
     |> start_async({:reply_draft, thread.id}, fn ->
       AI.generate_reply_draft_stream(
         scope,
         thread,
         fn chunk -> send(live_view, {:reply_draft_chunk, thread.id, chunk}) end,
         %{instruction: instruction, tone: tone}
       )
     end)}
  end

  @impl true
  def handle_async({:reply_draft, _thread_id}, {:ok, {:ok, %{content: content}}}, socket) do
    {:noreply,
     socket
     |> assign(:generating_reply?, false)
     |> assign(:reply_draft_content, "")
     |> assign(:reply_open, true)
     |> assign(:reply_to, reply_target(socket.assigns.thread))
     |> assign(:reply_form, reply_form(%{"body" => content}))
     |> push_event("tiptap:set-content", %{id: "reply-body", content: content})
     |> push_event("inbox:scroll-to-reply", %{})}
  end

  def handle_async({:reply_draft, _thread_id}, _result, socket) do
    {:noreply,
     socket
     |> assign(:generating_reply?, false)
     |> assign(:reply_draft_content, "")
     |> put_flash(:error, gettext("Could not generate a reply draft"))}
  end

  def handle_async({:task_extraction, _thread_id}, {:ok, {:ok, result}}, socket) do
    suggestions =
      build_task_suggestions(
        socket,
        result.tasks,
        result.source_email && result.source_email.id
      )

    {:noreply,
     socket
     |> assign(:extracting_tasks?, false)
     |> assign(:task_extraction_error, nil)
     |> assign(:task_suggestions, suggestions)}
  end

  def handle_async({:task_extraction, _thread_id}, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:extracting_tasks?, false)
     |> assign(:task_extraction_error, task_extraction_error_message(reason))}
  end

  def handle_async({:task_extraction, _thread_id}, _result, socket) do
    {:noreply,
     socket
     |> assign(:extracting_tasks?, false)
     |> assign(:task_extraction_error, gettext("Could not extract tasks from this thread"))}
  end

  defp task_extraction_error_message(reason) do
    if provider_rate_limited?(reason) do
      gettext("AI provider rate limit reached. Wait a minute, then try again.")
    else
      gettext("Could not extract tasks from this thread")
    end
  end

  defp provider_rate_limited?(reason) do
    reason
    |> inspect()
    |> String.downcase()
    |> then(
      &(String.contains?(&1, "resource_exhausted") or String.contains?(&1, "quota exceeded"))
    )
  end

  defp send_reply_from_params(socket, params) do
    if Map.get(params, "schedule_preset") do
      schedule_reply(socket, params)
    else
      send_reply_now(socket, Map.get(params, "body", ""))
    end
  end

  defp schedule_reply(socket, %{"body" => body} = params) do
    body = String.trim(body)

    if body == "" do
      {:noreply, put_flash(socket, :error, gettext("Reply cannot be empty"))}
    else
      do_schedule_reply(socket, body, params)
    end
  end

  defp do_schedule_reply(socket, body, params) do
    scope = socket.assigns.current_scope
    thread = socket.assigns.thread
    scheduled_at = scheduled_at_from_params(params)

    case Inbox.schedule_reply(scope, thread, body, scheduled_at,
           attachment_owner_id: socket.assigns.reply_attachment_owner_id,
           attachment_ids: Enum.map(socket.assigns.reply_attachments, & &1.id)
         ) do
      {:ok, _scheduled_email} ->
        {:noreply,
         socket
         |> reset_reply()
         |> put_flash(:success, gettext("Reply scheduled"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, schedule_error(reason))}
    end
  end

  defp send_reply_now(socket, body) do
    case String.trim(body) do
      "" ->
        {:noreply, put_flash(socket, :error, gettext("Reply cannot be empty"))}

      trimmed ->
        scope = socket.assigns.current_scope
        thread = socket.assigns.thread

        case Inbox.send_reply(scope, thread, trimmed,
               attachment_owner_id: socket.assigns.reply_attachment_owner_id,
               attachment_ids: Enum.map(socket.assigns.reply_attachments, & &1.id)
             ) do
          {:ok, _email} ->
            {:noreply,
             socket
             |> load_thread()
             |> reset_reply()
             |> put_flash(:success, gettext("Reply sent"))}

          {:error, :no_integration} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("No Gmail account connected. Please connect Gmail in Settings")
             )}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, gettext("Failed to send reply: %{r}", r: inspect(reason)))}
        end
    end
  end

  defp format_datetime(nil), do: ""

  defp format_datetime(%DateTime{} = dt) do
    Konevo.DateTime.format_local(dt, "%b %d, %Y at %H:%M")
  end

  defp task_review_form, do: to_form(%{}, as: :task_review)

  defp task_priority_options do
    [
      {"low", gettext("Low")},
      {"normal", gettext("Normal")},
      {"high", gettext("High")},
      {"urgent", gettext("Urgent")}
    ]
  end

  defp confidence_label(nil), do: gettext("Manual")

  defp confidence_label(confidence),
    do: gettext("%{score}% confidence", score: round(confidence * 100))

  defp task_status_label(:open), do: gettext("Open")
  defp task_status_label(:in_progress), do: gettext("In progress")
  defp task_status_label(:done), do: gettext("Done")
  defp task_status_label(:cancelled), do: gettext("Cancelled")
  defp task_status_label(status), do: Phoenix.Naming.humanize(status)

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

  defp schedule_error(:missing_recipient), do: gettext("Could not find a reply recipient")
  defp schedule_error(:missing_body), do: gettext("Write a reply before scheduling")

  defp schedule_error(:no_integration),
    do: gettext("No Gmail account connected. Please connect Gmail in Settings")

  defp schedule_error(:invalid_scheduled_at), do: gettext("Choose a valid schedule time")

  defp schedule_error(:scheduled_at_in_past),
    do: gettext("Choose a schedule time at least one minute from now")

  defp schedule_error(:scheduled_at_too_soon),
    do: gettext("Choose a schedule time at least one minute from now")

  defp schedule_error(%Ecto.Changeset{}), do: gettext("Could not schedule reply")
  defp schedule_error(_reason), do: gettext("Could not schedule reply")

  defp reply_target(thread) do
    thread.emails
    |> Enum.filter(& &1.is_inbound)
    |> Enum.max_by(& &1.received_at, DateTime, fn -> nil end)
    |> case do
      nil -> List.first(thread.participants) || ""
      email -> email.from
    end
  end

  defp reply_form(attrs \\ %{}) do
    defaults = %{"body" => "", "scheduled_at" => ""}
    to_form(Map.merge(defaults, stringify_keys(attrs)), as: :reply)
  end

  defp reply_form(socket, attrs) do
    socket.assigns.reply_form
    |> reply_form_attrs()
    |> Map.merge(stringify_keys(attrs))
    |> reply_form()
  end

  defp reply_form_attrs(%Phoenix.HTML.Form{params: params}) when is_map(params) do
    Map.take(params, ["body", "scheduled_at"])
  end

  defp reply_form_attrs(_form), do: %{}

  defp ai_reply_form(attrs \\ %{}, opts \\ []) do
    defaults = %{"instruction" => "", "tone" => "professional"}

    attrs
    |> stringify_keys()
    |> then(&Map.merge(defaults, &1))
    |> to_form(as: :ai_reply, errors: Keyword.get(opts, :errors, []))
  end

  defp reset_reply(socket) do
    assign(socket,
      reply_open: false,
      reply_to: nil,
      reply_draft_content: "",
      ai_reply_open?: false,
      ai_reply_form: ai_reply_form(),
      reply_form: reply_form(),
      reply_attachments: [],
      reply_attachment_owner_id: Ecto.UUID.generate()
    )
  end

  defp discard_reply_attachments(%{assigns: %{reply_attachments: []}} = socket), do: socket

  defp discard_reply_attachments(socket) do
    case delete_draft_attachments(
           socket.assigns.current_scope,
           socket.assigns.reply_attachment_owner_id,
           socket.assigns.reply_attachments
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

  defp reject_reply_attachment(socket, id) do
    Enum.reject(socket.assigns.reply_attachments, &(to_string(&1.id) == to_string(id)))
  end

  defp handle_reply_attachment_progress(:reply_attachment, entry, socket) do
    if entry.done? do
      save_reply_attachment(socket, entry)
    else
      {:noreply, socket}
    end
  end

  defp save_reply_attachment(socket, entry) do
    scope = socket.assigns.current_scope

    result =
      consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
        {:ok,
         UploadProcessor.process(
           temp_path,
           :mixed_attachment,
           to_string(scope.org.id),
           socket.assigns.reply_attachment_owner_id,
           "email_draft",
           entry.client_name
         )}
      end)

    case result do
      {:ok, file} ->
        {:noreply,
         socket
         |> update(:reply_attachments, &[file | &1])
         |> put_flash(:success, gettext("File attached"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not attach file"))}
    end
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes < 1_024 -> "#{bytes} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1_024, 1)} KB"
      bytes < 1_073_741_824 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
    end
  end

  defp category_badge_class(:lead), do: "badge-warning"
  defp category_badge_class(:customer), do: "badge-success"
  defp category_badge_class(:support), do: "badge-info"
  defp category_badge_class(:billing), do: "badge-error"
  defp category_badge_class(:internal), do: "badge-ghost"
  defp category_badge_class(:noise), do: "badge-ghost opacity-50"
  defp category_badge_class(nil), do: "badge-ghost"

  defp category_label(:lead), do: gettext("Lead")
  defp category_label(:customer), do: gettext("Customer")
  defp category_label(:support), do: gettext("Support")
  defp category_label(:billing), do: gettext("Billing")
  defp category_label(:internal), do: gettext("Internal")
  defp category_label(:noise), do: gettext("Uncategorised")
  defp category_label(nil), do: gettext("Uncategorised")

  defp initials(from) do
    from
    |> String.split(["@", " "], trim: true)
    |> hd()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  defp sender_color(from) do
    colors = [
      "bg-primary/20 text-primary",
      "bg-success/20 text-success",
      "bg-warning/20 text-warning",
      "bg-info/20 text-info",
      "bg-secondary/20 text-secondary"
    ]

    idx = :erlang.phash2(from, length(colors))
    Enum.at(colors, idx)
  end

  defp email_card_class(email) do
    [
      "overflow-hidden rounded-lg border bg-base-100 shadow-sm shadow-base-content/5 transition-shadow hover:shadow-md",
      if(email.is_inbound, do: "border-base-content/10", else: "border-info/25")
    ]
  end

  defp email_header_class(email) do
    [
      "flex items-start gap-3 border-b px-5 py-4",
      if(email.is_inbound,
        do: "border-base-content/8 bg-base-200/25",
        else: "border-info/10 bg-info/5"
      )
    ]
  end

  defp email_body_class(email) do
    if email.is_inbound, do: "bg-base-200/25", else: "bg-info/[0.025]"
  end

  defp email_html_source(email) do
    html_body = Map.get(email, :html_body)
    body = Map.get(email, :body)

    cond do
      present_string?(html_body) ->
        html_body

      present_string?(body) and KonevoWeb.HTMLSanitizer.email_html_like?(body) ->
        body

      true ->
        nil
    end
  end

  defp email_srcdoc(html, attachments, inline_image_cids) do
    body =
      html
      |> KonevoWeb.HTMLSanitizer.email_html_string()
      |> replace_inline_image_sources(attachments, inline_image_cids)

    """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <base target="_blank">
      <style>
        :root {
          color-scheme: light;
          --email-background: #fffaf3;
          --email-foreground: #332c25;
          --email-link: #2563eb;
        }
        * { box-sizing: border-box; }
        html, body { margin: 0; background: var(--email-background); color: var(--email-foreground); }
        body { min-height: 100%; padding: 16px 18px; font: 14px/1.5 Arial, Helvetica, sans-serif; overflow-wrap: anywhere; }
        a { color: var(--email-link); text-decoration: underline; }
        img { max-width: 100%; height: auto; }
        .email-image-placeholder {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 72px;
          height: 48px;
          margin: 4px 0;
          border: 1px solid color-mix(in srgb, CanvasText 15%, transparent);
          border-radius: 8px;
          background: color-mix(in srgb, CanvasText 5%, transparent);
          color: color-mix(in srgb, CanvasText 55%, transparent);
          vertical-align: middle;
        }
        .email-image-placeholder svg {
          width: 22px;
          height: 22px;
          fill: none;
          stroke: currentColor;
          stroke-width: 1.8;
          stroke-linecap: round;
          stroke-linejoin: round;
        }
        table { max-width: 100%; }
        blockquote { border-left: 3px solid color-mix(in srgb, CanvasText 20%, transparent); margin: 16px 0; padding-left: 12px; color: color-mix(in srgb, CanvasText 75%, transparent); }
        pre { white-space: pre-wrap; }
      </style>
    </head>
    <body>
      #{body}
    </body>
    </html>
    """
  end

  defp replace_inline_image_sources(html, attachments, inline_image_cids)
       when is_list(attachments) and is_map(inline_image_cids) do
    attachment_urls =
      Map.new(attachments, fn file ->
        {file.original_filename, ~p"/uploads/#{file.context}/#{file.id}"}
      end)

    Enum.reduce(inline_image_cids, html, fn {content_id, filename}, result ->
      case Map.get(attachment_urls, filename) do
        nil -> result
        url -> replace_inline_image_source(result, normalize_inline_image_cid(content_id), url)
      end
    end)
  end

  defp replace_inline_image_sources(html, _attachments, _inline_image_cids), do: html

  defp replace_inline_image_source(html, content_id, url) do
    pattern = Regex.compile!("(src\\s*=\\s*[\\\"'])cid:#{Regex.escape(content_id)}([\\\"'])", "i")
    Regex.replace(pattern, html, "\\1#{url}\\2")
  end

  defp normalize_inline_image_cid(content_id) do
    content_id
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp present_or(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp present_or(_value, fallback), do: fallback

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page>
        <:actions>
          <.link
            navigate={~p"/inbox"}
            class="btn btn-sm btn-ghost gap-1.5"
          >
            <span class="icon-[tabler--arrow-left] size-4" />
            {gettext("Back to inbox")}
          </.link>
        </:actions>

        <%= if @loaded? do %>
          <div class="flex flex-col gap-5 lg:flex-row lg:items-start">
            <%!-- Email thread column --%>
            <div class="min-w-0 flex-1">
              <%!-- Thread header --%>
              <div class="mb-4 rounded-lg border border-base-content/10 bg-base-100 p-5">
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="min-w-0">
                    <h2 class="text-lg font-semibold leading-tight">
                      {@thread.subject || gettext("(no subject)")}
                    </h2>
                    <div class="mt-1.5 flex flex-wrap items-center gap-2">
                      <span class={[
                        "badge !h-6 !rounded-md px-2.5 text-xs font-semibold",
                        category_badge_class(@thread.category)
                      ]}>
                        {category_label(@thread.category)}
                      </span>
                      <span
                        :if={@thread.is_unresolved}
                        class="badge badge-warning !h-6 !rounded-md gap-1.5 px-2.5 text-xs font-semibold"
                      >
                        <span class="icon-[tabler--alert-circle] size-3.5" />
                        {gettext("Unresolved")}
                      </span>
                      <span
                        :if={!@thread.is_unresolved}
                        class="badge badge-primary !h-6 !rounded-md gap-1.5 px-2.5 text-xs font-semibold"
                      >
                        <span class="icon-[tabler--circle-check] size-3.5" />
                        {gettext("Resolved")}
                      </span>
                    </div>
                  </div>

                  <%!-- Thread actions --%>
                  <div class="ml-auto flex shrink-0 flex-wrap items-center justify-end gap-2">
                    <button
                      type="button"
                      id="thread-header-reply"
                      phx-click="open_reply"
                      aria-label={gettext("Reply")}
                      title={gettext("Reply")}
                      class="btn btn-sm btn-primary gap-1.5"
                    >
                      <.icon name="icon-[tabler--corner-down-left]" class="size-4" />
                      {gettext("Reply")}
                    </button>
                    <div id="thread-more-menu" phx-hook="RowMenu" class="relative">
                      <button
                        type="button"
                        data-toggle
                        aria-haspopup="menu"
                        aria-expanded="false"
                        aria-label={gettext("More thread actions")}
                        title={gettext("More thread actions")}
                        class="inline-flex size-9 items-center justify-center text-base-content/50 transition-colors hover:text-base-content focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                      >
                        <.icon name="icon-[tabler--dots-vertical]" class="size-5" />
                      </button>
                      <div
                        data-panel
                        class="row-menu-closed z-50 w-48 space-y-0.5 overflow-hidden rounded-lg border border-base-content/10 bg-base-100 p-1.5 shadow-xl shadow-base-content/10"
                        role="menu"
                      >
                        <button
                          type="button"
                          id="thread-favorite-toggle"
                          phx-click="toggle_favorite"
                          class={[
                            "flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium transition-colors hover:bg-warning/10",
                            if(@thread.is_favorite,
                              do: "text-warning",
                              else: "text-base-content/70 hover:text-warning"
                            )
                          ]}
                          role="menuitem"
                        >
                          <.icon
                            name={
                              if(@thread.is_favorite,
                                do: "icon-[tabler--star-filled]",
                                else: "icon-[tabler--star]"
                              )
                            }
                            class="size-4"
                          />
                          {if @thread.is_favorite,
                            do: gettext("Remove favorite"),
                            else: gettext("Set favorite")}
                        </button>
                        <div class="my-1 h-px bg-base-content/10" />
                        <button
                          :if={@thread.is_unresolved}
                          type="button"
                          phx-click="resolve"
                          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-success transition-colors hover:bg-success/10"
                          role="menuitem"
                        >
                          <.icon name="icon-[tabler--circle-check]" class="size-4" />
                          {gettext("Mark resolved")}
                        </button>
                        <button
                          :if={!@thread.is_unresolved}
                          type="button"
                          phx-click="reopen"
                          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-base-200 hover:text-base-content"
                          role="menuitem"
                        >
                          <.icon name="icon-[tabler--refresh]" class="size-4" />
                          {gettext("Reopen")}
                        </button>
                        <div class="my-1 h-px bg-base-content/10" />
                        <button
                          :if={@thread.is_archived}
                          type="button"
                          phx-click="unarchive"
                          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-base-200 hover:text-base-content"
                          role="menuitem"
                        >
                          <.icon name="icon-[tabler--inbox]" class="size-4" />
                          {gettext("Move to inbox")}
                        </button>
                        <button
                          :if={!@thread.is_archived}
                          type="button"
                          phx-click="archive"
                          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-base-200 hover:text-base-content"
                          role="menuitem"
                        >
                          <.icon name="icon-[tabler--archive]" class="size-4" />
                          {gettext("Archive")}
                        </button>
                        <button
                          :if={is_nil(@thread.trashed_at)}
                          type="button"
                          phx-click="move_to_bin"
                          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-error transition-colors hover:bg-error/10"
                          role="menuitem"
                        >
                          <.icon name="icon-[tabler--trash]" class="size-4" />
                          {gettext("Move to bin")}
                        </button>
                        <button
                          :if={!is_nil(@thread.trashed_at)}
                          type="button"
                          phx-click="restore"
                          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-base-200 hover:text-base-content"
                          role="menuitem"
                        >
                          <.icon name="icon-[tabler--restore]" class="size-4" />
                          {gettext("Restore")}
                        </button>
                      </div>
                    </div>
                  </div>
                </div>

                <%!-- Revenue at risk --%>
                <div
                  :if={@thread.revenue_at_risk && Decimal.compare(@thread.revenue_at_risk, 0) == :gt}
                  class="mt-3 flex items-center gap-2 rounded-lg bg-error/8 px-3 py-2"
                >
                  <span class="icon-[tabler--alert-triangle] size-4 text-error" />
                  <span class="text-sm font-medium text-error">
                    {gettext("Revenue at risk: €%{amount}", amount: @thread.revenue_at_risk)}
                  </span>
                </div>
              </div>

              <%!-- Emails --%>
              <div id="email-selection-root" phx-hook="EmailSelectionActions" class="relative">
                <div
                  id="email-selection-toolbar"
                  class="hidden fixed z-50 items-center gap-1 rounded-lg border border-base-content/15 bg-base-100 p-1.5 shadow-xl shadow-base-content/15"
                  data-selection-toolbar
                >
                  <button
                    type="button"
                    class="btn btn-xs btn-ghost gap-1"
                    data-selection-action="contact"
                    title={gettext("Create contact")}
                  >
                    <.icon name="icon-[tabler--user-plus]" class="size-3.5" />
                    {gettext("Contact")}
                  </button>
                  <button
                    type="button"
                    class="btn btn-xs btn-ghost gap-1"
                    data-selection-action="company"
                    title={gettext("Create company")}
                  >
                    <.icon name="icon-[tabler--building-plus]" class="size-3.5" />
                    {gettext("Company")}
                  </button>
                  <span
                    id="email-selection-actions-divider"
                    aria-hidden="true"
                    class="mx-0.5 h-5 w-px bg-base-content/20"
                  />
                  <button
                    type="button"
                    class="btn btn-xs btn-primary gap-1"
                    data-selection-action="task"
                    title={gettext("Create task")}
                  >
                    <.icon name="icon-[tabler--checkbox]" class="size-3.5" />
                    {gettext("Task")}
                  </button>
                  <button
                    type="button"
                    class="btn btn-xs btn-primary gap-1"
                    data-selection-action="deal"
                    title={gettext("Create deal")}
                  >
                    <.icon name="icon-[tabler--briefcase]" class="size-3.5" />
                    {gettext("Deal")}
                  </button>
                </div>

                <div class="flex flex-col gap-3">
                  <div
                    :if={@emails == []}
                    class="rounded-lg border border-base-content/10 bg-base-100 px-6 py-12 text-center"
                  >
                    <span class="icon-[tabler--mail-off] mx-auto mb-3 block size-10 text-base-content/20" />
                    <p class="text-sm text-base-content/40">
                      {gettext("No emails in this thread yet.")}
                    </p>
                  </div>

                  <div
                    :for={email <- @emails}
                    id={"email-#{email.id}"}
                    class={email_card_class(email)}
                  >
                    <%!-- Email header --%>
                    <div class={email_header_class(email)}>
                      <div class={[
                        "flex size-9 shrink-0 items-center justify-center rounded-full text-sm font-bold",
                        sender_color(email.from)
                      ]}>
                        {initials(email.from)}
                      </div>
                      <div class="min-w-0 flex-1">
                        <div class="flex items-baseline justify-between gap-2">
                          <span class="text-sm font-semibold truncate">{email.from}</span>
                          <span class="shrink-0 text-xs font-medium text-base-content/60">
                            {format_datetime(email.received_at)}
                          </span>
                        </div>
                        <p class="mt-0.5 text-xs text-base-content/50">
                          {gettext("To:")} {Enum.join(email.to, ", ")}
                        </p>
                        <p :if={email.cc != []} class="text-xs text-base-content/40">
                          {gettext("CC:")} {Enum.join(email.cc, ", ")}
                        </p>
                      </div>
                    </div>

                    <%!-- Email body --%>
                    <div class={["px-5 py-4", email_body_class(email)]}>
                      <% html_source = email_html_source(email) %>
                      <%= if html_source do %>
                        <iframe
                          id={"email-body-#{email.id}"}
                          title={gettext("Email body")}
                          srcdoc={
                            email_srcdoc(
                              html_source,
                              Map.get(@email_attachments, email.id, []),
                              email.inline_image_cids
                            )
                          }
                          sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox"
                          referrerpolicy="no-referrer"
                          data-email-selectable-iframe
                          data-email-id={email.id}
                          class="h-[620px] w-full rounded-md border border-base-content/10 bg-base-100 shadow-inner shadow-base-content/5"
                        />
                      <% else %>
                        <div
                          id={"email-body-plain-#{email.id}"}
                          data-email-selectable
                          data-email-id={email.id}
                          class="rounded-md border border-base-content/10 bg-base-200/35 px-4 py-3 text-sm leading-relaxed text-base-content/80 shadow-inner shadow-base-content/5"
                        >
                          {KonevoWeb.HTMLSanitizer.email_html(email.body)}
                        </div>
                      <% end %>
                    </div>

                    <div
                      :if={Map.get(@email_attachments, email.id, []) != []}
                      class="border-t border-base-content/8 px-5 py-3"
                    >
                      <p class="mb-2 text-xs font-semibold uppercase tracking-wider text-base-content/40">
                        {gettext("Attachments")}
                      </p>
                      <div class="flex flex-wrap gap-2">
                        <.link
                          :for={file <- Map.get(@email_attachments, email.id, [])}
                          href={~p"/uploads/#{file.context}/#{file.id}"}
                          class="inline-flex max-w-full items-center gap-1.5 rounded-md border border-base-content/10 bg-base-200/50 px-2.5 py-1.5 text-xs font-medium text-base-content/70 transition-colors hover:border-primary/30 hover:text-primary"
                        >
                          <span class="icon-[tabler--paperclip] size-3.5 shrink-0" />
                          <span class="truncate">{file.original_filename}</span>
                        </.link>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Reply composer --%>
              <%= if @reply_open do %>
                <div
                  id="reply-composer"
                  class="mt-3 overflow-hidden rounded-lg border border-base-content/10 bg-base-100 shadow-sm shadow-base-content/5"
                >
                  <div
                    style="background-color: color-mix(in oklch, var(--color-primary) 10%, var(--color-base-100)); border-bottom: 1px solid color-mix(in oklch, var(--color-primary) 25%, transparent)"
                    class="flex items-center justify-between px-5 py-3"
                  >
                    <div class="flex items-center gap-2 text-sm">
                      <span class="icon-[tabler--corner-down-left] size-4 text-base-content/40" />
                      <span class="text-base-content/60">{gettext("Replying to")}</span>
                      <span class="max-w-xs truncate font-medium text-base-content/60">
                        {@reply_to}
                      </span>
                    </div>
                    <button
                      type="button"
                      phx-click="close_reply"
                      aria-label={gettext("Close reply composer")}
                      title={gettext("Close reply composer")}
                      class="topbar-action btn btn-ghost btn-sm btn-square"
                    >
                      <span class="icon-[tabler--x] size-4" />
                    </button>
                  </div>

                  <.form
                    :if={@ai_reply_open?}
                    for={@ai_reply_form}
                    id="ai-reply-guidance-form"
                    phx-submit="generate_reply_draft"
                    class="border-b border-primary/15 bg-primary/[0.035] px-4 py-4 sm:px-5"
                  >
                    <div class="flex items-start justify-between gap-4">
                      <div>
                        <p class="flex items-center gap-2 text-sm font-semibold text-base-content">
                          <.icon name="icon-[tabler--sparkles]" class="size-4 text-primary" />
                          {gettext("Draft with AI")}
                        </p>
                        <p class="mt-1 text-xs leading-relaxed text-base-content/55">
                          {gettext(
                            "Describe the outcome in your own words. You'll review the email before sending."
                          )}
                        </p>
                      </div>
                      <button
                        type="button"
                        phx-click="close_ai_reply_draft"
                        class="btn btn-ghost btn-xs btn-square"
                        aria-label={gettext("Close AI draft guidance")}
                      >
                        <.icon name="icon-[tabler--x]" class="size-4" />
                      </button>
                    </div>

                    <.input
                      field={@ai_reply_form[:instruction]}
                      type="textarea"
                      label={gettext("What should this reply say?")}
                      placeholder={
                        gettext("e.g. Decline politely and say I will be available from Monday.")
                      }
                      class="mt-3 min-h-24 w-full resize-y rounded-lg border border-base-content/15 bg-base-100 px-3 py-2 text-sm leading-relaxed shadow-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/15"
                    />

                    <div class="mt-3 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                      <.input
                        field={@ai_reply_form[:tone]}
                        type="select"
                        label={gettext("Tone")}
                        options={[
                          {gettext("Professional"), "professional"},
                          {gettext("Warm"), "warm"},
                          {gettext("Concise"), "concise"}
                        ]}
                        class="select select-sm w-full border-base-content/15 bg-base-100 sm:w-44"
                      />
                      <button
                        id="generate-guided-reply-draft"
                        type="submit"
                        class="btn btn-primary btn-sm gap-1.5"
                      >
                        <.icon name="icon-[tabler--sparkles]" class="size-4" />
                        {gettext("Generate draft")}
                      </button>
                    </div>
                  </.form>

                  <.form
                    for={@reply_form}
                    id="reply-form"
                    phx-change="validate_reply"
                    phx-submit="send_reply"
                    phx-drop-target={@uploads.reply_attachment.ref}
                    data-unsaved-form
                    class="flex max-h-[28rem] flex-col overflow-hidden bg-base-100"
                  >
                    <div
                      :if={@generating_reply?}
                      id="reply-draft-loading"
                      role="status"
                      aria-live="polite"
                      class="mx-4 mt-4 rounded-md border border-primary/20 bg-primary/5 px-3 py-2.5 text-sm text-base-content/75"
                    >
                      <.icon name="icon-[tabler--sparkles]" class="size-4 animate-spin text-primary" />
                      <span class="font-medium">{gettext("Drafting reply…")}</span>
                      <span class="text-xs text-base-content/55">
                        {gettext("Review it before sending.")}
                      </span>
                    </div>

                    <div
                      :if={@generating_reply? and @reply_draft_content != ""}
                      id="reply-draft-stream-preview"
                      class="mx-4 mt-3 max-h-36 overflow-y-auto whitespace-pre-wrap rounded-md border border-primary/15 bg-base-100 px-3 py-2 text-sm leading-relaxed text-base-content/80"
                    >
                      {@reply_draft_content}
                    </div>

                    <div class="px-4 pt-4">
                      <.rich_text_input
                        id="reply-body"
                        field={@reply_form[:body]}
                        placeholder={gettext("Write your reply…")}
                        class="tiptap-compact inbox-reply-editor !rounded-none !border-0 !shadow-none bg-base-100"
                      />
                    </div>

                    <div
                      :if={@reply_attachments != [] or @uploads.reply_attachment.entries != []}
                      id="reply-attachments"
                      class="mx-4 mb-3 max-h-36 space-y-1 overflow-y-auto rounded-md border border-base-content/10 bg-base-200/35 px-2 py-2"
                    >
                      <div
                        :for={entry <- @uploads.reply_attachment.entries}
                        id={"reply-upload-#{entry.ref}"}
                        class="flex items-center gap-2 rounded-md border border-base-content/10 bg-base-100 px-2.5 py-1.5 text-xs"
                      >
                        <span class="icon-[tabler--file-upload] size-4 shrink-0 text-primary" />
                        <span class="min-w-0 flex-1 truncate">{entry.client_name}</span>
                        <span class="w-10 text-right tabular-nums text-base-content/45">
                          {entry.progress}%
                        </span>
                        <button
                          type="button"
                          phx-click="cancel_reply_attachment"
                          phx-value-ref={entry.ref}
                          class="btn btn-ghost btn-xs btn-square"
                          aria-label={gettext("Cancel upload")}
                        >
                          <span class="icon-[tabler--x] size-3.5" />
                        </button>
                      </div>

                      <div
                        :for={file <- @reply_attachments}
                        id={"reply-attachment-#{file.id}"}
                        class="flex items-center gap-2 rounded-md border border-base-content/10 bg-base-100 px-2.5 py-1.5 text-xs"
                      >
                        <span class="icon-[tabler--paperclip] size-4 shrink-0 text-base-content/40" />
                        <span class="min-w-0 flex-1 truncate font-medium">
                          {file.original_filename}
                        </span>
                        <span class="shrink-0 text-base-content/40">
                          {format_bytes(file.byte_size)}
                        </span>
                        <button
                          type="button"
                          phx-click="delete_reply_attachment"
                          phx-value-id={file.id}
                          class="btn btn-ghost btn-xs btn-square"
                          aria-label={gettext("Remove attachment")}
                        >
                          <span class="icon-[tabler--x] size-3.5" />
                        </button>
                      </div>
                    </div>

                    <div class="flex items-center justify-between border-t border-base-content/8 bg-base-200/50 px-5 py-3">
                      <.live_file_input upload={@uploads.reply_attachment} class="sr-only" />
                      <div class="flex items-center gap-2 text-base-content/40 transition-opacity phx-submit-loading:pointer-events-none phx-submit-loading:opacity-45">
                        <span
                          class="tooltip"
                          data-tip={
                            if(@generating_reply?,
                              do: gettext("Drafting reply…"),
                              else: gettext("Generate reply draft")
                            )
                          }
                        >
                          <button
                            id="generate-reply-draft"
                            type="button"
                            phx-click="open_ai_reply_draft"
                            disabled={@generating_reply?}
                            class="btn btn-xs btn-primary gap-1.5 disabled:cursor-wait"
                          >
                            <.icon
                              name={
                                if(@generating_reply?,
                                  do: "icon-[tabler--loader-2]",
                                  else: "icon-[tabler--sparkles]"
                                )
                              }
                              class={["size-4", @generating_reply? && "animate-spin"]}
                            />
                            <span class="hidden sm:inline">
                              {if(@generating_reply?,
                                do: gettext("Drafting…"),
                                else: gettext("Draft with AI")
                              )}
                            </span>
                          </button>
                        </span>
                        <div aria-hidden="true" class="h-5 w-px bg-base-content/15" />
                        <span class="tooltip" data-tip={gettext("Attach files")}>
                          <label for={@uploads.reply_attachment.ref} class="btn btn-xs btn-ghost">
                            <span class="icon-[tabler--paperclip] size-4" />
                          </label>
                        </span>
                        <span class="tooltip" data-tip={gettext("Emoji")}>
                          <button
                            type="button"
                            class="btn btn-xs btn-ghost"
                            data-tiptap-command
                            data-tiptap-target="reply-body"
                            data-action="emoji"
                          >
                            <span class="icon-[tabler--mood-smile] size-4" />
                          </button>
                        </span>
                      </div>
                      <div class="flex items-center gap-2">
                        <button type="button" phx-click="close_reply" class="btn btn-sm btn-ghost">
                          {gettext("Cancel")}
                        </button>
                        <div
                          aria-hidden="true"
                          class="h-6 w-px bg-base-content/15"
                        />
                        <div
                          id="reply-schedule-dropdown"
                          class="relative"
                          phx-hook="ScheduleDropdown"
                          data-schedule-dropdown
                        >
                          <button
                            type="button"
                            id="reply-schedule-menu"
                            data-toggle
                            class="btn btn-primary btn-sm btn-square rounded-md"
                            title={gettext("Schedule reply")}
                          >
                            <span class="icon-[tabler--clock] size-4" />
                          </button>
                          <div
                            data-panel
                            class="absolute bottom-full right-0 z-[60] mb-2 hidden w-80 rounded-lg border border-base-content/10 bg-base-100 p-3 shadow-xl"
                          >
                            <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
                              {gettext("Schedule reply")}
                            </p>
                            <button
                              type="button"
                              data-schedule-preset-target={@reply_form[:scheduled_at].id}
                              data-schedule-preset-value={schedule_preset_input_value(:tomorrow)}
                              class="mb-1 flex h-9 w-full items-center gap-2.5 rounded-md border border-base-content/10 px-3 text-sm font-medium text-base-content/70 transition-colors hover:border-primary/30 hover:bg-base-200 hover:text-base-content"
                            >
                              <span class="icon-[tabler--sun] size-4 shrink-0 text-warning" />
                              {gettext("Tomorrow morning")}
                            </button>
                            <button
                              type="button"
                              data-schedule-preset-target={@reply_form[:scheduled_at].id}
                              data-schedule-preset-value={schedule_preset_input_value(:monday)}
                              class="flex h-9 w-full items-center gap-2.5 rounded-md border border-base-content/10 px-3 text-sm font-medium text-base-content/70 transition-colors hover:border-primary/30 hover:bg-base-200 hover:text-base-content"
                            >
                              <span class="icon-[tabler--calendar-week] size-4 shrink-0 text-primary" />
                              {gettext("Monday morning")}
                            </button>
                            <div class="mt-2 border-t border-base-content/10 pt-2">
                              <label
                                for={@reply_form[:scheduled_at].id}
                                class="mb-1 block text-xs font-medium text-base-content/50"
                              >
                                {gettext("Custom time")}
                              </label>
                              <input
                                type="datetime-local"
                                name={@reply_form[:scheduled_at].name}
                                id={@reply_form[:scheduled_at].id}
                                value={@reply_form[:scheduled_at].value}
                                class="input input-sm input-bordered w-full"
                              />
                              <button
                                type="submit"
                                name="reply[schedule_preset]"
                                value="custom"
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
                          disabled={@generating_reply?}
                          phx-disable-with={gettext("Sending…")}
                          class="btn btn-sm btn-primary gap-1.5 disabled:cursor-wait"
                        >
                          <span class="icon-[tabler--send] size-4" />
                          {gettext("Send reply")}
                        </button>
                      </div>
                    </div>
                  </.form>
                </div>
              <% else %>
                <button
                  type="button"
                  id="thread-bottom-reply"
                  phx-click="open_reply"
                  class="inbox-reply-trigger mt-3 flex w-full items-center gap-3 rounded-lg border border-dashed border-primary/30 bg-base-100 px-5 py-4 text-left shadow-sm shadow-base-content/5 transition-all hover:border-primary/45 hover:bg-primary/5"
                >
                  <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                    <span class="icon-[tabler--corner-down-left] size-4" />
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block text-sm font-semibold text-base-content">
                      {gettext("Reply to this thread…")}
                    </span>
                    <span class="mt-0.5 flex min-w-0 items-center gap-1.5 text-xs text-base-content/55">
                      <span class="shrink-0">{gettext("Replying to")}</span>
                      <span class="truncate font-medium text-base-content/75">
                        {reply_target(@thread)}
                      </span>
                    </span>
                  </span>
                </button>
              <% end %>
            </div>

            <%!-- Sidebar --%>
            <div class="w-full shrink-0 space-y-4 lg:w-72">
              <%!-- Contact card --%>
              <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
                <p class="mb-3 text-xs font-semibold uppercase tracking-wider text-base-content">
                  {gettext("Contact")}
                </p>
                <%= if @thread.contact do %>
                  <div class="flex items-center gap-3">
                    <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary/15 text-sm font-bold text-primary">
                      {String.first(@thread.contact.first_name || "?")}
                    </div>
                    <div class="min-w-0">
                      <p class="truncate text-sm font-semibold">
                        {[@thread.contact.first_name, @thread.contact.last_name]
                        |> Enum.filter(& &1)
                        |> Enum.join(" ")}
                      </p>
                      <p class="truncate text-xs text-base-content/50">{@thread.contact.email}</p>
                    </div>
                  </div>
                  <.link
                    navigate={~p"/contacts/#{@thread.contact}"}
                    class="btn btn-sm btn-primary mt-3 w-full gap-1.5"
                  >
                    <.icon name="icon-[tabler--external-link]" class="size-4" />
                    {gettext("View contact")}
                  </.link>
                <% else %>
                  <div class="flex flex-col items-center py-4 text-center">
                    <span class="icon-[tabler--user-question] mb-2 size-8 text-base-content/20" />
                    <p class="text-xs text-base-content">{gettext("No contact linked")}</p>
                    <div
                      :if={sender_prefill_available?(assigns)}
                      class="mt-4 grid w-full grid-cols-1 gap-2"
                    >
                      <.link
                        patch={~p"/inbox/#{@thread_id}/contact/new"}
                        id="create-contact-from-sender"
                        class="btn btn-sm btn-primary gap-1.5"
                      >
                        <span class="icon-[tabler--user-plus] size-4" />
                        {gettext("Create contact")}
                      </.link>
                      <.link
                        patch={~p"/inbox/#{@thread_id}/company/new"}
                        id="create-company-from-sender"
                        class="btn btn-sm btn-ghost w-full gap-1.5"
                      >
                        <span class="icon-[tabler--building-plus] size-4" />
                        {gettext("Create company")}
                      </.link>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Deal card --%>
              <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
                <p class="mb-3 text-xs font-semibold uppercase tracking-wider text-base-content">
                  {gettext("Deal")}
                </p>
                <%= if @thread.deal do %>
                  <div class="space-y-1.5">
                    <p class="text-sm font-semibold">{@thread.deal.title}</p>
                    <p :if={@thread.deal.value} class="text-xs text-base-content/50">
                      {gettext("Value: €%{v}", v: @thread.deal.value)}
                    </p>
                  </div>
                <% else %>
                  <div class="flex flex-col items-center py-4 text-center">
                    <span class="icon-[tabler--briefcase-off] mb-2 size-8 text-base-content/20" />
                    <p class="text-xs text-base-content">{gettext("No deal linked")}</p>
                  </div>
                <% end %>
              </div>

              <%!-- Extract card --%>
              <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
                <p class="mb-3 text-xs font-semibold uppercase tracking-wider text-base-content">
                  {gettext("Extract")}
                </p>
                <div class="grid grid-cols-1 gap-2">
                  <.link
                    patch={~p"/inbox/#{@thread_id}/task/new"}
                    id="extract-tasks-from-thread"
                    class="btn btn-sm btn-primary w-full gap-1.5"
                  >
                    <.icon name="icon-[tabler--sparkles]" class="size-4" />
                    {gettext("Extract tasks")}
                  </.link>
                  <.link
                    patch={~p"/inbox/#{@thread_id}/task/new?mode=manual"}
                    id="create-task-from-thread"
                    class="btn btn-sm btn-ghost w-full gap-1.5"
                  >
                    <.icon name="icon-[tabler--checkbox]" class="size-4" />
                    {gettext("Create task")}
                  </.link>
                  <.link
                    patch={~p"/inbox/#{@thread_id}/deal/new"}
                    id="create-deal-from-thread"
                    class="btn btn-sm btn-ghost w-full gap-1.5"
                  >
                    <.icon name="icon-[tabler--briefcase]" class="size-4" />
                    {gettext("Create deal")}
                  </.link>
                </div>
              </div>

              <%!-- Attachments card --%>
              <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
                <p class="mb-3 text-xs font-semibold uppercase tracking-wider text-base-content">
                  {gettext("Attachments")}
                </p>
                <%= if @thread_attachments == [] do %>
                  <div class="flex flex-col items-center py-4 text-center">
                    <span class="icon-[tabler--files-off] mb-2 size-8 text-base-content/20" />
                    <p class="text-xs text-base-content">{gettext("No attachments")}</p>
                  </div>
                <% else %>
                  <div class="space-y-2">
                    <.link
                      :for={file <- @thread_attachments}
                      href={~p"/uploads/#{file.context}/#{file.id}"}
                      class="flex min-w-0 items-center gap-2 rounded-lg border border-base-content/10 bg-base-200/40 px-2.5 py-2 text-xs font-medium text-base-content/70 transition-colors hover:border-primary/30 hover:text-primary"
                    >
                      <span class="icon-[tabler--paperclip] size-3.5 shrink-0" />
                      <span class="truncate">{file.original_filename}</span>
                    </.link>
                  </div>
                <% end %>
              </div>

              <%!-- Thread meta --%>
              <div class="rounded-lg border border-base-content/10 bg-base-100 p-4">
                <p class="mb-3 text-xs font-semibold uppercase tracking-wider text-base-content">
                  {gettext("Details")}
                </p>
                <dl class="space-y-2 text-xs">
                  <div class="flex justify-between">
                    <dt class="text-base-content/50">{gettext("Emails")}</dt>
                    <dd class="font-medium">{length(@emails)}</dd>
                  </div>
                  <div :if={@thread.last_inbound_at} class="flex justify-between">
                    <dt class="text-base-content/50">{gettext("Last inbound")}</dt>
                    <dd class="font-medium">{format_datetime(@thread.last_inbound_at)}</dd>
                  </div>
                  <div :if={@thread.last_activity_at} class="flex justify-between">
                    <dt class="text-base-content/50">{gettext("Last activity")}</dt>
                    <dd class="font-medium">{format_datetime(@thread.last_activity_at)}</dd>
                  </div>
                  <div :if={@thread.participants != []} class="flex flex-col gap-1.5">
                    <dt class="text-base-content/50">{gettext("Participants")}</dt>
                    <dd>
                      <div class="flex flex-wrap gap-1">
                        <span
                          :for={p <- @thread.participants}
                          class="rounded bg-base-200 px-1.5 py-0.5 text-xs"
                        >
                          {p}
                        </span>
                      </div>
                    </dd>
                  </div>
                </dl>
              </div>
            </div>
          </div>
        <% else %>
          <div class="rounded-lg border border-base-content/10 bg-base-100 px-6 py-16 text-center">
            <span class="loading loading-spinner loading-md text-primary" />
            <p class="mt-3 text-sm text-base-content/50">{gettext("Loading thread...")}</p>
          </div>
        <% end %>
      </Layouts.page>

      <.modal
        :if={@live_action == :new_contact and @contact}
        id="inbox-contact-modal"
        show
        on_cancel={JS.patch(~p"/inbox/#{@thread_id}")}
      >
        <.live_component
          module={ContactFormComponent}
          id="inbox-contact-form-new"
          action={:new}
          title={gettext("Create contact from sender")}
          contact={@contact}
          current_scope={@current_scope}
          patch={~p"/inbox/#{@thread_id}"}
        />
      </.modal>

      <.modal
        :if={@live_action == :new_company and @company}
        id="inbox-company-modal"
        show
        on_cancel={JS.patch(~p"/inbox/#{@thread_id}")}
      >
        <.live_component
          module={CompanyFormComponent}
          id="inbox-company-form-new"
          action={:new}
          title={gettext("Create company from sender")}
          company={@company}
          current_scope={@current_scope}
          patch={~p"/inbox/#{@thread_id}"}
        />
      </.modal>

      <.modal
        :if={@live_action == :new_task}
        id="inbox-task-modal"
        show
        on_cancel={JS.patch(~p"/inbox/#{@thread_id}")}
      >
        <div id="inbox-task-extraction-review">
          <div class="mb-6 flex items-center gap-3">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10">
              <.icon name="icon-[tabler--sparkles]" class="size-5 text-primary" />
            </div>
            <div>
              <h2 class="text-base font-semibold text-base-content">
                {if selected_text_active?(assigns),
                  do: gettext("Create task from selection"),
                  else: gettext("Extract tasks")}
              </h2>
              <p class="text-xs text-base-content/50">
                {if selected_text_active?(assigns),
                  do: gettext("Review the selected text before creating the task."),
                  else: gettext("Review suggested tasks before creating them.")}
              </p>
            </div>
          </div>

          <div
            :if={@existing_thread_tasks != []}
            id="existing-thread-tasks"
            class="mb-4 rounded-lg border border-base-content/10 bg-base-200/40 p-3"
          >
            <p class="mb-2 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/45">
              <.icon name="icon-[tabler--checks]" class="size-3.5" />
              {gettext("Already created")}
            </p>
            <div class="space-y-1.5">
              <div
                :for={task <- @existing_thread_tasks}
                class="flex items-center gap-2 rounded-md bg-base-100 px-2.5 py-2 text-sm"
              >
                <.icon name="icon-[tabler--checkbox]" class="size-4 text-base-content/35" />
                <span class="min-w-0 flex-1 truncate font-medium">{task.title}</span>
                <span class="text-xs text-base-content/45">{task_status_label(task.status)}</span>
              </div>
            </div>
          </div>

          <div
            :if={@extracting_tasks?}
            id="task-extraction-loading"
            role="status"
            aria-live="polite"
            class="flex items-center gap-3 rounded-lg border border-primary/20 bg-primary/5 px-4 py-4 text-sm text-base-content/75"
          >
            <.icon name="icon-[tabler--loader-2]" class="size-5 animate-spin text-primary" />
            <div>
              <p class="font-semibold text-base-content">{gettext("Reading the thread")}</p>
              <p class="text-xs text-base-content/55">
                {gettext("Long conversations are deduplicated before suggestions appear.")}
              </p>
            </div>
          </div>

          <div
            :if={@task_extraction_error}
            id="task-extraction-error"
            class="rounded-lg border border-error/20 bg-error/10 p-4"
          >
            <p class="mb-3 text-sm font-medium text-error">{@task_extraction_error}</p>
            <button
              id="retry-task-extraction"
              type="button"
              phx-click="retry_task_extraction"
              class="btn btn-sm btn-outline border-error/30 text-error hover:bg-error/10"
            >
              <.icon name="icon-[tabler--refresh]" class="size-4" />
              {gettext("Try again")}
            </button>
          </div>

          <%= if !@extracting_tasks? and is_nil(@task_extraction_error) do %>
            <.form
              for={task_review_form()}
              id="task-review-form"
              phx-submit="create_extracted_tasks"
            >
              <div
                :if={@task_suggestions == []}
                id="task-extraction-empty"
                class="rounded-lg border border-base-content/10 bg-base-200/35 px-5 py-8 text-center"
              >
                <.icon
                  name="icon-[tabler--square-x]"
                  class="mx-auto mb-3 size-9 text-base-content/25"
                />
                <p class="text-sm font-semibold text-base-content">
                  {gettext("No clear tasks found")}
                </p>
                <p class="mt-1 text-xs text-base-content/50">
                  {gettext("Add one manually if this thread still needs follow-up.")}
                </p>
              </div>

              <div id="task-suggestions" class="max-h-[28rem] space-y-3 overflow-y-auto pr-1">
                <div
                  :for={suggestion <- @task_suggestions}
                  id={"task-suggestion-#{suggestion.id}"}
                  class={[
                    "rounded-lg border bg-base-100 p-3 shadow-sm shadow-base-content/5",
                    if(suggestion.duplicate?,
                      do: "border-warning/30",
                      else: "border-base-content/10"
                    )
                  ]}
                >
                  <input
                    type="hidden"
                    name={"task_review[suggestions][#{suggestion.id}][selected]"}
                    value="false"
                  />
                  <input
                    type="hidden"
                    name={"task_review[suggestions][#{suggestion.id}][source_email_id]"}
                    value={suggestion.source_email_id}
                  />
                  <div class="mb-3 flex items-start gap-3">
                    <input
                      type="checkbox"
                      name={"task_review[suggestions][#{suggestion.id}][selected]"}
                      value="true"
                      checked={suggestion.selected}
                      class="checkbox checkbox-sm mt-1"
                    />
                    <div class="min-w-0 flex-1">
                      <div class="mb-2 flex flex-wrap items-center gap-2">
                        <span
                          :if={suggestion.duplicate?}
                          class="inline-flex items-center gap-1 rounded-md border border-warning/25 bg-warning/10 px-2 py-0.5 text-xs font-semibold text-warning"
                        >
                          <.icon name="icon-[tabler--copy]" class="size-3" />
                          {gettext("Possible duplicate")}
                        </span>
                        <span class="inline-flex items-center gap-1 rounded-md border border-primary/15 bg-primary/5 px-2 py-0.5 text-xs font-medium text-base-content/60">
                          <.icon name={suggestion.filing.icon} class="size-3" />
                          {suggestion.filing.title}
                        </span>
                        <span class="text-xs text-base-content/40">
                          {confidence_label(suggestion.confidence)}
                        </span>
                      </div>

                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <label class="fieldset sm:col-span-2">
                          <span class="label">{gettext("Title")}</span>
                          <input
                            type="text"
                            name={"task_review[suggestions][#{suggestion.id}][title]"}
                            value={suggestion.title}
                            class="input w-full"
                            required
                          />
                        </label>
                        <label class="fieldset">
                          <span class="label">{gettext("Due date")}</span>
                          <input
                            type="datetime-local"
                            name={"task_review[suggestions][#{suggestion.id}][due_date]"}
                            value={suggestion.due_date}
                            class="input w-full"
                            required
                          />
                        </label>
                        <label class="fieldset">
                          <span class="label">{gettext("Priority")}</span>
                          <select
                            name={"task_review[suggestions][#{suggestion.id}][priority]"}
                            class="select w-full"
                          >
                            <option
                              :for={{value, label} <- task_priority_options()}
                              value={value}
                              selected={suggestion.priority == value}
                            >
                              {label}
                            </option>
                          </select>
                        </label>
                        <label class="fieldset sm:col-span-2">
                          <span class="label">{gettext("Description")}</span>
                          <textarea
                            name={"task_review[suggestions][#{suggestion.id}][description]"}
                            rows="2"
                            class="textarea w-full"
                          >{suggestion.description}</textarea>
                        </label>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div class="mt-5 flex justify-end gap-2">
                <button
                  type="button"
                  class="btn btn-sm btn-ghost"
                  phx-click={JS.patch(~p"/inbox/#{@thread_id}")}
                >
                  {gettext("Cancel")}
                </button>
                <button
                  id="create-selected-tasks"
                  type="submit"
                  class="btn btn-sm btn-primary gap-1.5"
                >
                  <.icon name="icon-[tabler--checks]" class="size-4" />
                  {gettext("Create selected")}
                </button>
              </div>
            </.form>
          <% end %>
        </div>
      </.modal>

      <.modal
        :if={@live_action == :new_deal and @deal}
        id="inbox-deal-modal"
        show
        on_cancel={JS.patch(~p"/inbox/#{@thread_id}")}
      >
        <.live_component
          module={DealFormComponent}
          id="inbox-deal-form-new"
          action={:new}
          title={gettext("Create deal from thread")}
          deal={@deal}
          current_scope={@current_scope}
          patch={~p"/inbox/#{@thread_id}"}
        />
      </.modal>
    </Layouts.app>
    """
  end
end
