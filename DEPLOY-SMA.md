# DocuSeal deployment (`tester-env`)

Source-built environment for `docusealco/docuseal` **3.3.7**
(commit `0dac1abe842798633aac85ff975ec719c39e85dd`, latest stable GitHub
Release, published 2026-11-16; identical to `master` at pin time).

Fork: `https://github.com/sma-rl-dev/docuseal`, branch `tester-env-baseline`.
Deployment tooling lives at the fork root (`apps/docuseal/` in the corpus):
`tester-env`, `docker-compose.tester-env.yml`, `lib/tester_env/{seed.rb,verify.rb,sample-document.pdf}`,
`tester-env-seed.json`. Upstream files are unmodified: the compose overlay
builds upstream's own `Dockerfile`.

The corpus submodule `apps/docuseal` points at the tooling tip of
`tester-env-baseline`, a direct child of the pinned baseline commit; the
baseline itself is unchanged.

## Quick Start

```bash
./tester-env deploy    # build from source, start app, complete first-run /setup
./tester-env seed      # deterministic fixtures (users, folders, templates, submissions)
./tester-env verify    # /up + owner login + rendered seeded pages + 64 database checks
./tester-env status    # running state, URL, browser origin, health
./tester-env reset     # remove container + data volume (image kept)
./tester-env stop      # remove container, keep the data volume
./tester-env logs      # tail app logs
```

Every command accepts `--run-id <id>` and `--port <port>`. `scripts/rl-env` also
sets `IMAGE_TAG` (content-addressed image name), `PORT`, `RUN_ID` and
`TESTER_ENV_BROWSER_ORIGIN`. `IMAGE_TAG` names the image; `RUN_ID` only scopes
the compose project (`tester-env-docuseal[-<id>]`) and the data volume.

## Topology

| Service | Image | Notes |
| --- | --- | --- |
| `app` | built from source (upstream `Dockerfile`) | Rails 8.1 on Ruby 4.0.9, listens on `:3000`; migrations run at boot; embedded Redis (`127.0.0.1:16379`) and Sidekiq start as puma plugins |

One container, no sidecars: SQLite at `$WORKDIR/db.sqlite3`, Active Storage on
disk, `SECRET_KEY_BASE` generated once into `$WORKDIR/docuseal.env`. The named
volume `docuseal-data` is mounted at `/data/docuseal` (`WORKDIR`) and is the only
state `reset` removes.

Host port mapping: `${PORT} -> app:3000` (default 18091).

## Build layers (mutation cost)

Upstream `Dockerfile` is used unchanged:

1. `download` – wgets GoNoto fonts, DancingScript, the pinned fields-detection
   ONNX model and sha256-verified pdfium.
2. `webpack` – `yarn install` + `bin/shakapacker` over `package.json`,
   `config/webpack`, `app/javascript`, `app/views`.
3. `app` – `bundle install` (native gems: ruby-vips, onnxruntime, nokogiri…),
   copies `app/config/db/migrate/lib/public/tmp`, precompiles bootsnap.

Measured on this host:

| Step | Time |
| --- | --- |
| Cold build (`docker build` all three stages) | 2m23s |
| `app/views/**` edit → rebuild (webpack reruns, yarn/bundle cached) | 52s |
| Controller/model edit → rebuild | ~a few seconds (webpack stage skipped) |
| No-change rebuild | 1.8s |
| Reset → deploy → verify | 7.5s (image cached) |
| Image size | 520 MB |

Implication: view edits cost ~52s, Ruby-only edits much less; only
`Gemfile`/`package.json` changes force a full dependency rebuild.

## URLs

- Local: `http://127.0.0.1:<port>/`
- Browser-visible origin: `http://<bridge-gateway>:<port>/` — on this host
  `http://172.16.0.1:18091/` for a manual run on port 18091.
  `deploy` posts `TESTER_ENV_BROWSER_ORIGIN` (or explicit `APP_URL`) as the
  `APP_URL` EncryptedConfig at first-run setup, so signing links and redirects
  stay reachable from the runner browser container.
- `host.docker.internal` does **not** resolve from bridge containers on this
  host; use the bridge gateway.

Verified without a browser: from a throwaway `curlimages/curl` container on the
default bridge, `GET http://172.16.0.1:18091/up` → 200 and `GET /setup` → 302.

## Credentials

| User | Password | Notes |
| --- | --- | --- |
| `admin@tester-env.local` | `TesterEnv123!` | owner of account `Tester Env` (created by `deploy`) |
| `marco.silva@tester-env.local` | `TesterEnv123!` | seeded admin, author in Sales Contracts |
| `priya.raman@tester-env.local` | `TesterEnv123!` | seeded admin, author in HR Onboarding |
| `dana.okafor@tester-env.local` | `TesterEnv123!` | seeded admin |

First run is deterministic: with no user, every request redirects to `/setup`;
`deploy` POSTs the form (`user[first_name]`, `user[last_name]`, `user[email]`,
`user[password]`, `account[name]`, `account[timezone]`, `account[locale]`,
`encrypted_config[value]` = `APP_URL`) and gets a 302.
`SetupController#ensure_first_user_not_created!` blocks setup forever once a
user exists, so a re-deploy keeps existing data. Override with `ADMIN_EMAIL`,
`ADMIN_PASSWORD`, `ADMIN_FIRST_NAME`, `ADMIN_LAST_NAME`, `ACCOUNT_NAME`,
`ACCOUNT_TIMEZONE`, `ACCOUNT_LOCALE`.

