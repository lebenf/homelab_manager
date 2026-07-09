# homelab_manager — tool repository (installer + templates)

<!-- Free text, ignored by the runner. This builds the TOOL repo only: the
installer (install.sh), parametrized templates, shared scripts, and the
canonical CLAUDE.md. It never contains a concrete STATE.md or a concrete
infra/core-compose.yml for one server — those are generated per server by
install.sh into a separate instance repo. See WORKFLOW.md for the fixed
two-repo model, placeholder convention (__TOKEN__), and ENGINE-resolution
convention referenced tersely by the tasks below. -->

## Install PyYAML validation dependency

Install PyYAML into the project's existing virtualenv so later tasks can
validate YAML files that are not Docker/Podman compose files (e.g.
`templates/traefik.yml.tmpl`).

- Run `.venv/bin/pip install pyyaml`.
- Create `requirements-dev.txt` at repo root containing exactly: `pyyaml`.

Verify with `.venv/bin/python -c "import yaml; print('ok')"` — it must
print `ok`.

## Create tool-repo skeleton, .gitignore and initialize git

If `.git` does not already exist, run `git init`.

Create these directories (add an empty `.gitkeep` file in any directory
that would otherwise be empty):
- `templates/app-scripts`
- `scripts`
- `tests`

Create `.gitignore` at the repo root containing exactly these lines:
```
.env
*.pyc
__pycache__/
```

Verify with `find templates scripts tests -type d | sort` (all three
directories above must be listed) and `test -f .gitignore && echo ok`.

## Write the repository validation harness

Create `tests/validate.sh`, the harness re-used by most later tasks. It
must:
- Start with `#!/usr/bin/env bash` and `set -uo pipefail` (NOT `-e`: it
  must keep checking remaining files after one failure).
- Declare `fail=0`.
- For every `*.sh` file in the repo (exclude `.venv/` and `.git/`), run
  `bash -n` on it; on error set `fail=1` but continue to the next file.
- For every file matching `*compose*.yml*` in the repo (this also matches
  `*.yml.tmpl` compose templates; exclude `.venv/`), run
  `"${CONTAINER_ENGINE:-podman}" compose -f <file> config --quiet`; on
  error set `fail=1` but continue.
- If `templates/traefik.yml.tmpl` exists, validate it with
  `.venv/bin/python -c "import yaml; yaml.safe_load(open('templates/traefik.yml.tmpl'))"`;
  on error set `fail=1`.
- End with `exit $fail`.

Make it executable (`chmod +x tests/validate.sh`).
Verify by running `bash tests/validate.sh; echo $?` — with the repo in its
current state (no scripts or templates yet) it must print `0`.

## Write the canonical CLAUDE.md

Create `CLAUDE.md` at the repo root. `install.sh` copies this file
verbatim into every instance repo it generates, so it must be entirely
server-agnostic. It contains the operating rules Claude Code follows when
later adding or modifying apps in an instance repo. Include these rules,
one bullet each:
- Never create a dedicated DB/cache service inside an app's own compose
  file; always use the shared `postgres`/`redis` from
  `infra/core-compose.yml` via `infra/scripts/new-db.sh` /
  `infra/scripts/new-redis-ns.sh`.
- Never invent credentials; generate them only through the dedicated
  scripts, or ask the user.
- Every publicly exposed service needs standard Traefik labels (router,
  entrypoint `websecure`, certresolver `le-prod`) and no directly published
  host ports unless strictly required.
- Every new service joins the existing `homelab_net` network; never create
  a new network without an explicit reason documented in `STATE.md`.
- After any structural change, propose an updated diff of `STATE.md` in the
  same change.
- Compose files must stay compatible with both `docker compose` and
  `podman compose`/`podman-compose`; flag explicitly any requested feature
  that isn't portable.
- Every new app gets the full set of lifecycle scripts, copied and adapted
  from `infra/templates/app-scripts/` — never rewritten from scratch.
- Never run `up -d` or apply changes automatically without explicit user
  confirmation on the generated diff.
- Never place secrets in `STATE.md`, `CLAUDE.md`, or any committed
  compose/`*.env.example` file.

Verify with `test -f CLAUDE.md && echo ok` — must print `ok`.

## Write core-compose.yml.tmpl with shared network and Postgres

