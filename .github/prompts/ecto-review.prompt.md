---
description: "Ecto/DB review — N+1, money types, query safety, migrations, transactions"
mode: "ask"
tools: ["codebase"]
---

Review the selected Ecto schemas, queries, and migrations.

For each issue: **Severity** (Critical/High/Medium/Low) | **Location** (file:line) | **Issue** | **Fix**

### Query safety
- Unpinned variables in `from` macros (missing `^`) — wrong data or silent runtime bug
- String interpolation in `fragment/1` — SQL injection risk
- `Repo` called directly outside a context module
- Raw SQL via `Repo.query/2` where `Ecto.Query` would suffice

### N+1 prevention
- Associations accessed in templates or LiveViews without preloading at the context boundary
- `Repo.all` without preloads where the caller iterates over associations
- Missing explicit `:preload` for `has_many` associations (never JOIN for has_many)

### Data types
- `:float` for any monetary value (must be `:decimal` or integer cents)
- Missing `null: false` + `default:` on columns that must never be null
- Storing JSON blobs for data that is queried/filtered (normalise instead)

### Pagination / limits
- Unbounded `Repo.all` on tables that grow without a limit (contacts, emails, tasks, messages)
- Missing `limit/2` or stream/cursor pagination on large dataset queries

### Migrations
- Column dropped before data is migrated off it (destructive without backfill)
- Constraint or index added on a large existing table without `concurrently` option
- New non-nullable column added without a default (will fail on existing rows)
- Foreign key added without an index on the referencing column (`org_id`, `contact_id`, etc.)

### Transactions
- Multi-step writes (create + associate + log) not wrapped in `Repo.transaction`
- Side effects (sending email, triggering Oban job) inside a transaction before it commits

Summarise as table sorted by Severity. Show corrected query, schema, or migration for each finding.
