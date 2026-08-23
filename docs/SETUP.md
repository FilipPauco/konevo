# Setup and deployment

Konevo is self-hosted. This guide is for the person operating an instance.
Before connecting real inboxes, read [Gmail integration](GMAIL.md) and
[Security](SECURITY.md).

## Requirements

- Elixir `~> 1.15` and a compatible Erlang/OTP runtime
- PostgreSQL
- Node.js and npm
- ImageMagick for image processing
- A persistent filesystem location for uploads in production

The supplied [`Dockerfile`](../Dockerfile) installs the runtime dependencies for
a container release. It does not provide a database, reverse proxy, TLS
termination, or persistent volumes.

## Local development

1. Copy the environment example and replace every placeholder.

   ```shell
   cp .env.example .env
   ```

   On PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

2. Create the database, fetch dependencies, install asset tools, migrate, seed,
   and build assets.

   ```shell
   mix setup
   ```

3. Create the initial owner from `KONEVO_OWNER_EMAIL` and
   `KONEVO_OWNER_PASSWORD`.

   ```shell
   mix run -e "IO.inspect(Konevo.Release.create_owner())"
   ```

   Re-running this command with the same email is safe; it does not reset the
   existing password.

4. Start the server.

   ```shell
   mix phx.server
   ```

   Open <http://localhost:4000>. Registration is intentionally unavailable;
   only an existing owner or invited user can sign in.

## Environment variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `GOOGLE_CLIENT_ID` | Yes in development and production | Web OAuth client ID used by Gmail and calendar integration |
| `GOOGLE_CLIENT_SECRET` | Yes in development and production | Matching OAuth client secret |
| `KONEVO_OWNER_EMAIL` | For owner creation | Initial owner email |
| `KONEVO_OWNER_PASSWORD` | For owner creation | Initial owner password |
| `DATABASE_URL` | Production | PostgreSQL connection URL |
| `SECRET_KEY_BASE` | Production | Phoenix cookie and token secret; generate with `mix phx.gen.secret` |
| `PHX_HOST` | Production | Public hostname without scheme or path |
| `RESEND_API_KEY` | Production | Resend transactional-email API key |
| `MAILER_FROM_EMAIL` | Production | Sender address on a Resend-verified domain |
| `MAILER_FROM_NAME` | No | Sender name; defaults to `Konevo` |
| `PORT` | No | HTTP port; defaults to `4000` |
| `POOL_SIZE` | No | Ecto connection pool size; defaults to `10` |
| `UPLOADS_ROOT` | No | Persistent uploads directory; defaults to `priv/uploads` |
| `ECTO_IPV6` | No | Set to `true` or `1` when PostgreSQL needs IPv6 |
| `DNS_CLUSTER_QUERY` | No | DNS query for distributed Erlang clustering |
| `PHX_SERVER` | Release start | Set to `true` to start the Phoenix endpoint |

## AI setup

Konevo uses one OpenAI API key, configured in **Settings → AI** for the
workspace. The application stores the key encrypted; do not add it to `.env`
or commit it to the repository.

- **GPT-5.6 Luna** handles fast, high-volume extraction and lightweight tasks.
- **GPT-5.6 Terra** handles higher-quality drafting and deeper research.

The Settings page shows this month's Luna-versus-Terra usage, including tokens,
runs, and estimated cost.

## Gmail prerequisites

Create a Google Cloud OAuth **Web application** client. The redirect URI must
match exactly:

- Development: `http://localhost:4000/integrations/gmail/callback`
- Production: `https://<PHX_HOST>/integrations/gmail/callback`

Enable the Gmail API and Google Calendar API for the project. Configure the
Google OAuth consent screen with the public application home page, privacy
policy, terms of use, and support email. The full process, scopes, test-mode
limits, and verification requirements are documented in [GMAIL.md](GMAIL.md).

## Production release

Set production environment variables, then build the release:

```shell
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
PHX_SERVER=true _build/prod/rel/konevo/bin/konevo start
```

Run migrations and seeds before normal traffic:

```shell
_build/prod/rel/konevo/bin/konevo eval "Konevo.Release.migrate_and_seed()"
```

Create the owner once the release can reach the production database:

```shell
_build/prod/rel/konevo/bin/konevo eval "Konevo.Release.create_owner()"
```

The supplied container command runs migrations and essential seeds. It does not
create an owner automatically.

## Production checklist

- Serve the app through HTTPS and set `PHX_HOST` to the exact public hostname.
- Use a managed or hardened PostgreSQL deployment with backups and restricted
  network access.
- Set `UPLOADS_ROOT` to a persistent mounted directory outside the release.
- Back up the database and uploads together; test a restore before relying on
  the instance.
- Restrict database, upload-volume, and deployment-secret access to operators.
- Configure a monitored outbound-email domain in Resend before sending email.
- Configure the Google OAuth consent screen before connecting Gmail.
- Run `mix precommit` before upgrading your deployment from source.

## Updates

Konevo is pre-release and does not promise stable public APIs or migration
compatibility. Read release changes, back up PostgreSQL and uploads, deploy the
new release, run migrations, and verify login, Gmail sync, background jobs, and
uploads after every upgrade.
