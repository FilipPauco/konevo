# Public-repository release deployment

This deployment model keeps production secrets on your server. GitHub builds a
public immutable image, and the server polls GitHub over HTTPS for a published
release. GitHub never receives a production SSH key, webhook secret, or .env.

~~~text
Approved pull request -> protected main -> GitHub CI -> GHCR image + GitHub Release
                                                   -> server systemd timer -> Docker Compose
~~~

The supplied deployment files live in deploy/docker:

- compose.yaml runs an immutable APP_IMAGE instead of building source code;
- konevo-deploy.sh fetches the newest GitHub Release and deploys its matching image;
- konevo-deploy.service and konevo-deploy.timer run the systemd job; and
- deploy.env.example contains non-secret deployment settings.

## 1. Before making the repository public

1. Audit the working tree and Git history for credentials, uploads, database
   dumps, backups, private notes, SSH keys, and real user data. Rotate any
   credential that was ever committed.
2. Keep .env untracked and commit only .env.example with placeholders.
3. Enable GitHub secret scanning, push protection, Dependabot alerts, and
   Dependabot security updates.

## 2. GitHub settings

Protect main with pull requests, successful CI, independent review, blocked
force pushes, and restricted bypass permissions. Keep the Actions default token
read-only; the workflow requests only the extra permissions needed per job.

After the first successful build, make the linked GHCR package public so the
server can pull release images without a registry credential.

Do not add production secrets or server SSH keys to GitHub. The automatic
github.token publishes images and creates releases with the limited permissions
defined in the workflow.

## 3. CI behavior

On a push to protected main, the release workflow:

1. verifies formatting, compilation, tests, and Credo;
2. builds an image tagged with the immutable commit SHA;
3. creates a vX.Y.Z Git tag;
4. tags that image as vX.Y.Z; and
5. creates the GitHub Release.

The deployer watches GitHub Releases, not raw branch commits or mutable latest
tags. The workflow does not SSH to the production server.

## 4. Prepare the server

Use a Linux server with Docker Engine and the Docker Compose plugin installed.
Point your domain at the server, allow inbound TCP ports 80 and 443, and secure
SSH with an administrator key. Install the deployer's small dependencies:

~~~shell
sudo apt update && sudo apt install -y curl jq git
~~~

Then prepare the deploy account and clone the public repository once. Do not
download individual Compose files with `curl`.

~~~shell
sudo adduser --system --group --home /opt/konevo --shell /usr/sbin/nologin konevo-deploy
sudo install -d -o konevo-deploy -g konevo-deploy /opt/konevo/app
sudo -u konevo-deploy git clone https://github.com/FilipPauco/konevo.git /opt/konevo/app
sudo install -d -o 65534 -g 65534 -m 750 /opt/konevo/uploads
sudo install -d -o konevo-deploy -g konevo-deploy -m 750 /var/lib/konevo
~~~

Create the production environment file from the committed placeholder file. It
stores app settings and secrets and must remain outside Git:

~~~shell
sudo install -o root -g konevo-deploy -m 640 \
  /opt/konevo/app/.env.example /opt/konevo/app/.env
sudoedit /opt/konevo/app/.env
~~~

Set every placeholder, including `APP_IMAGE`, `PHX_HOST`, `SECRET_KEY_BASE`,
`POSTGRES_PASSWORD`, the initial owner, Gmail OAuth, and email values.
`APP_IMAGE` must be the immutable release to run, for example
`ghcr.io/filippauco/konevo:vX.Y.Z`. The Compose file supplies the database URL,
endpoint start flag, and persistent upload path.

If you want automatic updates, create the deployer's non-secret configuration:

~~~shell
sudo install -d -o root -g root -m 755 /etc/konevo
sudo install -o root -g root -m 644 \
  /opt/konevo/app/deploy/docker/deploy.env.example /etc/konevo/deploy.env
sudoedit /etc/konevo/deploy.env
~~~

Set the public identifiers in /etc/konevo/deploy.env:

~~~dotenv
APP_IMAGE_REPOSITORY=ghcr.io/filippauco/konevo
GITHUB_REPOSITORY=FilipPauco/konevo
~~~

