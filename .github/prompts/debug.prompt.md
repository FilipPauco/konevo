---
description: "Structured debugging for Elixir/OTP/Phoenix/LiveView — investigate before changing code"
mode: "ask"
tools: ["codebase"]
---

Investigate the issue in the selected code or described error. Follow this order strictly — do not suggest any code change until step 4.

### 0. Reproduce first
- What is the exact error message or unexpected behaviour?
- Is it consistent or intermittent?
- Does it happen in a specific LiveView lifecycle phase (`mount`, `handle_event`, `handle_info`)?
- Intermittent → suspect process state or race condition → go to step 1
- Wrong data → suspect query → go to step 2
- UI not updating → suspect assigns/streams → go to step 3

### 1. OTP process tree
- Is the process alive? Check with `Process.alive?/1` or `:observer.start()`
- What is the supervision strategy? Is it restarting unexpectedly?
- Is the crash caused by a linked process dying upstream?
- Inspect `GenServer` state with `:sys.get_state(pid)` or `:observer`

### 2. Ecto query logs
- Enable query logging: `config :logger, level: :debug` in `dev.exs`
- Look for N+1: same query repeating in a loop in logs
- Check for missing `^` pins causing incorrect filtering
- Verify preloads happen at the context boundary, not in the template
- For slow queries: `EXPLAIN ANALYZE` via `Repo.query/2`

### 3. LiveView assign state
- What are the current assigns at the point of failure? Use `dbg(socket.assigns)` in `handle_event`
- Is the disconnected `mount/3` running a DB query it shouldn't?
- Is a list growing unbounded instead of using `stream_insert/3`?
- Is an event handler missing an authorization check?

### 4. Only after investigation
- State exactly what was found in steps 1–3
- Propose the **minimal** code change that fixes the root cause
- Do not refactor unrelated code
