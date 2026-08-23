## Communication
- Be extremely concise. Sacrifice grammar for concision.
- Code only. No explanation unless explicitly asked.
- No preamble, no "Here is the code:", no closing summary.

---

## Planning
- Before any multi-step task, write a short plan first.
- At the end of each plan, list unresolved questions (if any) — one line each, extremely concise.
- For large tasks (5+ steps), ask whether to start a fresh session.

---

## Stack

- **Elixir / OTP** — functional core, supervised processes
- **Phoenix** — HTTP, routing, plugs, contexts
- **LiveView** — real-time UI (`*_live.ex`)
- **Ecto + PostgreSQL** — data layer, migrations, queries
- **Tailwind CSS** — utility classes for layout, spacing, customization

---

## Core Principles

- Prefer simplicity over abstraction.
- Always return `{:ok, result}` or `{:error, reason}`. Never silently ignore errors.
- Use pattern matching instead of conditionals where possible.
- Pipe operator `|>` for data transformations.
- Prefer `with` for multi-step operations.
- Functions under 20-25 lines.
- Measure before optimizing.

---

## Iron Laws — Never Violate

These are non-negotiable. Stop and explain if any change would break them.

### LiveView

- **No database queries in disconnected `mount/3`.** Check `connected?(socket)` first; defer data loading to connected mount or `handle_info`.
- **Use streams for lists.** Any list that could exceed ~100 items must use `stream/3` + `stream_insert/3`, never `assign` a growing list.
- **Subscribe to PubSub only when connected.** Always guard `Phoenix.PubSub.subscribe/2` behind `if connected?(socket)`.
- **Never use `assign_new` for values refreshed every mount.** `assign_new` is for values that should not be recomputed on reconnect. Data that must be fresh goes in connected mount.
- **Authorize inside every `handle_event`.** Never assume socket assigns are a sufficient auth check — re-verify the actor's permission for each event.
- **For translations use `Gettext`** All displayed text should be wrapped inside gettext functions - mostly default function, but some need pluralization.

### Ecto / PostgreSQL

- **Never use `:float` for money.** Use `:decimal` (or store as integer cents).
- **Always pin values with `^` in queries.** Unpinned variables in `from` macros are a compile-time or runtime bug.
- **Separate queries for `has_many`; `JOIN` for `belongs_to`.** Avoid accidental N+1 by preloading the right way.
- **No raw string interpolation into queries.** Use parameterized queries; never `fragment("... #{user_input}")`.
- **Migrations are append-only in production.** Add columns nullable first, backfill, then add constraints.

### Security

- **Never call `String.to_atom/1` with user input.** Atoms are not garbage-collected; use `String.to_existing_atom/1` or a safe mapping.
- **Authorize in every `handle_event` and controller action.** Role checks in the router or mount are not enough.
- **Never pass user-controlled data to `raw/1` in HEEx.** Use `{:safe, ...}` only for known-safe strings.
- **CSRF is on by default.** Do not disable it for convenience.

### OTP

- **No process without a supervision reason.** Unsupervised `spawn` for anything stateful is forbidden; use `GenServer` under a `Supervisor`.
- **Supervise all long-lived processes** — GenServers, PubSub subscribers, task supervisors.
- **Use `Task.Supervisor` for async jobs.** Never fire bare `Task.async` for work that must not be lost.
- **Never block the BEAM scheduler** with long synchronous work — offload to a Task or GenServer.

### Elixir

- **Declare `@external_resource` for compile-time files.** Any file read at compile time must be declared so recompilation triggers correctly.
- **Wrap third-party libraries behind project modules.** Don't scatter `MyHttp.get` calls; wrap external deps so they are swappable and testable.
- **Jobs (Oban workers) must be idempotent.** Running the same job twice must be safe. Use unique constraints or guard clauses.
- **Oban args use string keys.** JSON serialization loses atom keys; always access args with string keys like `args["user_id"]`.

---

## Architecture Conventions

### Phoenix Contexts

- One context per business domain (e.g., `Konevo.Accounts`, `Konevo.Inbox`, `Konevo.Contacts`, `Konevo.Deals`, `Konevo.Automation`, `Konevo.Messaging`, `Konevo.AI`, `Konevo.Compliance`).
- Contexts own their schemas. Cross-context access goes through public context functions — never reach into another context's schema directly.
- Keep controllers and LiveViews thin. Business logic lives in the context.

### LiveView Structure

