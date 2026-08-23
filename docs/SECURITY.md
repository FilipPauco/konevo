# Security and operational hardening

Konevo is self-hosted. Security depends on both the application and the person
operating the instance. This guide describes the deployment responsibilities and
the current implementation boundaries.

## Before production

- Serve Konevo only over HTTPS behind a maintained reverse proxy or platform.
- Set a long, unique `SECRET_KEY_BASE` using `mix phx.gen.secret`.
- Use a strong initial owner password and create separate accounts for people who
  need access; do not share credentials.
- Restrict PostgreSQL to the application network and use unique database
  credentials.
- Persist `UPLOADS_ROOT` outside the release directory with restrictive filesystem
  permissions. Include it in backups.
- Store environment variables in the deployment platform's secret manager, not in
  `.env` committed to Git.
- Keep the operating system, Erlang/Elixir runtime, PostgreSQL, ImageMagick, and
  dependencies patched.

## Protect secrets and Gmail access

Treat all of the following as secrets:

- `SECRET_KEY_BASE`, database URL, Resend API key, and OAuth client secret
- Google access and refresh tokens stored for connected inboxes
- AI provider keys configured in Settings
- database backups, uploads, exports, and logs containing customer data

Konevo stores Gmail access and refresh tokens in its database so that sync can
continue. The current application does not add a separate application-level token
encryption layer. Protect database-at-rest encryption, database network access,
backups, and operator access accordingly.

Each self-hosted operator should use its own Google Cloud OAuth project and should
never expose its client secret in browser code, issues, logs, screenshots, or
repositories.

## Application controls

Konevo includes these controls, but they do not replace secure deployment:

- authenticated and organisation-scoped routes for CRM data;
- CSRF protection and secure browser headers, including a content security policy;
- per-organisation access checks for application actions;
- OAuth state validation before a Gmail callback is accepted;
- Gmail data-use acknowledgement before authorization begins;
- server-side file validation and cleanup processing; and
- background-job retries for recoverable work.

Review changes carefully before assuming a control applies to a new integration or
customisation.

## Uploads and attachments

Uploads can contain untrusted content. Keep the uploads directory non-executable,
restrict access, and scan files with infrastructure controls appropriate to your
environment. ImageMagick is used for image processing; keep it patched and limit
the runtime permissions of the process that invokes it.

Do not expose the raw uploads directory through a public web server. Konevo serves
application files through authenticated routes and authorisation checks.

## AI and third parties

AI features may send email or CRM content to the AI provider selected by the
instance operator. Review provider data-processing terms, choose an appropriate
region and retention configuration where available, and do not enable AI on data
you are not allowed to share.

Gmail, Google Calendar, Resend, and any AI provider are independent services.
Their credentials, availability, retention, and terms are the operator's
responsibility.

## Backups and recovery

- Back up PostgreSQL and `UPLOADS_ROOT` together.
- Encrypt backups and restrict access to restore operators.
- Test restoring into an isolated environment before an incident occurs.
- Define your own retention and deletion schedule; disconnecting Gmail stops new
  access but does not automatically erase previously synced data.

## Security updates

Before upgrading, back up the instance and run:

```shell
mix precommit
```

After deployment, check that login, the dashboard, Gmail sync, background jobs,
uploads, and outbound email work as expected.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Follow the repository
[security policy](../SECURITY.md) and email
[filip.pauco08@gmail.com](mailto:filip.pauco08@gmail.com) with the impact,
affected version or commit, and safe reproduction steps.