If the optional Namecheap wildcard setup below is enabled, also add this so
automatic deployments keep using the wildcard Caddy configuration:

~~~dotenv
COMPOSE_FILES=deploy/docker/compose.yaml:deploy/docker/compose.namecheap-wildcard.yaml
~~~

## 5. Start the first release

After GitHub has published a release and its GHCR package is public, set
`APP_IMAGE` in `/opt/konevo/app/.env` to its actual release tag. Then run:

~~~shell
sudo docker compose --env-file /opt/konevo/app/.env \
  -f /opt/konevo/app/deploy/docker/compose.yaml up -d
~~~

The stack starts PostgreSQL, Konevo, and Caddy. Caddy requests and renews the
TLS certificate for `PHX_HOST`.

### Optional: serve every subdomain with Namecheap DNS

Use this only when the application must serve arbitrary one-level subdomains,
such as `tenant.konevo.net`. Keep `PHX_HOST` set to the base hostname (for
example, `konevo.net`); do not set it to a wildcard. A wildcard certificate is
required because the certificate for `konevo.net` does not cover its
subdomains.

In Namecheap, confirm that the domain uses Namecheap BasicDNS, PremiumDNS, or
FreeDNS. Add an `A Record` with host `*` and the server's public IPv4 address.
Enable Namecheap API access, add that same server IPv4 address to the API
allowlist, and add these values to `/opt/konevo/app/.env`:

~~~dotenv
NAMECHEAP_API_KEY=replace-with-the-namecheap-api-key
NAMECHEAP_API_USER=your-namecheap-username
NAMECHEAP_CLIENT_IP=your-server-public-ipv4
~~~

Start the stack with the optional Compose override. It builds Caddy once with
the Namecheap DNS module, then Caddy creates and renews the certificate for
both `PHX_HOST` and `*.PHX_HOST`:

~~~shell
sudo docker compose --env-file /opt/konevo/app/.env \
  -f /opt/konevo/app/deploy/docker/compose.yaml \
  -f /opt/konevo/app/deploy/docker/compose.namecheap-wildcard.yaml up -d --build
~~~

This covers `tenant.konevo.net`, but not nested names such as
`api.tenant.konevo.net`.

Create the owner configured in `.env`. The command temporarily disables the web
endpoint in this one-off process, so it does not compete for port 4000:

~~~shell
sudo docker compose --env-file /opt/konevo/app/.env \
  -f /opt/konevo/app/deploy/docker/compose.yaml \
  exec app env -u PHX_SERVER bin/konevo eval \
  'IO.inspect(Konevo.Release.create_owner(), label: "Owner creation")'
~~~

`Owner creation: {:ok, ...}` confirms success. Re-running it is safe and may
report that the owner already exists.

## 6. Optional automatic updates

Install and enable the deployer after the first release is running:

~~~shell
sudo install -o root -g root -m 755 \
  /opt/konevo/app/deploy/docker/konevo-deploy.sh /usr/local/sbin/konevo-deploy
sudo install -o root -g root -m 644 \
  /opt/konevo/app/deploy/docker/konevo-deploy.service /etc/systemd/system/konevo-deploy.service
sudo install -o root -g root -m 644 \
  /opt/konevo/app/deploy/docker/konevo-deploy.timer /etc/systemd/system/konevo-deploy.timer
sudo systemctl daemon-reload
sudo systemctl enable --now konevo-deploy.timer
sudo systemctl start konevo-deploy.service
~~~

The timer checks at boot and then approximately every five minutes. It queries
the public GitHub Release API, pulls the matching immutable image, and restarts
only the app service. GitHub does not connect to the server.

## 7. Operations and rollback

- Back up PostgreSQL, /opt/konevo/uploads, and .env to an encrypted off-server
  destination; test restores.
- Verify login, email delivery, Gmail, uploads, and logs after each release.
- Keep the previous image until the new version is verified.
- Database migrations are forward-only in practice. Do not roll back after a
  migration without reviewing compatibility and restoring a matching backup if
  needed.
- Apply infrastructure changes deliberately rather than through the app timer.