Create `templates/core-compose.yml.tmpl` defining:
- A network named `homelab_net`, driver `bridge` (not external — this file
  is where it is created).
- A `postgres` service: image `postgres:16-alpine`, `container_name:
  postgres`, `restart: unless-stopped`, environment
  `POSTGRES_PASSWORD=${POSTGRES_ROOT_PASSWORD}`, a named volume
  `postgres_data:/var/lib/postgresql/data`, attached to `homelab_net`, no
  published ports.
- Declare the named volume `postgres_data` under the top-level `volumes:`
  key.

Note: `${POSTGRES_ROOT_PASSWORD}` is real Docker Compose variable
interpolation (resolved from the instance's `infra/.env` at run time) — do
not replace it with a `__TOKEN__` placeholder.

Verify with `bash tests/validate.sh; echo $?` — must print `0`.

## Add Redis and Traefik services to core-compose.yml.tmpl

Read `templates/core-compose.yml.tmpl` first, then add two services to it
(do not remove or rewrite the existing `postgres` service or the
`homelab_net` network):

- `redis`: image `redis:7-alpine`, `container_name: redis`,
  `restart: unless-stopped`, named volume `redis_data:/data`, attached to
  `homelab_net`, no published ports.
- `traefik`: image `traefik:v3.1`, `container_name: traefik`,
  `restart: unless-stopped`, attached to `homelab_net`, ports `80:80` and
  `443:443`, volumes:
  - `./traefik/traefik.yml:/etc/traefik/traefik.yml:ro`
  - `./traefik/acme.json:/acme.json`
  - `./traefik/acme-staging.json:/acme-staging.json`
  - `__CONTAINER_SOCKET__:/var/run/docker.sock:ro`

`__CONTAINER_SOCKET__` is a placeholder token (not compose variable
syntax): `install.sh` will replace it with the correct host socket path for
the chosen runtime at generation time.

Add the named volume `redis_data` under the top-level `volumes:` key
alongside `postgres_data`.

Verify with `bash tests/validate.sh; echo $?` — must print `0`.

## Write traefik.yml.tmpl

Create `templates/traefik.yml.tmpl` (Traefik v3 static configuration) with:
- `entryPoints`: `web` (port 80) redirecting to `websecure` via
  `http.redirections.entryPoint` (`to: websecure`, `scheme: https`), and
  `websecure` (port 443).
- `providers.docker`: `exposedByDefault: false` (Traefik reaches the socket
  mounted at `/var/run/docker.sock` inside its own container — see
  `templates/core-compose.yml.tmpl`).
- `certificatesResolvers`:
  - `le-staging`: ACME with `email: __ACME_EMAIL__`, `caServer:
    https://acme-staging-v02.api.letsencrypt.org/directory`,
    `httpChallenge.entryPoint: web`, `storage: /acme-staging.json`.
  - `le-prod`: ACME with `email: __ACME_EMAIL__`, the default production
    `caServer` (omit that key), `httpChallenge.entryPoint: web`,
    `storage: /acme.json`.

Verify with `bash tests/validate.sh; echo $?` — must print `0`.

## Write STATE.md.tmpl and env.tmpl

Create `templates/STATE.md.tmpl` — the per-server source of truth
`install.sh` renders into each instance's `STATE.md`. Include these
sections (level-2 headings):

`## Server` — `__SERVER_NAME__`.

`## Rete` — network name `homelab_net`, driver `bridge`, defined in
`infra/core-compose.yml`; every app compose file must declare it as
`external: true`.

`## Reverse proxy` — Traefik, discovery via the `docker` provider,
certresolvers `le-staging`/`le-prod`, base domain `__BASE_DOMAIN__`, app
domain convention `<app>.__BASE_DOMAIN__`.

`## Servizi condivisi` — `postgres` (Postgres 16, host `postgres`, port
`5432`, credentials via `infra/scripts/new-db.sh`, never in this file) and
`redis` (Redis 7, host `redis`, port `6379`, namespacing via
`infra/scripts/new-redis-ns.sh`).

`## Backup` — destinazione primaria: `__BACKUP_DESTINATION__`.

`## Runtime` — runtime in uso: `__CONTAINER_ENGINE__`.

`## App registrate` — add exactly this table header and marker (scripts
append rows after the marker; never remove it):
```
| Nome | Path | Dominio | DB dedicato | Backup |
|---|---|---|---|---|
<!-- APPS_TABLE_ROWS -->
```

Do not include any password, token, or secret anywhere in this template.

Also create `templates/env.tmpl` — rendered into each instance's
`infra/.env` (and copied as-is into `infra/.env.example`) — containing
exactly these two lines:
```
POSTGRES_ROOT_PASSWORD=__POSTGRES_ROOT_PASSWORD__
CONTAINER_ENGINE=__CONTAINER_ENGINE__
```

Verify with `test -f templates/STATE.md.tmpl && grep -q 'APPS_TABLE_ROWS' templates/STATE.md.tmpl && test -f templates/env.tmpl && echo ok`
— must print `ok`.

## Write scripts/new-db.sh

Create `scripts/new-db.sh`. Usage: `new-db.sh <app-name>`.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Resolve `ENGINE` using the sourcing convention from `WORKFLOW.md` (this
  script lives at `infra/scripts/new-db.sh` once copied into an instance,
  so it sources `../.env`).
- If no argument is given, print a usage message to stderr and `exit 1`.
- Idempotently create, inside the running `postgres` container, a role and
  database both named `<app-name>` if they don't already exist (check
  first via `"$ENGINE" exec -i postgres psql -U postgres -tAc "..."`
  against `pg_roles`/`pg_database`, only create when the check returns
  empty).
