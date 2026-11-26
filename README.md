# laserfocus

One screen that shows what your team is actually working on, and what is stuck.

LaserFocus brings together the team's **Jira** board, the **Jira Product
Discovery** roadmap, and the open **GitHub** pull requests and issues. It
flags anything that has waited too long, so stalled tickets, unreviewed PRs and
unanswered issues surface in standup and don't sit unnoticed.

It is **read-only**: it polls Jira and GitHub on a schedule, keeps a snapshot
in SQLite, and never writes back to either. Sign-in is Google OAuth, limited
to an allow-list.

## Views

| Tab | What it shows | Source |
|---|---|---|
| **Board** | Priority epics as columns, their tickets grouped by status | Jira |
| **Community** | The same board for community-labelled epics | Jira |
| **Next** | Roadmap "Next" items and how ready each one is to start | Jira Product Discovery |
| **Reviews** | Open PRs, grouped by who they are waiting on | GitHub |
| **Issues** | Open issues, grouped by who has the ball | GitHub |

All tabs share one header, so the tabs stay in the same spot on every view.
The Reviews and Issues tabs show a red count of critical items wherever you are,
even on the board. A **Goal history** page (`/history`) lists every day an epic
joined or left the board.

### Board

- **Epics as columns**, chosen by your JQL (e.g. everything labelled
  `Priority`), plus an optional **Unplanned** column for tickets with no tracked
  epic. Freshly created tickets carry a **NEW** badge for a few days.
- **Three ways to group** a column's tickets: *Staleness* (status groups ordered
  by their most stale ticket), *Status order* (your configured order), or
  *Unified* (one In Progress section, most stale first). Each browser remembers
  its own choice.
- **Drag columns** to reorder them, and **collapse** a column into a narrow strip
  that shows its name and new / in progress / done counts, plus a dot if
  something in progress is stale. Neighbouring collapsed columns stack into one
  slot. Order and collapse state are shared by everyone. `/?expand_all=1`
  expands everything without changing the stored state.
- **Search, status filter and People filter** across all tickets. Hover a card
  for details; cards show the PRs linked in Jira's development panel.
- **Ongoing lane**: epics labelled as continuous work (upstream, community) get
  their own lane instead of being flagged as stalled.
- **Roadmap line** (with Discovery set up): one line above the board says how
  many roadmap "Now" commitments actually have a column. An epic that delivers a
  Now item joins the board even without the `Priority` label, and columns are
  tagged with their roadmap item, the Ongoing lane, or a "nothing started" flag.
  Click the line to see the details.

### Community

The board view for epics carrying the community label. They move here: they no
longer show on the main board, and neither do the roadmap Now items that deliver
into them.

### Next

The roadmap's "Next" items as columns, ranked left to right. The cards are the
readiness steps: delivery ticket, epic on the board, tickets under it,
committed. Steps already met fade back, and the first open one tells you what to
do in Jira.

### Reviews

Open, ready-for-review PRs (drafts are left out) across the repos in
`reviews.repos`, in four columns: **Needs review**, **In discussion**, **Changes
requested**, **Approved**.

- Each card shows how long the PR has waited, CI state, size, Jira keys from its
  title or branch, and a 🌱 tag for contributors outside the org.
- The waiting clock follows whoever has the ball: reviewers and mergers get a
  short clock, the author a longer one.
- A PR open for `decision_days` (default 30) is flagged **decision needed**:
  merge it, close it, or snooze it with the reason it stays open.
- **Filters**: repo, community only, search, and a **People** menu (wrote it,
  replied, asked to review, *My team*, *No reply yet*), plus the **Needs me**
  and **Mine** scopes for the signed-in viewer. Filters live in the URL, so a
  filtered view can be shared as a link.
- **Exclude repos from your own view**: right-click a repo in the Repo filter
  and choose *Exclude from my view*. Its PRs and issues disappear from your
  Reviews and Issues views, its row moves to an *Excluded* section at the bottom
  of the list, and the red tab counts leave it out. Right-click it again to
  bring it back. This is saved per signed-in user and nobody else's view
  changes.
- People are matched to `board.users` by the name on their GitHub profile, so
  your team shows up with the names they have in Jira.

### Issues

The open GitHub issues in the same repos, grouped by who has the ball: **New**
(nobody on the team has replied), **Waiting on us** (someone outside spoke after
the team), **Waiting on reporter** (the team had the last word) and **Team
backlog** (filed by the team). "The team" is anyone GitHub lists as a member or
collaborator of the org, or anyone in `board.users`.

Each column has its own clock, so a quiet reporter goes stale slowly while a
user waiting on the team goes stale quickly. Age chips, snooze, *decision needed*
(default after 90 days), filters, repo exclusion and the People menu (opened it,
commented, assigned) work as on Reviews. *Needs me* means assigned to you and
waiting on the team.

## Across every view

- **Staleness**: tickets, PRs and issues are flagged *stale*, then *critical*,
  after a configurable number of days. The thresholds fire an hour early by
  default, so something looked at during the daily standup is flagged again by
  the start of that same standup days later.
- **Snooze**: right-click a stale card to snooze it, with an optional reason,
  when it is stuck for a good reason. For `snooze_days` (default 7) it shows as
  fresh, with a moon on its age, and drops out of the stale counts. Everyone sees
  who snoozed it and why, and anyone can lift it. The snooze ends early when the
  ticket changes status, or the PR/issue moves on.
- **Live updates**: pages refresh in place (Turbo morph) when new data arrives,
  keeping your filters, scroll position and open menus.
