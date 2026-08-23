<p align="center">
  <img src="priv/static/images/logo-navbar.png" alt="Konevo logo" width="180" />
</p>

<h1 align="center">Konevo</h1>

<p align="center">
  <strong>Your inbox, organized into meaningful relationships.</strong>
</p>

<p align="center">
  A self-hosted, AI-first CRM that turns email into contacts, tasks, and follow-ups&mdash;while you stay in control.
</p>

<p align="center">
  <a href="#installation">Installation</a> &middot;
  <a href="#quick-start">Source development</a> &middot;
  <a href="docs/README.md">Documentation</a> &middot;
  <a href="docs/SETUP.md">Deployment</a>
</p>

<p align="center">
  <img src="priv/static/images/landing_small.png" alt="Konevo contacts workspace preview" width="1200" />
</p>

Konevo is not a hosted service. You deploy it, control its infrastructure, and
bring your own Gmail OAuth credentials and OpenAI API key.

## Built for the work that happens after &ldquo;send&rdquo;

Konevo helps your team turn an overflowing inbox into clear, shared next steps.

- **Remember every relationship.** Keep people, companies, deals, tasks, and the context behind every conversation together in one workspace.
- **Work from the inbox you already use.** Sync Gmail, bring in email history, write replies with your signatures, and create calendar events without losing the thread.
- **Put AI to work&mdash;with you in control.** Let Konevo spot tasks and draft replies, then review every suggestion before it becomes action.
- **Never let a good conversation go cold.** Start with ready-made automations for unanswered emails, turning messages into tasks, and preparing AI-assisted replies.
- **Own your workflow and your data.** Run Konevo yourself, collaborate with your team, and rely on activity history, file uploads, review queues, and thoughtful follow-up safeguards.

## Documentation

Start here:

- [Documentation index](docs/README.md)
- [Setup and deployment](docs/SETUP.md)
- [Gmail integration](docs/GMAIL.md)
- [Automations](docs/AUTOMATIONS.md)
- [Security and operational hardening](docs/SECURITY.md)

The public product presentation is available at `/` after starting Konevo.

## Installation

There are two ways to run Konevo. The pre-built image method is recommended for
production self-hosting.

### Option A — Pre-built images (recommended)

No cloning or building required. Docker pulls a version-pinned Konevo release
image from GitHub Container Registry (GHCR).

#### Prerequisites

- A Linux server with Docker Engine and Docker Compose v2
- A public domain with DNS pointing at the server
- Ports 80 and 443 open in the server firewall and provider firewall
- Google OAuth and Resend credentials; see [Gmail setup](docs/GMAIL.md)

#### 1. Download the deployment files and default configuration

~~~shell
sudo mkdir -p /opt/konevo/app/deploy/docker
sudo chown -R "$USER":"$USER" /opt/konevo
cd /opt/konevo/app

curl -fsSL -o deploy/docker/compose.yaml \
  https://raw.githubusercontent.com/FilipPauco/konevo/main/deploy/docker/compose.yaml
curl -fsSL -o deploy/docker/Caddyfile \
  https://raw.githubusercontent.com/FilipPauco/konevo/main/deploy/docker/Caddyfile
curl -fsSL -o .env \
  https://raw.githubusercontent.com/FilipPauco/konevo/main/.env.example
~~~

#### 2. Configure the environment

Edit .env, replacing every placeholder. The Docker stack supplies
DATABASE_URL, PHX_SERVER, and the persistent uploads path automatically.

~~~shell
nano .env
~~~

| Variable | Description |
| --- | --- |
| PHX_HOST | Public hostname only, for example crm.example.com |
| SECRET_KEY_BASE | Phoenix session secret; generate with openssl rand -hex 64 |
| POSTGRES_PASSWORD | Password for the bundled PostgreSQL database; generate with openssl rand -hex 32 |
| KONEVO_OWNER_EMAIL | Email address of the first private owner account |
| KONEVO_OWNER_PASSWORD | Long, unique password for that owner account |
| GOOGLE_CLIENT_ID | Google OAuth Web application client ID |
| GOOGLE_CLIENT_SECRET | Matching Google OAuth client secret |
| RESEND_API_KEY | Resend API key for transactional email |
| MAILER_FROM_EMAIL | Sender address on a Resend-verified domain |
| MAILER_FROM_NAME | Optional sender name; defaults to Konevo |