- On first creation only, generate a password with `openssl rand -hex 16`
  and set it on the role.
- Always print, as the last stdout line,
  `DATABASE_URL=postgresql://<app-name>:<password-or-(unchanged)>@postgres:5432/<app-name>`
  — print `(unchanged)` instead of a password when the db already existed.

Make it executable.
Verify: `bash -n scripts/new-db.sh && scripts/new-db.sh; echo $?` must
print `1` after a usage message (no Postgres container is running yet, so
only the no-argument path can be exercised here).

## Write scripts/new-redis-ns.sh

Create `scripts/new-redis-ns.sh`. Usage: `new-redis-ns.sh <app-name>`.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- If no argument is given, print a usage message to stderr and `exit 1`.
- No server-side action is needed (Redis needs no explicit namespace
  creation): simply print two lines to stdout:
  - `REDIS_URL=redis://redis:6379/0`
  - `REDIS_PREFIX=<app-name>:`

Make it executable.
Verify: `bash -n scripts/new-redis-ns.sh && scripts/new-redis-ns.sh myapp`
must print the two lines above with `myapp:` as the prefix, and exit `0`.

## Write scripts/register-app.sh

Read `templates/STATE.md.tmpl` first to see the exact `## App registrate`
table and the `<!-- APPS_TABLE_ROWS -->` marker. Create
`scripts/register-app.sh`. Usage:
`register-app.sh <app-name> <path> <domain> <db|nodb> <backup|nobackup>`.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Resolve `STATE_FILE="${STATE_FILE:-STATE.md}"` (defaults to the instance
  root `STATE.md`; overridable for testing).
- If fewer than 5 arguments are given, print usage to stderr and `exit 1`.
- Build the row `| <app-name> | <path> | <domain> | <db|nodb> | <backup|nobackup> |`.
- If a line starting with `| <app-name> |` already exists in `$STATE_FILE`,
  replace it in place; otherwise insert the new row immediately after the
  `<!-- APPS_TABLE_ROWS -->` marker line (use `sed`).

Make it executable.
Verify: render a throwaway test file first —
`sed -e 's/__SERVER_NAME__/test/' -e 's/__BASE_DOMAIN__/test.example/g' -e 's#__BACKUP_DESTINATION__#none#' -e 's/__CONTAINER_ENGINE__/podman/' templates/STATE.md.tmpl > /tmp/state-test.md`
— then run
`bash -n scripts/register-app.sh && STATE_FILE=/tmp/state-test.md scripts/register-app.sh demo apps/demo demo.test.example nodb backup && grep -q '| demo |' /tmp/state-test.md && echo ok`
must print `ok`. Finish with `rm -f /tmp/state-test.md`.

## Write scripts/backup.sh

