# Gmail integration

Konevo connects Gmail through OAuth 2.0. The operator of a self-hosted instance
must create and manage its own Google Cloud project and OAuth credentials.

## What Konevo requests

Konevo currently requests these Google scopes:

| Scope | Why Konevo uses it |
| --- | --- |
| `gmail.modify` | Sync conversations and update mailbox state, such as read status, from Inbox |
| `gmail.send` | Send replies and approved or enabled follow-up automation |
| `gmail.settings.basic` | Import a Gmail signature when the operator chooses to do so |
| `calendar.events.readonly` | Show Google Calendar events in Konevo |
| `userinfo.email` and `openid` | Identify the Google account being connected |

`gmail.modify` and `gmail.send` are restricted Gmail scopes. Request only the
scopes listed above and keep the Google Cloud consent-screen configuration in
sync with the application.

## Configure Google Cloud

1. Create or select a Google Cloud project.
2. Enable the **Gmail API** and **Google Calendar API**.
3. Configure the OAuth consent screen.
   - App name: `Konevo` or another accurate name for the operator's instance
   - Support email: an email monitored by the instance operator
   - Home page: `https://<PHX_HOST>/`
   - Privacy Policy: the operator's own public privacy-policy URL
   - Terms of Service: the operator's own public terms URL
4. Create an OAuth 2.0 client of type **Web application**.
5. Add the authorized redirect URI exactly as shown below.

   ```text
   http://localhost:4000/integrations/gmail/callback
   https://<PHX_HOST>/integrations/gmail/callback
   ```

6. Put the client ID and client secret in `GOOGLE_CLIENT_ID` and
   `GOOGLE_CLIENT_SECRET`. Restart Konevo after changing them.

Do not reuse one OAuth client and secret across unrelated self-hosted instances.
Each operator should control its own Google Cloud project.

Before configuring the consent screen, publish the operator's own legal pages.
The support email and legal URLs must be public, controlled by the instance
operator, use HTTPS, and match the information users see in that service. The
Konevo public-site Privacy Policy and Terms do not replace them.

## Connect an account

1. Sign in as an authorised workspace user and open **Settings**.
2. Choose **Connect Gmail**.
3. Read the in-product Gmail data-use notice and tick the acknowledgement.
4. Choose **Continue to Google** and approve the scopes on Google's screen.
5. Return to Konevo and wait for the initial sync.

The data-use notice appears before every new authorization or permission update.
The direct OAuth endpoint does not start authorization without that
acknowledgement.

## How data is used

Synced email data stays in the self-hosted Konevo instance. Gmail conversations
are used to power Inbox, contacts, task extraction, reply drafts, follow-ups,
signature import, and calendar display.

When AI features or AI automations are used, only the email/thread content needed
for that feature is sent to the AI provider configured by the instance operator.
The provider's own terms and privacy policy apply to that processing.

Disconnecting Gmail stops future sync and access. It does not automatically erase
email data already stored in the database or uploads volume; the instance operator
must remove that data if required.

## Sync and history import

- Active Gmail integrations are checked by a background job every five minutes.
- A history import is separate from normal recent sync; use the date range in
  Settings to queue it.
- Sync and import run in Oban. The UI can update before all queued work finishes.
- Gmail tokens are stored in the instance database. Protect database backups and
  database access as sensitive credentials.

## Testing and production

For personal development, keep the OAuth audience in **Testing** and add your own
Google account as a test user. Google issues refresh tokens that expire after
seven days in Testing for this set of scopes, so the account must be reconnected.

For an ongoing production connection, publish and verify the OAuth app. Restricted
Gmail scopes can require OAuth verification and, when restricted data is stored
or transmitted by a server, a security assessment. Follow Google's current
requirements before making an instance available to other users.

- [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy)
- [Google OAuth policy](https://developers.google.com/identity/protocols/oauth2/policies)
- [Restricted-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- [Google OAuth testing token limits](https://developers.google.com/identity/protocols/oauth2)

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Google rejects the redirect URI | The configured URI must exactly match `PHX_HOST`, scheme, path, and port |
| “Access blocked” or an unverified warning | Add your Google account as a test user, or complete Google verification for production |
| Sync stops after about seven days | Testing-mode refresh tokens expire; reconnect or publish the OAuth app |
| “invalid_grant” | Reconnect the Gmail account; the token may have expired or been revoked |
| Emails do not appear immediately | Wait for the five-minute sync cycle or use the product's sync controls |
