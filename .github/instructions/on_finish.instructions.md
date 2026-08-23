---
name: elixir-on_finish
description: Run before finishing a task. Validates code quality and correctness for Elixir projects.
applyTo: "**/*.ex,**/*.exs"
---

Before finishing a task, run in order:

```bash
mix format
mix compile --warnings-as-errors
mix credo --strict
mix test
```

Fix every warning and error before moving on.