- **Adaptive polling**: a fast sync interval while someone is looking at the
  page, a slow one when nobody is.
- **Dark / light theme** and a **compact** density toggle, remembered per
  browser.

## Quick start

```sh
git clone https://github.com/Percona-Lab/laserfocus.git laserfocus
cd laserfocus

cp .env.example .env                    # Jira, GitHub and Google OAuth secrets
cp config/laserfocus.example.yml config/laserfocus.yml   # board config

task dev                                # http://localhost:3000
```

`task dev` builds the dev image, boots the app, and starts a headless Chromium
sidecar for the system tests.

Sign in with a Google account whose email matches `auth.allowed_domains` or
`auth.allowed_emails` in `config/laserfocus.yml`.

Only Jira is required. Leave `discovery`, `reviews` or `issues` out of the
config and the roadmap line, Next, Reviews or Issues switch off along with their
tabs.

## Configuration

Two files. Secrets go in `.env`, everything else in `config/laserfocus.yml`.

### `.env`

| Variable | Purpose |
|---|---|
| `JIRA_BASE_URL` | e.g. `https://acme.atlassian.net` |
| `JIRA_EMAIL` | Jira account for the API token |
| `JIRA_API_TOKEN` | Generated at id.atlassian.com → Security |
| `GITHUB_TOKEN` | For Reviews and Issues. A read-only token: fine-grained with public read access, or classic with no scopes for public repos |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | OAuth client from Google Cloud Console |
| `SECRET_KEY_BASE` | Rails secret (prod) |
| `RAILS_MASTER_KEY` | Contents of `config/master.key` (prod) |

### `config/laserfocus.yml`

`config/laserfocus.example.yml` is a fully commented sample. Here is an overview
of the sections.

**`auth`**: who can sign in.
- `allowed_domains` / `allowed_emails`

**`polling`**: how often the sync runs.
- `tick_seconds`, `active_window_minutes`, `idle_interval_minutes`: a tight tick
  while someone viewed the page in the last few minutes, a long interval
  otherwise. Jira and GitHub sync on the same tick; a GitHub failure never
  blocks the Jira sync.

**`board`**: the Jira board.
- `epic_query`: JQL for the epics shown as columns.
- `unplanned_query`: optional JQL for the leftmost Unplanned column (tickets
  with no tracked epic). `new_unplanned_query` / `new_unplanned_days` add
  freshly created tickets there with a NEW badge.
- `closed_epics_query`: optional, used by `task discover-closed-epics` to
  backfill goal history.
- `users`: Jira usernames → display names. Add `github:` where a GitHub profile
  name differs from `display_name`, and `email:` where a Google account name
  differs from it.
- `status_map`: collapses Jira statuses into `new` / `in_progress` / `review` /
  `done`. `new_statuses` and `done_statuses` say which ones count as not
  started and finished.
- `staleness.somewhat_days` / `really_days`: the two staleness tiers.
  `snooze_days` (default 7) is how long a snooze lasts, and `lead_minutes`
  (default 60) makes all thresholds fire that much early.
  `ignore_staleness_for_new_issues` skips not-started tickets.
- `ongoing_label`: epics with this label are continuous work and get their own
  lane. Also takes a list, e.g. `["Ongoing", "Community"]`.
- `community_label`: epics with this label (on top of `Priority`) move to the
  Community view.

**`discovery`**: optional Jira Product Discovery roadmap, for the roadmap line
and the Next view.
- `now_query` / `next_query`: JQL over the ideas project.
- `horizon_field`, `incubator_field`, `rank_field`: custom field ids on an idea.
- `delivery_link_type_id`: the issue link type JPD uses for delivery tickets.

**`reviews`**: optional Reviews view.
- `repos`: GitHub repos as `owner/name`.
- `exclude_authors`: e.g. dependency bots.
- `staleness` (default 3 / 7 days): the clock while a PR waits on reviewers or a
  merge. `author_staleness` (default 7 / 14) is the clock while it waits on its
  author.
- `decision_days` (default 30).

**`issues`**: the Issues view, on whenever `reviews` is set up. It uses the
reviews repos and `exclude_authors` unless it lists its own.
- `staleness.team` (default 3 / 7 days), `staleness.reporter` (14 / 30),
  `staleness.backlog` (30 / 90): each column's clock.
- `decision_days` (default 90).
- `issues: false` switches the view off.

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

The working tree is bind-mounted into the container, so edits show up live.
Bundled gems live in a named volume (`bundle`) and survive container rebuilds.

One-off maintenance:

```sh
task backfill-history       # backfill goal history timestamps from Jira's changelog
task discover-closed-epics  # find epics closed before LaserFocus tracked them
```

### Production

```sh
task redeploy        # rebuild and restart; migrations run on boot
task prod-logs       # tail prod logs
```

`docker-compose.prod.yml` brings up two containers:

- `app`: the Rails app (Puma with Solid Queue in-process) on internal port
  3000. Persistent state lives in `./storage` (SQLite databases for primary,
  queue, cache and cable).
- `caddy`: TLS terminator on 80/443, reverse-proxying to `app:3000`. Cert data
  persists in named volumes (`caddy_data`, `caddy_config`).

## Tests

```sh
task test
```

Runs RuboCop, the Rails unit tests, then system tests through the
`selenium/standalone-chromium` sidecar in `docker-compose.yml`. WebMock stubs
all Jira and GitHub traffic, so the suite never calls the real APIs.
