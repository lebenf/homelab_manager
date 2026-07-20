#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
INSTALL_SH="$(dirname "$0")/../install.sh"

fail() {
  echo "e2e FAILED: $1" >&2
  rm -rf "$TMP_DIR"
  exit 1
}

"$INSTALL_SH" --target-dir "$TMP_DIR" --runtime podman --non-interactive \
  --base-domain e2e.example --acme-email e2e@example.com --server-name e2e-test \
  || fail "install.sh (first run) exited non-zero"

test -f "$TMP_DIR/STATE.md" || fail "STATE.md missing"
test -f "$TMP_DIR/CLAUDE.md" || fail "CLAUDE.md missing"
test -f "$TMP_DIR/infra/core-compose.yml" || fail "infra/core-compose.yml missing"
test -f "$TMP_DIR/infra/traefik/traefik.yml" || fail "infra/traefik/traefik.yml missing"
test -f "$TMP_DIR/infra/.env" || fail "infra/.env missing"

if grep -rl '__' "$TMP_DIR" >/dev/null 2>&1; then
  if grep -rl '__' "$TMP_DIR" | grep -v -E '(app-scripts/.*\.tmpl$|\.env\.example$)' >/dev/null 2>&1; then
    fail "leftover __TOKEN__ placeholder found outside app-scripts templates / .env.example"
  fi
fi

cp "$TMP_DIR/STATE.md" "$TMP_DIR/../STATE.md.before.$$"

"$INSTALL_SH" --target-dir "$TMP_DIR" --runtime podman --update-core --non-interactive \
  || fail "install.sh (--update-core) exited non-zero"

test -f "$TMP_DIR/STATE.md" || fail "STATE.md missing after --update-core"
diff -q "$TMP_DIR/../STATE.md.before.$$" "$TMP_DIR/STATE.md" >/dev/null \
  || fail "STATE.md changed by --update-core"

rm -f "$TMP_DIR/../STATE.md.before.$$"
rm -rf "$TMP_DIR"
exit 0
