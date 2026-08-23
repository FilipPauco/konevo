# Docker deployment

This guide deploys one self-hosted Konevo instance on a Linux server with
Docker, PostgreSQL, and Caddy-managed HTTPS. It is intended for personal and
small internal deployments, not high availability.

The Docker bundle lives in deploy/docker. It keeps PostgreSQL private to the
Docker network, exposes only Caddy on ports 80 and 443, and persists database,
TLS, and upload data.

## 1. Provision and secure the server

Use a supported Linux server with an SSH key. Allow:

- TCP 22 only from administrator IP addresses;
- TCP 80 from anywhere; and
- TCP 443 from anywhere.

Do not expose PostgreSQL on port 5432 or the Konevo app on port 4000. Install
Docker Engine and Docker Compose using the [official Docker instructions](https://docs.docker.com/engine/install/).

## 2. Point DNS before starting Caddy

Create an A record for the final hostname, such as konevo.example.com, pointing
to the server's public IPv4 address. Add an AAAA record only when IPv6 is
configured. Caddy uses the hostname to obtain and renew the TLS certificate.

## 3. Download the bundle

The README includes a no-clone installation flow. For the automated release
deployer, follow [RELEASE_DEPLOYMENT.md](RELEASE_DEPLOYMENT.md#4-prepare-the-server)
instead.

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

## 4. Configure the environment

Set every placeholder in .env. At minimum configure PHX_HOST,
SECRET_KEY_BASE, POSTGRES_PASSWORD, the owner credentials, Google OAuth
credentials, and the Resend sender credentials.

Generate a Phoenix secret and database password on a trusted machine:

~~~shell
openssl rand -hex 64
openssl rand -hex 32
~~~

Configure Google OAuth with these exact URLs:

- Home page: https://<PHX_HOST>/
- Privacy policy: https://<PHX_HOST>/privacy
- Terms: https://<PHX_HOST>/terms
- Redirect URI: https://<PHX_HOST>/integrations/gmail/callback

See [GMAIL.md](GMAIL.md) for Google Cloud requirements.

## 5. Start a published release

Select a release image, then start the application stack:

~~~shell
KONEVO_VERSION="$(curl -fsSL https://api.github.com/repos/FilipPauco/konevo/releases/latest | grep -m1 '"tag_name"' | cut -d '"' -f4)"
printf '\nAPP_IMAGE=ghcr.io/filippauco/konevo-crm:%s\n' "$KONEVO_VERSION" >> .env

sudo install -d -o 65534 -g 65534 -m 750 /opt/konevo/uploads
docker compose --env-file .env -f deploy/docker/compose.yaml up -d
docker compose --env-file .env -f deploy/docker/compose.yaml ps
docker compose --env-file .env -f deploy/docker/compose.yaml logs --tail=100 app caddy
~~~

The application runs migrations and essential seeds before starting. Create the
owner account once:

~~~shell
docker compose --env-file .env -f deploy/docker/compose.yaml \
  exec app bin/konevo eval "Konevo.Release.create_owner()"
~~~

## 6. Verify before connecting real Gmail data

Over HTTPS, verify the home page, privacy policy, terms, robots file, and
sitemap; sign in as the owner; confirm transactional email; connect a test
Gmail account; and confirm uploads survive a container restart.

## Backups and updates

Back up PostgreSQL and /opt/konevo/uploads together to an encrypted off-server
destination. Test restoring before relying on the instance.

For manual updates, pin a new APP_IMAGE version and restart only the app:

~~~shell
docker compose --env-file .env -f deploy/docker/compose.yaml pull app
docker compose --env-file .env -f deploy/docker/compose.yaml up -d --no-deps app
~~~

Do not scale to multiple app containers without reviewing migrations, cluster
configuration, uploads, and background jobs.
