---
description: "Security review for Elixir/Phoenix/LiveView — OWASP + OTP + GDPR"
mode: "ask"
tools: ["codebase"]
---

Perform a thorough security review of the selected/active code. Focus on Elixir, Phoenix, LiveView, Ecto, and GDPR specifics.

For each issue: **Severity** (Critical/High/Medium/Low) | **Location** (file:line) | **Issue** | **Risk** | **Fix**

### Elixir / OTP
- `String.to_atom/1` with user-controlled input (atom exhaustion / DoS)
- Bare `spawn` for stateful processes (unsupervised — crash + data loss risk)
- Blocking the BEAM scheduler with heavy sync work in LiveView or GenServer

### Phoenix / LiveView
- Missing authorization re-check inside every `handle_event/3` (not just assigns check)
- `raw/1` or `{:safe, ...}` with user-controlled or AI-generated strings (XSS)
- CSRF disabled on any route or form
- `assign_new/3` for values that must be fresh on every mount (stale data)
- PubSub subscriptions outside `if connected?(socket)` guard (duplicate subscriptions)
- DB queries in disconnected `mount/3`

### Ecto / Database
- String interpolation in fragments: `fragment("... #{user_input}")` (SQL injection)
- Unpinned variables in `from` macros — missing `^`
- `:float` for any money field (must be `:decimal`)
- Sensitive data leaked via `IO.inspect` or `Logger.debug` in production paths

### Secrets & Config
- Secrets or credentials hardcoded outside `config/runtime.exs`
- API keys (OpenAI, Twilio, Stripe) committed in source or `config/dev.exs`
- `SECRET_KEY_BASE` / DB password not loaded from env at runtime

### Outbound messaging (email + SMS)
- Email or SMS sent without checking suppression/opt-out list first
- Twilio webhook endpoint not verifying `X-Twilio-Signature` header (spoofing)
- Automation rules firing without per-contact consent being verified

### GDPR / Compliance
- PII (email body, phone, name) logged at any log level
- Contact delete does not cascade to emails, messages, and audit entries (incomplete erasure)
- Raw PII sent to external LLM (OpenAI/Anthropic) without pseudonymisation
- No rate limiting on public-facing forms, webhooks, or API endpoints
- Missing input validation at system boundaries (form params, webhook payloads, API params)

Format as a table sorted by Severity (Critical first). Include a corrected code snippet for every finding.
