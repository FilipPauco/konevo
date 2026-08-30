# Docker deployment

Use [RELEASE_DEPLOYMENT.md](RELEASE_DEPLOYMENT.md) for the current Docker
deployment. It deploys immutable GitHub Container Registry release images and
can use a server-side systemd timer for updates; GitHub never needs an SSH key
or application secrets.

Do not download individual Compose files with `curl`. Clone the public
repository once so the Compose file, Caddy configuration, deployer, and the
release image are always from the same version.

Before deploying, secure the server firewall, allow only ports 80 and 443
publicly, and restrict SSH to an administrator key and your own IP address.
