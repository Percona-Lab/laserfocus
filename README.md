# laserfocus

A read-only Kanban-style dashboard for a JIRA project. 
LaserFocus polls JIRA on a schedule, stores a denormalized snapshot in SQLite, and renders a fast board view that highlights stale tickets.

## What you get

- Board grouped by Epic (columns), plus an optional "Unplanned" column for orphan tickets.
- Collapsible columns: fold a column into a narrow strip showing just the name and the new / in progress / done counts (plus a dot when something in progress is stale). Collapse state is shared by everyone, like column order, and adjacent collapsed columns stack in one slot. `/?expand_all=1` shows everything expanded without touching the stored state.
- Roadmap alignment: reads the Jira Product Discovery project and shows, in one line above the board, how many "Now" commitments actually have a column. An epic behind a "Now" item joins the board even without the `Priority` label, and columns are tagged with the roadmap item, the `Ongoing` lane, or a "nothing started" flag.
- A `/community` view: the board for epics carrying the community label. Those epics move there: they no longer show on the main board, and neither do the roadmap "Now" items that deliver into them.
- A `/next` view: the roadmap's "Next" items as columns, ranked left to right. The cards are the readiness steps (delivery ticket, epic on the board, tickets under it, committed): met ones fade back, the first open one says what to do in Jira. Board, Community and Next share the same header tabs.
- A `/reviews` view: open, ready-for-review PRs (drafts left out) across the GitHub repos in `reviews.repos`, as columns by who they wait on: Needs review, In discussion, Changes requested, Approved. Cards carry the same age chip, stale paper and right-click snooze as tickets, plus CI state, size, Jira keys from the title or branch, and a 🌱 tag for contributors outside the org. A PR open for `reviews.decision_days` (default 30) is flagged "decision needed": merge it, close it, or snooze it with the reason it stays open. Filters for repo, community and search (right-click a repo in the Repo filter to exclude it from your own Reviews and Issues views, red tab counts included; it moves to an "Excluded" section at the bottom, and right-clicking it includes it again. Saved per signed-in user, nobody else's view changes), a People filter (wrote it, replied, asked to review, "My team", "No reply yet"), plus "Needs me" / "Mine". People are matched to `board.users` by the name on their GitHub profile, so the team shows with its Jira names. The Reviews tab shows a red count of critical PRs on every view. LaserFocus only reads from GitHub.
- An `/issues` view: the open GitHub issues of the same repos, as columns by who has the ball: New (nobody on the team has replied), Waiting on us (someone outside spoke after the team), Waiting on reporter (the team had the last word) and Team backlog (filed by the team). "The team" is anyone GitHub calls a member or collaborator of the org, or who is in `board.users`. Each column has its own clock, so a quiet reporter goes stale slowly and a waiting user quickly. Same age chip, snooze, "decision needed" (default after 90 days), filters and People menu (opened it, commented, assigned) as Reviews; "Needs me" is what is assigned to you and waiting on the team. The Issues tab's red count is what is critical on the team.
- Staleness highlighting: tickets get flagged "somewhat" and "really" stale after configurable day thresholds.
- Stale snooze: right-click a stale card to snooze it, with an optional reason, when it is stuck for a good reason. For `board.staleness.snooze_days` (default 7) it shows as fresh with a moon on its age, and drops out of the stale counts. Anyone on the board sees who snoozed it and why in the tooltip, and can lift the snooze from the same menu. The snooze ends early when the ticket changes status.
- Adaptive polling: tight tick interval while someone is actively viewing the board, long interval otherwise.
- Google OAuth login restricted to an allow-list of domains and/or individual emails.

## Quick start

```sh
git clone https://github.com/dutow/laserfocus.git laserfocus
cd laserfocus

cp .env.example .env                    # JIRA + Google OAuth secrets
cp config/laserfocus.example.yml config/laserfocus.yml   # board config

task dev                                # http://localhost:3000
```

That's it — `task dev` builds the dev image, boots the app, and brings up
a headless Chromium sidecar used by the system tests.

Sign in with a Google account whose email matches `auth.allowed_domains`
or `auth.allowed_emails` in `config/laserfocus.yml`.

## Configuration

Two files. Secrets go in `.env`, everything else in `config/laserfocus.yml`.

### `.env`

| Variable | Purpose |
|---|---|
| `JIRA_BASE_URL` | e.g. `https://acme.atlassian.net` |
| `JIRA_EMAIL` | JIRA account for the API token |
| `JIRA_API_TOKEN` | Generated at id.atlassian.com → Security |
| `GITHUB_TOKEN` | Optional, for the Reviews view. A read-only token (fine-grained with public read access, or classic with no scopes for public repos) |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | OAuth client from Google Cloud Console |
| `SECRET_KEY_BASE` | Rails secret (prod) |
| `RAILS_MASTER_KEY` | Contents of `config/master.key` (prod) |

### `config/laserfocus.yml`

See `config/laserfocus.example.yml` for a fully-commented sample. The
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
- `board.staleness.snooze_days` — how long a snoozed stale ticket stays
  out of the highlight (default 7).
- `board.staleness.lead_minutes` — the day thresholds above fire this many
  minutes early (default 60), so a ticket moved or snoozed during the daily
  standup is flagged again by the start of the same standup days later.
- `board.ongoing_label` — epics with this label are continuous work and get
  their own lane instead of being flagged as stalled.
- `board.community_label` — epics with this label (on top of `Priority`) move
  from the main board to the Community view. `ongoing_label` also takes a list,
  e.g. `["Ongoing", "Community"]`, when community epics never finish.
- `discovery.*` — optional Jira Product Discovery roadmap. `now_query` /
  `next_query` are JQL over the ideas project; `horizon_field`,
  `incubator_field` and `rank_field` are the custom field ids on an idea, and
  `delivery_link_type_id` is the issue link type JPD uses for delivery
  tickets. Leave the section out to switch the roadmap features off.
- `reviews.*` — optional Reviews view. `repos` lists the GitHub repos
  (`owner/name`); `exclude_authors` hides bots; `staleness` (default 3 / 7
  days) is the clock while a PR waits on reviewers or a merge,
  `author_staleness` (default 7 / 14) while it waits on its author;
  `decision_days` (default 30) flags long-open PRs. GitHub logins are linked
  to `board.users` by the name on the GitHub profile; give an entry a
  `github:` login only where that name differs from `display_name`. The
  People menu lists team members it could not link. GitHub is synced on the same tick as Jira, and a GitHub failure
  never blocks the Jira sync. Leave the section out to switch the view off.
- `issues.*` — optional; the Issues view is on whenever `reviews` is set up
  and uses its repos and `exclude_authors` unless it lists its own.
  `staleness.team` (default 3 / 7 days), `staleness.reporter` (14 / 30) and
  `staleness.backlog` (30 / 90) set each column's clock; `decision_days`
  (default 90) flags long-open issues. `issues: false` switches it off.
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
