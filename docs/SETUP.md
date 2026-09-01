# Setup and deployment

Konevo is self-hosted. This guide is for the person operating an instance.
Before connecting real inboxes, read [Gmail integration](GMAIL.md) and
[Security](SECURITY.md).

## Local-development requirements

- Elixir `~> 1.15` and a compatible Erlang/OTP runtime
- PostgreSQL
- Node.js and npm
- ImageMagick for image processing
- A persistent filesystem location for uploads in production

Production does not need Elixir, Erlang, Node.js, or ImageMagick installed on
the server. It uses the pre-built container image described in
[Release deployment](RELEASE_DEPLOYMENT.md).

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
| `NAMECHEAP_API_KEY` | Namecheap wildcard HTTPS | Namecheap API key; keep only in the production `.env` |
| `NAMECHEAP_API_USER` | Namecheap wildcard HTTPS | Namecheap account username |
| `NAMECHEAP_CLIENT_IP` | Namecheap wildcard HTTPS | Public IPv4 address allowlisted in Namecheap API access |
| `RESEND_API_KEY` | Production | Resend transactional-email API key |
| `MAILER_FROM_EMAIL` | Production | Sender address on a Resend-verified domain |
| `MAILER_FROM_NAME` | No | Sender name; defaults to `Konevo` |
| `PORT` | No | HTTP port; defaults to `4000` |
| `POOL_SIZE` | No | Ecto connection pool size; defaults to `10` |
| `UPLOADS_ROOT` | No | Persistent uploads directory; defaults to `priv/uploads` |
| `ECTO_IPV6` | No | Set to `true` or `1` when PostgreSQL needs IPv6 |
| `DNS_CLUSTER_QUERY` | No | DNS query for distributed Erlang clustering |
| `PHX_SERVER` | Release start | Set to `true` to start the Phoenix endpoint |

## Self-hosted legal responsibilities

The built-in Privacy Policy and Terms describe the public Konevo website and
the Konevo software. They are not the privacy policy or terms for an operator's
separate self-hosted service.

Before exposing a self-hosted instance to users, its operator must provide and
maintain its own privacy policy, terms, support contact, and Google OAuth
consent-screen details. Those materials must accurately describe the operator's
hosting, data processing, integrations, and services, and should receive
operator-specific legal review.

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
Google OAuth consent screen with the public application home page, the
operator's privacy-policy URL, terms URL, and support email. These must belong
to the operator of this instance. The full process, scopes, test-mode limits,
and verification requirements are documented in [GMAIL.md](GMAIL.md).

## Production deployment

Use [Release deployment](RELEASE_DEPLOYMENT.md). It is the supported
single-server workflow: GitHub publishes an immutable GHCR image after a merge
of an application change to protected `main`, and the server optionally pulls
the newest GitHub Release itself. Documentation-only changes do not publish a
release. Application settings and secrets remain only in `/opt/konevo/app/.env`.

The container runs migrations and essential seeds when it starts. Create the
first owner explicitly with the command in that guide; it prints the result and
does not start a second web server.

## Production checklist

- Serve the app through HTTPS and set `PHX_HOST` to the exact public hostname.
- To serve arbitrary one-level subdomains, follow the optional Namecheap
  wildcard deployment in [RELEASE_DEPLOYMENT.md](RELEASE_DEPLOYMENT.md).
- Use a managed or hardened PostgreSQL deployment with backups and restricted
  network access.
- Set `UPLOADS_ROOT` to a persistent mounted directory outside the release.
- Back up the database and uploads together; test a restore before relying on
  the instance.
- Restrict database, upload-volume, and deployment-secret access to operators.
- Configure a monitored outbound-email domain in Resend before sending email.
- Publish and verify the operator's privacy policy, terms, support contact, and
  Google OAuth consent-screen details before inviting users.
- Configure the Google OAuth consent screen before connecting Gmail.
- Confirm `https://<PHX_HOST>/health` returns `{"status":"ok"}` after each
  deployment; it verifies the public Phoenix endpoint through Caddy.
- Back up before every release and verify the app after it deploys.

## Updates

Konevo is pre-release and does not promise stable public APIs or migration
compatibility. Read release changes, back up PostgreSQL and uploads, deploy the
new release, run migrations, and verify login, Gmail sync, background jobs, and
uploads after every upgrade.
