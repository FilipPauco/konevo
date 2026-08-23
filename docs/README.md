# Konevo documentation

These documents describe the currently implemented self-hosted product.

| Guide | Use it for |
| --- | --- |
| [Setup and deployment](SETUP.md) | Local development, production releases, environment variables, backups |
| [Gmail integration](GMAIL.md) | Google Cloud OAuth setup, scopes, testing, and production verification |
| [Automations](AUTOMATIONS.md) | Workflow behavior, approvals, exclusions, and scheduled processing |
| [Security](SECURITY.md) | Deployment hardening, secrets, uploads, incident response, and known boundaries |
| [Search visibility](SEO.md) | Search metadata, sharing previews, sitemap, and post-deployment indexing |
| [Docker deployment](DOCKER.md) | A single-server Docker, PostgreSQL, and HTTPS deployment |
| [Release deployment](RELEASE_DEPLOYMENT.md) | Public-repository CI, GHCR releases, and server pull deployment |

## Public versus private notes

Everything in `docs/` is intended to be public. Use `docs/private/` for personal
planning, deployment records, or credentials-related notes. Git ignores every
file in that directory except its [README](private/README.md), so private notes
cannot be committed accidentally.

## Legacy planning material

Early planning material belongs under `docs/private/wiki/` on the maintainer's
local copy. It is ignored by Git because it contains ideas and assumptions that
are not part of the current public product documentation.