Create `scripts/backup.sh`. Usage: `backup.sh [--app <name>]`.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Resolve `ENGINE` using the `WORKFLOW.md` sourcing convention (this script
  lives at `infra/scripts/backup.sh` once copied into an instance, so it
  sources `../.env`).
- Build the list of app directories to process: either just `apps/<name>`
  (if `--app <name>` is given and the directory exists — otherwise print an
  error to stderr and `exit 1`), or every directory under `apps/` when
  `--app` is omitted.
- For each app: skip it if its `docker-compose.yml` contains the string
  `homelab.backup=false`; otherwise, if `apps/<app>/.needs-db` exists, run
  `"$ENGINE" exec postgres pg_dump -U postgres <app>` into
  `infra/backup-staging/<app>.sql`, then run
  `restic backup "apps/<app>" infra/backup-staging` (repository/password
  expected already exported as `RESTIC_REPOSITORY`/`RESTIC_PASSWORD`, never
  hardcoded).

Make it executable.
Verify: `bash -n scripts/backup.sh && scripts/backup.sh --app does-not-exist; echo $?`
must print a non-zero exit code (the app directory doesn't exist).

## Write scripts/app.sh dispatcher

Create `scripts/app.sh`. Usage:
`app.sh <app-name> <install|update|backup-now|remove|start|stop|restart|status|logs> [extra args...]`.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- If fewer than 2 arguments are given, print usage to stderr and `exit 1`.
- If `apps/<app-name>/scripts/<action>.sh` does not exist, print an error
  to stderr and `exit 1`.
- Otherwise `exec` that script, forwarding any remaining arguments.

Make it executable.
Verify: `bash -n scripts/app.sh && scripts/app.sh nope status; echo $?`
must print a non-zero exit code (no such app yet).

## Write simple per-app lifecycle templates

Read `scripts/app.sh` first to see the `apps/<app>/scripts/<action>.sh`
convention it expects. In `templates/app-scripts/`, create five templates,
each `#!/usr/bin/env bash`, `set -euo pipefail`, resolving `ENGINE` via the
`WORKFLOW.md` sourcing convention (`../../../infra/.env`, since these live
at `apps/<app>/scripts/` once copied) and
`COMPOSE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker-compose.yml"`:
- `start.sh`: `"$ENGINE" compose -f "$COMPOSE_FILE" start`
- `stop.sh`: `"$ENGINE" compose -f "$COMPOSE_FILE" stop`
- `restart.sh`: `"$ENGINE" compose -f "$COMPOSE_FILE" restart`
- `status.sh`: `"$ENGINE" compose -f "$COMPOSE_FILE" ps`
- `logs.sh`: `"$ENGINE" compose -f "$COMPOSE_FILE" logs -f "$@"` (accepts an
  optional service name to filter)

Make all five executable.
Verify with `bash tests/validate.sh; echo $?` — must print `0`.

## Write install.sh per-app lifecycle template

Create `templates/app-scripts/install.sh` (copied and adapted per-app
later; keep the placeholder `__APP_NAME__` exactly where noted — Claude
Code replaces it when copying this template into a new app, `install.sh`
the installer never touches this placeholder).
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Resolve `ENGINE`/`COMPOSE_FILE` the same way as
  `templates/app-scripts/status.sh` (read it first).
- If the sibling file `../.needs-db` exists, run
  `../../../infra/scripts/new-db.sh __APP_NAME__` before starting the app.
- Run `"$ENGINE" compose -f "$COMPOSE_FILE" pull` then
  `"$ENGINE" compose -f "$COMPOSE_FILE" up -d --build`.
- Run `"$ENGINE" compose -f "$COMPOSE_FILE" ps` and `grep` its output for
  `Up`/`running`; if not found, print an error to stderr and `exit 1`.

Make it executable.
Verify with `bash tests/validate.sh; echo $?` — must print `0` (syntax-only
check: no containers actually run in this environment).

## Write update.sh per-app lifecycle template

Create `templates/app-scripts/update.sh`.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Resolve `ENGINE`/`COMPOSE_FILE` the same way as
  `templates/app-scripts/status.sh` (read it first).
- First run the sibling `./backup-now.sh` (never update without a fresh
  backup) — if it fails, `exit 1` before touching anything else.
- Then run `"$ENGINE" compose -f "$COMPOSE_FILE" pull` and
  `"$ENGINE" compose -f "$COMPOSE_FILE" up -d --build`.

Make it executable.
Verify with `bash -n templates/app-scripts/update.sh; echo $?` — must
print `0`.

## Write backup-now.sh per-app lifecycle template

Create `templates/app-scripts/backup-now.sh`. It must not duplicate backup
logic — it only wraps the shared script.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Resolve `APP_NAME` from the containing app directory name:
  `APP_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)")"`.
- From the repo root (three levels up from this script), run
  `infra/scripts/backup.sh --app "$APP_NAME"`.

Make it executable.
Verify with `bash -n templates/app-scripts/backup-now.sh; echo $?` — must
print `0`.

## Write remove.sh per-app lifecycle template

Create `templates/app-scripts/remove.sh`. This is destructive — it must
default to safe.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Resolve `ENGINE`/`COMPOSE_FILE` the same way as
  `templates/app-scripts/status.sh` (read it first).
- Accept an optional `--yes` flag; without it, prompt with `read -rp` for
  confirmation and abort (`exit 1`) on anything but `y`/`yes`.
- Run `"$ENGINE" compose -f "$COMPOSE_FILE" down`.
- Do not touch the database, volumes, or restic backups unless a
  `--with-data` flag is also given; if it is, additionally run
  `"$ENGINE" compose -f "$COMPOSE_FILE" down -v`.

Make it executable.
Verify: `bash -n templates/app-scripts/remove.sh && echo n | templates/app-scripts/remove.sh; echo $?`
must print a non-zero exit code (the confirmation prompt must abort on
`n`).

## Write install.sh: argument parsing and skeleton

Create `install.sh` at the repo root, the installer entrypoint. This task
only creates the skeleton — later tasks append to this same file.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- `TOOL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
- Declare defaults: `TARGET_DIR="$(pwd)"`, `RUNTIME=""`, `UPDATE_CORE=0`,
  `NON_INTERACTIVE=0`, `BASE_DOMAIN=""`, `ACME_EMAIL=""`, `SERVER_NAME=""`,
  `BACKUP_DEST=""`.
- Parse these flags in a `while [ $# -gt 0 ]; do case "$1" in ... esac;
  done` loop, each consuming its value and shifting 2 (or 1 for booleans):
  `--target-dir`, `--runtime`, `--update-core` (sets `UPDATE_CORE=1`,
  shift 1), `--non-interactive` (sets `NON_INTERACTIVE=1`, shift 1),
  `--base-domain`, `--acme-email`, `--server-name`, `--backup-dest`. Any
  other argument prints `Unknown option: $1` to stderr and exits 1.
- End the file with `echo "Target directory: $TARGET_DIR"`.

Make it executable.
Verify: `bash -n install.sh && ./install.sh --target-dir /tmp/x --runtime podman --non-interactive`
must print `Target directory: /tmp/x` and exit `0`.

## Write install.sh: prerequisite and port checks

Read `install.sh` first. Insert two functions right after the argument
parsing loop, and call them before the final `echo "Target directory: ..."`
line:
- `check_prerequisites`: if `RUNTIME` is empty, print
  `Missing --runtime (podman|docker)` to stderr and `exit 1`. Otherwise
  build a list of required binaries — `git`, `curl`, `"$RUNTIME"` — and for
  each one not found by `command -v`, collect it; if the collected list is
  non-empty, print `Missing required tools: <list>` to stderr and `exit 1`.
- `check_ports`: for ports 80 and 443, if `ss` is available and
  `ss -ltn "( sport = :$port )"` shows a `LISTEN` line, print
  `Port <port> is already in use.` to stderr and `exit 1`.

Call `check_prerequisites` then `check_ports` in that order.

Make sure it's still executable.
Verify: `bash -n install.sh && ./install.sh --target-dir /tmp/x --runtime podman --non-interactive; echo $?`
must exit `0` on this machine (git, curl and podman are already installed
and ports 80/443 are free).

## Write install.sh: interactive configuration prompts

Read `install.sh` first. Insert this logic right after the
`check_prerequisites`/`check_ports` calls, before the final `echo` line:
- An `ask "<prompt text>" VARNAME` helper that: returns immediately if
  `NON_INTERACTIVE` is `1`; returns immediately if the named variable is
  already non-empty (flags already set it); otherwise runs
  `read -rp "<prompt text>: " value` and assigns `value` into the named
  variable (use `eval` or a `case`/`printf -v` approach — either is fine as
  long as it works for a variable name given as a string argument).
- Call `ask` for `BASE_DOMAIN` ("Base domain (e.g. example.com)"),
  `ACME_EMAIL` ("Let's Encrypt account email"), `SERVER_NAME` ("Server
  name"), `BACKUP_DEST` ("Backup destination (leave empty to configure
  later)").
- After those calls: if `NON_INTERACTIVE` is `1` and any of `BASE_DOMAIN`,
  `ACME_EMAIL`, `SERVER_NAME` is still empty, print an error to stderr
  listing the missing `--base-domain`/`--acme-email`/`--server-name` flags
  and `exit 1`.
- If `BACKUP_DEST` is still empty, set it to `(non configurata)`.

Verify: `bash -n install.sh && timeout 5 ./install.sh --target-dir /tmp/x --runtime podman --non-interactive --base-domain d.example --acme-email a@b.example --server-name test1; echo $?`
must exit `0` without hanging (the `timeout 5` proves it never blocks on
`read` in non-interactive mode).

## Write install.sh: generate the instance repository

Read `install.sh` first, and also read `templates/core-compose.yml.tmpl`,
`templates/traefik.yml.tmpl`, `templates/STATE.md.tmpl` and
`templates/env.tmpl` to confirm their exact placeholder tokens. Insert this
generation logic right after the configuration-prompt block, replacing the
final placeholder `echo "Target directory: ..."` line:

- If `UPDATE_CORE` is `0` and `"$TARGET_DIR/STATE.md"` already exists,
  print an error to stderr (`STATE.md already exists in $TARGET_DIR —
  refusing to overwrite. Use --update-core to only refresh shared files.`)
  and `exit 1`.
- `mkdir -p` these directories under `$TARGET_DIR`: `infra/traefik`,
  `infra/scripts`, `infra/templates/app-scripts`, `apps`.
- Copy `CLAUDE.md`, every file in `scripts/`, and every file in
  `templates/app-scripts/` from `$TOOL_REPO_DIR` into the matching
  `$TARGET_DIR` paths, then `chmod +x` the copied scripts.
- If `UPDATE_CORE` is `1`, print a confirmation message and `exit 0` here
  (STATE.md, infra/core-compose.yml, infra/traefik/traefik.yml, infra/.env
  and apps/ must be left untouched by an update-core run).
- Compute `SOCKET_PATH`: `/run/user/$(id -u)/podman/podman.sock` if
  `RUNTIME` is `podman`, else `/var/run/docker.sock`.
- Render with `sed`, writing each result into `$TARGET_DIR`:
  `core-compose.yml.tmpl` → `infra/core-compose.yml` (substitute
  `__CONTAINER_SOCKET__`); `traefik.yml.tmpl` → `infra/traefik/traefik.yml`
  (substitute `__ACME_EMAIL__`); `STATE.md.tmpl` → `STATE.md` (substitute
  `__SERVER_NAME__`, `__BASE_DOMAIN__`, `__BACKUP_DESTINATION__`,
  `__CONTAINER_ENGINE__`); `env.tmpl` → `infra/.env` (substitute
  `__POSTGRES_ROOT_PASSWORD__` with `$(openssl rand -hex 16)` and
  `__CONTAINER_ENGINE__` with `$RUNTIME`).
- Copy `env.tmpl` as-is to `infra/.env.example`.
- Create empty `infra/traefik/acme.json` and `infra/traefik/acme-staging.json`,
  `chmod 600` both.
- Write `$TARGET_DIR/.gitignore` with: `.env`, `apps/*/.env`, `infra/.env`,
  `infra/traefik/acme.json`, `infra/traefik/acme-staging.json`.
- Print a summary ending with the manual next step:
  `cd $TARGET_DIR/infra && $RUNTIME compose -f core-compose.yml up -d`.

Verify: `bash -n install.sh` must succeed. Then run
`rm -rf /tmp/homelab-test-instance && ./install.sh --target-dir /tmp/homelab-test-instance --runtime podman --non-interactive --base-domain d.example --acme-email a@b.example --server-name test1`
and confirm with
`test -f /tmp/homelab-test-instance/STATE.md && test -f /tmp/homelab-test-instance/infra/core-compose.yml && ! grep -q '__' /tmp/homelab-test-instance/STATE.md && echo ok`
— must print `ok` (no leftover `__TOKEN__` placeholders). Finish with
`rm -rf /tmp/homelab-test-instance`.

## Write README.md

Create `README.md` at the repo root, documenting for a human operator:
- What this repository is: the reusable **tool repo** (installer +
  templates + shared scripts + canonical `CLAUDE.md`) for a file-based,
  declarative, Podman-first/Docker-compatible homelab — not a repo you
  deploy directly. Explain the tool-repo/instance-repo split from
  `WORKFLOW.md`.
- Usage: `./install.sh --target-dir <path> --runtime podman|docker
  [--base-domain <domain> --acme-email <email> --server-name <name>
  --backup-dest <dest>] [--non-interactive]`, run once per server to
  create its instance repo, then follow the printed manual next steps
  (review `infra/.env`, apply Podman rootless prerequisites — privileged
  port sysctl, `loginctl enable-linger` — if using Podman, then start the
  core services).
- `--update-core`: re-run against an existing instance directory to refresh
  `CLAUDE.md`, `infra/scripts/` and `infra/templates/app-scripts/` from
  this tool repo without touching that server's `STATE.md` or `apps/`.
- How to add a new app inside a generated instance (reference the
  instance's own `CLAUDE.md` and `infra/scripts/app.sh`).
- How to run this tool repo's own validation suite: `bash tests/validate.sh`.

Verify with `test -f README.md && grep -q 'tests/validate.sh' README.md && grep -q -- '--update-core' README.md && echo ok`
— must print `ok`.

## Write end-to-end integration test for install.sh

Create `tests/test-install-e2e.sh`, a script that exercises `install.sh`
for real against a disposable temporary directory (the only place in this
project allowed to do so) and cleans up after itself.
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- `TMP_DIR="$(mktemp -d)"`.
- Run: `"$(dirname "$0")/../install.sh" --target-dir "$TMP_DIR" --runtime podman --non-interactive --base-domain e2e.example --acme-email e2e@example.com --server-name e2e-test`.
- Assert with `test`/`grep` that `$TMP_DIR/STATE.md`,
  `$TMP_DIR/CLAUDE.md`, `$TMP_DIR/infra/core-compose.yml`,
  `$TMP_DIR/infra/traefik/traefik.yml`, `$TMP_DIR/infra/.env` all exist,
  and that no file under `$TMP_DIR` still contains the literal substring
  `__` (no leftover placeholder). On any failed assertion, print which one
  failed to stderr, remove `$TMP_DIR`, and `exit 1`.
- Re-run the same `install.sh` command with `--update-core` appended and
  assert `$TMP_DIR/STATE.md` still exists and is unchanged (compare against
  a copy saved before the re-run).
- `rm -rf "$TMP_DIR"` and `exit 0` on success.

Make it executable.
Verify: `bash -n tests/test-install-e2e.sh && bash tests/test-install-e2e.sh; echo $?`
must print `0`.

## Run final full validation pass

Run the complete validation suite end to end and confirm the tool repo is
internally consistent:
- `bash tests/validate.sh; echo $?` must print `0`.
- `bash tests/test-install-e2e.sh; echo $?` must print `0`.
- Confirm every core file exists:
  `test -f install.sh && test -f CLAUDE.md && test -f README.md && test -f templates/core-compose.yml.tmpl && test -f templates/traefik.yml.tmpl && test -f templates/STATE.md.tmpl && test -f templates/env.tmpl && test -f scripts/new-db.sh && test -f scripts/new-redis-ns.sh && test -f scripts/register-app.sh && test -f scripts/backup.sh && test -f scripts/app.sh && echo all-present`.
- Confirm every template in `templates/app-scripts/` is executable, and
  `install.sh` and every file in `scripts/` are executable:
  `find templates/app-scripts scripts -type f ! -perm -u+x` and
  `find install.sh ! -perm -u+x` must both print nothing.

If anything is missing or not executable, fix it directly, then re-run the
checks above. The task is complete only once all checks pass.