```
lib/konevo_web/live/
  feature_live/
    index.ex            # list view
    show.ex             # detail view
    form_component.ex
```

- Extract repeated UI into function components (`~H` in a `_components.ex` module).
- Use `Phoenix.Component` for stateless pieces; `LiveComponent` only when local state is genuinely needed.
- Keep assigns minimal. Prefer derived data in `render/1` over storing computed values in the socket.

### Components

- Before creating any UI, follow this priority order:
  1. **Existing component** — grep `lib/konevo_web/components/` first; extend via `attr`/`slot` before creating new ones.
  2. **FlyonUI component** — check [flyonui.com/docs](https://flyonui.com/docs) for a matching component; use its classes directly.
  3. **Custom Tailwind component** — only when nothing existing or FlyonUI covers the use case; write your own Tailwind-based markup.
- Always declare types on `attr`/`slot` — no untyped props.
- Shared/global components → `lib/konevo_web/components/core_components.ex`. Feature-scoped → `lib/konevo_web/live/feature/_components.ex`.
- Stateless UI → `Phoenix.Component`. Local state only → `LiveComponent`.

### Ecto Schemas & Queries

- One schema per table. Embed schemas sparingly (only truly owned sub-data).
- Keep query functions in the context module, not in the schema.
- Use `Repo.one!` / `Repo.get!` for records that must exist; handle `nil` explicitly elsewhere.
- Always `Repo.transact` for multi-step writes.
- **No `Repo` calls outside of context modules.** Controllers and LiveViews call context functions, never `Repo` directly.
- **No raw SQL unless Ecto can't do it.** Use `Ecto.Query` first; reach for `fragment/1` or `Repo.query/2` only as a last resort.
- **Preload only what is needed.** Don't blanket-preload every association; fetch what the current view requires.

### Styling

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/konevo_web";

- **Always use and maintain this import syntax** in the app.css file.
- **Never** use `@apply` when writing raw css.
- Extract repeated class combos into a HEEx function component.
- Use `Phoenix.Component.assigns_to_attributes` for class merging in generic components.

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles.
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions).
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look.
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions.

---

## Workflow

### Before Writing Code

1. Check `mix.exs` dependencies before adding a library — it may already be there.
2. For schema changes: write the migration, update the schema, update the context, then the UI.
3. For LiveView features: define the socket assigns upfront, then implement `mount`, then `handle_event` / `handle_info`.
4. For UI: check existing components first, then write Tailwind-based components, then custom CSS — in that order.

### After Writing Code

After every code change:

```bash
mix format
mix compile --warnings-as-errors
```

Fix every warning before moving on.

---

## Testing

- Test every context function. Use `ExUnit` + `ExMachina` factories.
- LiveView tests with `Phoenix.LiveViewTest` — test `mount`, events, and re-renders.
- Use `Mox` for external service dependencies; define behaviours and mock them.
- Avoid testing implementation details (private functions, internal assigns not visible in HTML).
- Test the sad path: authorization failures, invalid changesets, missing records.

### Factory pattern

```elixir
# test/support/factories.ex
defmodule Konevo.Factory do
  use ExMachina.Ecto, repo: Konevo.Repo

  def user_factory do
    %Konevo.Accounts.User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: "Test User"
    }
  end
end
```

---

## Common Patterns

### N+1 Prevention

Preload associations at the context boundary, not in the template:

```elixir
# Good
def list_posts do
  Repo.all(from p in Post, preload: [:user, :tags])
end

# Bad — causes N+1 in the template
def list_posts do
  Repo.all(Post)
end
```

### PubSub + LiveView

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(Konevo.PubSub, "topic:#{socket.assigns.current_user.id}")
  end
  {:ok, assign(socket, ...)}
end

def handle_info({:new_event, payload}, socket) do
  {:noreply, stream_insert(socket, :items, payload)}
end
```

### Changeset errors in LiveView

Always pass the changeset to the template and let `Phoenix.HTML.Form` surface errors — don't manually build error messages in the LiveView.

### Authorization

```elixir
def handle_event("delete", %{"id" => id}, socket) do
  post = Konevo.Posts.get_post!(id)

  case Konevo.Posts.delete_post(socket.assigns.current_user, post) do
    {:ok, _} -> {:noreply, stream_delete(socket, :posts, post)}
    {:error, :unauthorized} -> {:noreply, put_flash(socket, :error, "Not allowed")}
  end
end
```

---