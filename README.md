# korkban

A read-only Kanban-style dashboard for a JIRA project. 
Korkban polls JIRA on a schedule, stores a denormalized snapshot in SQLite, and renders a fast board view that highlights stale tickets.

## What you get

- Board grouped by Epic (columns), plus an optional "Unplanned" column for orphan tickets.
- Staleness highlighting: tickets get flagged "somewhat" and "really" stale after configurable day thresholds.
- Adaptive polling: tight tick interval while someone is actively viewing the board, long interval otherwise.
- Google OAuth login restricted to an allow-list of domains and/or individual emails.

## Quick start

```sh
git clone https://github.com/dutow/korkban.git korkban
cd korkban

cp .env.example .env                    # JIRA + Google OAuth secrets
cp config/korkban.example.yml config/korkban.yml   # board config

task dev                                # http://localhost:3000
```

That's it — `task dev` builds the dev image, boots the app, and brings up
a headless Chromium sidecar used by the system tests.

Sign in with a Google account whose email matches `auth.allowed_domains`
or `auth.allowed_emails` in `config/korkban.yml`.

## Configuration

Two files. Secrets go in `.env`, everything else in `config/korkban.yml`.

### `.env`

| Variable | Purpose |
|---|---|
| `JIRA_BASE_URL` | e.g. `https://acme.atlassian.net` |
| `JIRA_EMAIL` | JIRA account for the API token |
| `JIRA_API_TOKEN` | Generated at id.atlassian.com → Security |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | OAuth client from Google Cloud Console |
| `SECRET_KEY_BASE` | Rails secret (prod) |
| `RAILS_MASTER_KEY` | Contents of `config/master.key` (prod) |

### `config/korkban.yml`

See `config/korkban.example.yml` for a fully-commented sample. The
important sections:

- `auth.allowed_domains` / `auth.allowed_emails` — who can log in.
- `board.epic_query` — JQL that picks the epics shown as rows.
- `board.unplanned_query` — optional JQL for the leftmost "Unplanned"
  column (orphan tickets).
- `board.users` — JIRA usernames → display names for the swimlanes.
- `board.status_map` — collapse JIRA statuses into the board's
  `new` / `in_progress` / `review` / `done` columns.
- `board.staleness.somewhat_days` / `really_days` — day thresholds for
  the two staleness tiers.
- `polling.tick_seconds` / `active_window_minutes` / `idle_interval_minutes`
  — how often the sync job runs while the board is being watched vs.
  while it's idle.

## Development

```sh
task dev          # run the app on :3000 (rebuilds on changes)
task shell        # bash inside the dev container
task console      # rails console
task migrate      # run pending migrations
task lint         # RuboCop (matches CI lint job)
task lint:fix     # RuboCop with safe autocorrect
task test         # lint + full test suite (unit + system, Chromium sidecar)
task logs         # tail dev logs
```

The repo bind-mounts the working tree into the container, so edits in
your editor show up live. Bundled gems live in a named volume
(`bundle`) so they survive container rebuilds.

### Production

```sh
task redeploy        # (re)build, (re)start, run migrations
task prod-logs       # tail prod logs
```

### What's running

`docker-compose.prod.yml` brings up two containers:

- `app` — the Rails app (Puma + Solid Queue in-process), behind
  internal port 3000. Persistent state lives in `./storage` (SQLite
  databases for primary, queue, cache, cable).
- `caddy` — TLS terminator on 80/443, reverse-proxies to `app:3000`.
  Cert data persists in named volumes (`caddy_data`, `caddy_config`).

## Tests

```sh
task test
```

Runs Rails unit tests, then system tests through the `selenium/standalone-chromium`
sidecar defined in `docker-compose.yml`. WebMock stubs all JIRA traffic
so the suite never hits the real API.
