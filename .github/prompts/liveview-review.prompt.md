---
description: "LiveView-specific review — iron laws, streams, auth, assigns, components"
mode: "ask"
tools: ["codebase"]
---

Review the selected LiveView module against our iron laws and patterns.

For each issue: **Severity** (Critical/High/Medium/Low) | **Location** (file:line) | **Issue** | **Fix**

### Mount / lifecycle
- Is there a DB query in the disconnected branch of `mount/3`? Must guard with `if connected?(socket)`.
- Does `assign_new/3` store anything that must be fresh on every reconnect?
- Is PubSub subscribe guarded by `if connected?(socket)`?

### Authorization
- Does every `handle_event/3` independently re-verify the actor's permission?
- Is any `handle_event` relying solely on `socket.assigns` for access control (not enough)?

### Data / assigns
- Are lists that could exceed ~100 items using `stream/3` + `stream_insert/3`? Never `assign` a growing list.
- Are computed/derived values recalculated in `render/1` rather than stored in assigns?
- Are assigns minimal — no data stored that the template doesn't use?

### Components
- Is stateless UI using `Phoenix.Component`, not `LiveComponent`?
- Is `LiveComponent` used only when local state is genuinely needed?
- Are all `attr` types declared on component props?

### Patterns
- Is business logic in the context module, not in the LiveView?
- Is `Repo` called directly from the LiveView? (must go through a context function)
- Are all user-visible strings wrapped in `gettext`?

Summarise as table sorted by Severity. For each violation, show the bad code and the corrected version side by side.
