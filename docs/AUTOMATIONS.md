# Automations

Konevo automations convert email events into follow-ups, tasks, and reviewable
AI drafts. They run through Oban background jobs, so an action may be queued
shortly after the event rather than appearing in the same browser response.

## Workflow types

| Workflow | Trigger | Result |
| --- | --- | --- |
| No-reply follow-up | A thread has an outbound message and no newer customer reply after the chosen delay | A follow-up draft for review, or a sent follow-up when automatic mode is chosen |
| Email to task | A newly imported inbound email | AI task suggestions for review, or created tasks in automatic mode |
| AI email reply | A newly imported inbound email after the workflow was activated | An AI reply draft for review |

## Important rules

### One active workflow of each type

Only one workflow of a given type can be active in an organisation. You may keep
multiple drafts, paused workflows, or archived workflows, but activating a second
workflow of the same type is blocked until the existing active one is paused or
archived.

This avoids duplicate task extraction, reply drafts, and follow-ups for the same
email event.

### Lifecycle

- **Draft** — editable but does not run.
- **Active** — receives new qualifying events.
- **Paused** — stops new work from being enrolled.
- **Archived** — retained for history and cannot be activated again.

## No-reply follow-up

This workflow finds threads where:

1. Konevo has recorded an outbound email;
2. the selected delay has elapsed; and
3. no inbound email is newer than that outbound email.

The configured delay is measured in whole days and is at least one day. The
background worker checks active no-reply workflows every minute; it does not
guarantee delivery at the exact second a thread becomes eligible.

### Modes

- **Needs approval** creates a follow-up draft. Review, edit, approve, and send
  it from the normal draft flow.
- **Automatic** prepares and sends the configured follow-up subject and body.
  It remains subject to Konevo's messaging safety checks and exclusions.

### Exclusions

The default exclusion list protects no-reply and notification-style senders:

```text
noreply@*
no-reply@*
donotreply@*
notification@*
*@calendar.google.com
```

One pattern may be placed on each line or separated with commas. `*` is a
wildcard and matching is case-insensitive. Add senders that should never receive
a follow-up.

## Email to task

This workflow runs for newly imported inbound emails. AI extracts potential task
titles, descriptions, priorities, and due dates from the email context.

- **Needs approval** places suggestions in **Automation → Task suggestions**.
  You can edit a suggestion before approving it; approval creates the real task.
- **Automatic** creates extracted tasks directly.

Konevo prevents the same source email from producing duplicate pending/approved
suggestions or source-email tasks. An email that already produced work is skipped
on later worker retries.

## AI email reply

This workflow always creates a draft for review; it never sends an AI reply
automatically. It only processes inbound emails received at or after the workflow
was activated, and it creates at most one reply draft per source email.

The draft text is plain, editable email content. Approving it keeps the draft
ready to send; review the final recipient, content, attachments, and timing before
sending.

## Approval queues and expiry

Task suggestions and AI email drafts live in separate approval queues. Each queue
is paginated in groups of 10.

The organisation setting **Approval retention** determines how long pending items
remain reviewable. The default is 7 days; the allowed range is 1–90 days. A
scheduled cleanup runs hourly and automatically rejects expired pending task
suggestions and email drafts. It does not delete already created tasks or sent
messages.

Set this in **Settings → Automation**. Use a shorter period to keep the queues
clear; use a longer period only when someone reliably reviews the queue.

## Operational timing

| Background job | Normal schedule |
| --- | --- |
| Gmail recent sync | Every 5 minutes |
| No-reply follow-up evaluation | Every minute |
| Pending-approval expiry | Hourly |
| Scheduled-email recovery | Every minute |
| Deleted-upload cleanup retry | Every 10 minutes |

Jobs can retry after transient failures. Treat these schedules as processing
cadence, not a real-time delivery guarantee.

## Safe testing

Use a dedicated test Gmail account and a test contact. Start with **Needs
approval**, confirm the item appears in the expected queue, then verify the final
message manually. Only enable automatic mode after checking sender exclusions,
suppression/consent settings, subject, body, and the chosen delay.
