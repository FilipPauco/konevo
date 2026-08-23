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

Follow [DOCKER.md](DOCKER.md) to secure the server, install Docker, configure
DNS, and create the production .env file. Then prepare the deploy account:

~~~shell
sudo adduser --system --group --home /opt/konevo --shell /usr/sbin/nologin konevo-deploy
sudo install -d -o konevo-deploy -g konevo-deploy /opt/konevo/app
sudo -u konevo-deploy git clone https://github.com/<owner>/<repository>.git /opt/konevo/app
sudo install -d -o 65534 -g 65534 -m 750 /opt/konevo/uploads
sudo install -d -o konevo-deploy -g konevo-deploy -m 750 /var/lib/konevo
~~~

Create the production environment file manually. It is the only source of app
secrets and must remain outside Git:

~~~shell
sudo install -o root -g konevo-deploy -m 640 /dev/null /opt/konevo/app/.env
sudoedit /opt/konevo/app/.env
~~~

Create the deployer's non-secret configuration:

~~~shell
sudo install -d -o root -g root -m 755 /etc/konevo
sudo install -o root -g root -m 644 \
  /opt/konevo/app/deploy/docker/deploy.env.example /etc/konevo/deploy.env
sudoedit /etc/konevo/deploy.env
~~~

Set the public identifiers in /etc/konevo/deploy.env:

~~~dotenv
APP_IMAGE_REPOSITORY=ghcr.io/<owner>/<repository>
GITHUB_REPOSITORY=<owner>/<repository>
~~~

Install and enable the deployer after a release image exists:

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

The server needs curl, jq, Git, Docker Engine, and the Docker Compose plugin.
The timer checks at boot and then approximately every five minutes.

## 5. Operations and rollback

- Back up PostgreSQL, /opt/konevo/uploads, and .env to an encrypted off-server
  destination; test restores.
- Verify login, email delivery, Gmail, uploads, and logs after each release.
- Keep the previous image until the new version is verified.
- Database migrations are forward-only in practice. Do not roll back after a
  migration without reviewing compatibility and restoring a matching backup if
  needed.
- Apply infrastructure changes deliberately rather than through the app timer.
