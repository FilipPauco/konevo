# Showcase screenshot data

Konevo can add a small set of fictional companies, contacts, inbox threads,
deals, and dated tasks to one workspace for screenshots. The calendar displays
the seeded tasks, deal follow-ups, and close targets automatically. It also
adds three paused workflow configurations, two pending task suggestions, and
two pending AI email drafts for the Automation approval screens.

The command is intentionally guarded and touches only the organization selected
by `KONEVO_SHOWCASE_ORG_SLUG`. It removes any earlier Konevo showcase records
before adding a fresh set. It never imports, sends, or changes Gmail data.

## Add screenshot data

Run this on the server after deploying a release that includes this feature:

```shell
cd /opt/konevo/app
sudo docker compose --env-file .env -f deploy/docker/compose.yaml \
  exec -e KONEVO_SHOWCASE_DATA=true -e KONEVO_SHOWCASE_ORG_SLUG=public \
  app bin/konevo eval 'IO.inspect(Konevo.Showcase.seed())'
```

`public` is the default workspace created for the initial owner. Change the
slug only if you intentionally want the screenshots in another workspace.

Refresh Inbox, Companies, Deals, Tasks, Calendar, and Automation after the
command finishes. The seeded workflows are paused, so they cannot process real
data or send messages.

## Remove screenshot data

After taking the screenshots, run:

```shell
cd /opt/konevo/app
sudo docker compose --env-file .env -f deploy/docker/compose.yaml \
  exec -e KONEVO_SHOWCASE_DATA=true -e KONEVO_SHOWCASE_ORG_SLUG=public \
  app bin/konevo eval 'IO.inspect(Konevo.Showcase.clear())'
```

Only records created by `Konevo.Showcase.seed/0` are removed.