Pin the latest published release image:

~~~shell
KONEVO_VERSION="$(curl -fsSL https://api.github.com/repos/FilipPauco/konevo/releases/latest | grep -m1 '"tag_name"' | cut -d '"' -f4)"
printf '\nAPP_IMAGE=ghcr.io/filippauco/konevo-crm:%s\n' "$KONEVO_VERSION" >> .env
~~~

#### 3. Start Konevo

~~~shell
sudo mkdir -p /opt/konevo/uploads
docker compose --env-file .env -f deploy/docker/compose.yaml up -d
~~~

The stack starts Konevo, PostgreSQL, and Caddy. Caddy automatically requests
and renews a TLS certificate for PHX_HOST.

#### 4. Create the first owner account

Public registration is disabled. After the app has completed startup and
migrations, create the owner configured in .env:

~~~shell
docker compose --env-file .env -f deploy/docker/compose.yaml \
  exec app bin/konevo eval "Konevo.Release.create_owner()"
~~~

Open https://<PHX_HOST> and sign in with that account.

#### 5. Connect Gmail and AI

Set the Google OAuth redirect URI to:

~~~text
https://<PHX_HOST>/integrations/gmail/callback
~~~

Then sign in, open **Settings**, connect Gmail, and add your OpenAI API key in
**Settings → AI**. The application encrypts the AI key; do not add it to .env.

### Updating

Back up PostgreSQL and /opt/konevo/uploads before updating. Then pin the newest
release image and restart only the app service:

~~~shell
KONEVO_VERSION="$(curl -fsSL https://api.github.com/repos/FilipPauco/konevo/releases/latest | grep -m1 '"tag_name"' | cut -d '"' -f4)"
sed -i "s|^APP_IMAGE=.*|APP_IMAGE=ghcr.io/filippauco/konevo-crm:$KONEVO_VERSION|" .env

docker compose --env-file .env -f deploy/docker/compose.yaml pull app
docker compose --env-file .env -f deploy/docker/compose.yaml up -d --no-deps app
~~~

The release runs migrations and essential seeds when the app starts. Review
release notes and verify login, Gmail sync, background jobs, and uploads after
each update.

## Quick start

Requirements: Elixir 1.15+, Erlang/OTP, PostgreSQL, Node.js/npm, and ImageMagick.

```shell
cp .env.example .env
mix setup
mix phx.server
```

On PowerShell, use `Copy-Item .env.example .env`. Then create the first owner:

```shell
mix run -e "IO.inspect(Konevo.Release.create_owner())"
```

Open <http://localhost:4000>. Public registration is intentionally disabled.

## Self-hosting responsibilities

The operator of a Konevo instance is responsible for its users, data, backups,
hosting location, Gmail OAuth configuration, OpenAI API configuration, and
compliance obligations. Read the [setup](docs/SETUP.md),
[Gmail](docs/GMAIL.md), and [security](docs/SECURITY.md) guides before connecting
real data.

## License

Konevo is **source-available, not open source**.

- Personal and other noncommercial use: PolyForm Strict License 1.0.0
- Internal business use and private internal modifications: PolyForm Internal Use License 1.0.0

Redistribution, resale, sublicensing, white-labeling, paid third-party
installation, and hosted or managed service use require written permission.
Read [LICENSE](LICENSE), [commercial licensing](COMMERCIAL-LICENSING.md), and
[trademark terms](TRADEMARKS.md).

## Participate or get help

Feedback and bug reports are welcome through GitHub issues. Read
[CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request. For licensing,
collaboration, or product questions, email [filip.pauco08@gmail.com](mailto:filip.pauco09@gmail.com).

Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