Email is not configured (`letter_opener_web` is development-only), so
invitations/resends cannot be used as oracles.

## Fixture data (`./tester-env seed`)

Upstream ships no `db/seeds.rb` or seed task (`spec/factories` are dev/test
only). `lib/tester_env/seed.rb` mirrors `spec/factories/templates.rb` with
production code: `ActiveStorage::Blob.create_and_upload!` →
`Pdfium::Document.open_io` → `Templates::ProcessDocument` →
`template.schema/fields`. `./tester-env seed` runs
`bin/rails runner 'TesterEnv::Seed.run!'` inside the app container. Every
visible timestamp is pinned; entities are looked up before creation, so a
re-seed converges instead of duplicating. `tester-env-seed.json` is the static
requirement manifest.

| Surface | Seeded state |
| --- | --- |
| Users | owner (Tester Env) + 3 admins: Marco Silva, Priya Raman, Dana Okafor |
| Folders | `Sales Contracts`, `HR Onboarding` (+ pinned `Default`) |
| Templates | 6, each with one processed PDF: Consulting Services Agreement, Mutual NDA, Statement of Work (Default); Software License Agreement, Data Processing Addendum (Sales Contracts); Employment Offer Letter (HR Onboarding) |
| Fields | required text/date/number/checkbox/select fields bound to both parties on every template |
| Submissions | 8 (7 active + 1 archived), 14 submitters, fixed dates 2026-09-24 .. 2026-11-10 |
| Statuses | completed 2, declined 1, expired 1, plus sent / opened / partially_completed mixes |
| Declined | Data Processing Addendum — Cobalt Freight, Sofia Marchetti declined 2026-10-22 with reason `Budget sign-off moved to the next fiscal quarter.` |
| Completed values | e.g. Brightpath Health LLC / Olivia Bennett / 2026-10-03, Meridian Logistics Inc. / 250 seats |
| Archived | Mutual NDA — Halcyon Studio, archived 2026-11-05, so the dashboard lists 7 rows and `/submissions/archived` exactly 1 |

`./tester-env verify` asserts `/up`, owner sign-in via `/api/user`, the rendered
dashboard/folder cards/submission rows, every `/submissions/:id` answering 200,
the declined reason text, then `lib/tester_env/verify.rb` (64 database checks).

Browser-visible assertions for the smoke run (all on seeded data):

1. Sign in as `admin@tester-env.local` → dashboard shows the 6 template cards,
   the `Sales Contracts` / `HR Onboarding` folder cards and the submission count.
2. `/submissions` lists 7 rows with mixed status badges; `/submissions/archived`
   lists the single Halcyon Studio NDA.
3. `/submissions/1..8` all open; every completed row renders its values.
4. `/submissions/5` (Cobalt Freight DPA) renders
   `Reason: Budget sign-off moved to the next fiscal quarter.` under the
   declined recipient.
5. A folder page lists its templates; `/settings/users` lists the 4 users.

## Reset

`./tester-env reset` runs project-scoped `docker compose down -v --remove-orphans`
plus `docker volume rm docuseal-data`, dropping SQLite, Active Storage files and
`docuseal.env` (so `SECRET_KEY_BASE` is regenerated). The image is kept
(content-addressed tags are shared). The next `deploy` re-runs all migrations on
an empty database and recreates the owner; the next `seed` recreates the
fixtures. No direct `docker rm`/`stop`/`rmi`/`prune` is used, and
`alevern/chromium-browser` / `chromium-ls*` are never touched.

Determinism check: a canonical dump (users, folders, templates with
dates/fields/options/document metadata, submissions with status dates/archived/
expire/slug, submitters, decline events) hashed to
`sha256 b9e2f1daac6a2ac2649bc684b681f21075e5a9401aeed0985245ac8d51a3a3dd`
across two independent reset → deploy → seed cycles, and a re-seed on a live
stack converged to the same hash (deploy-created owner excluded).

## Caveats

1. `search_entries` full-text search is PostgreSQL-only. On the default SQLite
   stack the `q` filters degrade to case-insensitive `LIKE` on names; add a
   `postgres:18` service to the overlay if a full-text oracle is needed.
2. Sidekiq runs embedded in puma, so email/webhook jobs are asynchronous: assert
   on async status with polling, not synchronously.
3. Email is unconfigured; invites, resends and reminders are not oracles.
4. Pro-licensed features (bulk send, formulas/conditional fields, automated
   reminders, SMS/identity verification, SSO/SAML, white-label, embedded
   builder) must not be used as scenario oracles.
5. License is AGPLv3 with Section 7(b) additional terms requiring the DocuSeal
   attribution to stay visible; do not mutate it away.
6. `APP_URL` is stored at first-run setup. Changing the browser origin requires
   `reset` + `deploy`; a plain `start` reuses the stored value.
7. `deploy` leaves a healthy stack running; `stop` removes containers but keeps
   the volume; `reset` is the clean-slate path.
