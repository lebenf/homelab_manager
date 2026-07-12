#!/usr/bin/env bash
set -euo pipefail

TOOL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
TARGET_DIR="$(pwd)"
RUNTIME=""
UPDATE_CORE=0
NON_INTERACTIVE=0
BASE_DOMAIN=""
ACME_EMAIL=""
SERVER_NAME=""
BACKUP_DEST=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --target-dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --runtime)
      RUNTIME="$2"
      shift 2
      ;;
    --update-core)
      UPDATE_CORE=1
      shift 1
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift 1
      ;;
    --base-domain)
      BASE_DOMAIN="$2"
      shift 2
      ;;
    --acme-email)
      ACME_EMAIL="$2"
      shift 2
      ;;
    --server-name)
      SERVER_NAME="$2"
      shift 2
      ;;
    --backup-dest)
      BACKUP_DEST="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Check prerequisites
check_prerequisites() {
  if [ -z "$RUNTIME" ]; then
    echo "Missing --runtime (podman|docker)" >&2
    exit 1
  fi

  local missing_tools=()
  for tool in git curl "$RUNTIME"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done

  if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "Missing required tools: ${missing_tools[*]}" >&2
    exit 1
  fi
}

# Check ports
check_ports() {
  for port in 80 443; do
    if command -v ss >/dev/null 2>&1; then
      if ss -ltn 2>/dev/null | grep -qE "LISTEN.*:$port([^0-9]|$)"; then
        echo "Port $port is already in use." >&2
        exit 1
      fi
    fi
  done
}

# Run checks
check_prerequisites
check_ports

# Interactive configuration helper
ask() {
  local prompt="$1"
  local varname="$2"

  # Return immediately if non-interactive or variable already set
  [ "$NON_INTERACTIVE" = "1" ] && return 0

  [ -n "${!varname:-}" ] && return 0

  # Read from stdin
  read -rp "$prompt: " value
  eval "$varname=\$value"
}

# Prompt for required configuration values
ask "Base domain (e.g. example.com)" BASE_DOMAIN
ask "Let's Encrypt account email" ACME_EMAIL
ask "Server name" SERVER_NAME
ask "Backup destination (leave empty to configure later)" BACKUP_DEST

# Validate required fields in non-interactive mode (not needed for --update-core,
# which never touches STATE.md/core-compose.yml)
if [ "$NON_INTERACTIVE" = "1" ] && [ "$UPDATE_CORE" = "0" ]; then
  missing_flags=()
  if [ -z "$BASE_DOMAIN" ]; then
    missing_flags+=("--base-domain")
  fi
  if [ -z "$ACME_EMAIL" ]; then
    missing_flags+=("--acme-email")
  fi
  if [ -z "$SERVER_NAME" ]; then
    missing_flags+=("--server-name")
  fi

  if [ ${#missing_flags[@]} -gt 0 ]; then
    echo "Missing required flags in non-interactive mode: ${missing_flags[*]}" >&2
    exit 1
  fi
fi

# Default backup destination if empty
if [ -z "$BACKUP_DEST" ]; then
  BACKUP_DEST="(non configurata)"
fi

# Generate the instance repository
if [ "$UPDATE_CORE" = "0" ] && [ -f "$TARGET_DIR/STATE.md" ]; then
  echo "STATE.md already exists in $TARGET_DIR — refusing to overwrite. Use --update-core to only refresh shared files." >&2
  exit 1
fi

# Create directory structure
mkdir -p "$TARGET_DIR/infra/traefik"
mkdir -p "$TARGET_DIR/infra/scripts"
mkdir -p "$TARGET_DIR/infra/templates/app-scripts"
mkdir -p "$TARGET_DIR/apps"

# Copy shared files from tool repo
cp "$TOOL_REPO_DIR/CLAUDE.md" "$TARGET_DIR/"
cp "$TOOL_REPO_DIR"/scripts/* "$TARGET_DIR/infra/scripts/"
cp "$TOOL_REPO_DIR/templates/app-scripts/"* "$TARGET_DIR/infra/templates/app-scripts/"

# Make copied scripts executable
chmod +x "$TARGET_DIR/infra/scripts"/*
chmod +x "$TARGET_DIR/infra/templates/app-scripts"/*

# If update-core, exit here (STATE.md, infra/core-compose.yml, infra/traefik/traefik.yml, infra/.env and apps/ must be left untouched)
if [ "$UPDATE_CORE" = "1" ]; then
  echo "Updated core files in $TARGET_DIR"
  exit 0
fi

# Compute socket path based on runtime
if [ "$RUNTIME" = "podman" ]; then
  SOCKET_PATH="/run/user/$(id -u)/podman/podman.sock"
else
  SOCKET_PATH="/var/run/docker.sock"
fi

# Render templates with sed
sed -e "s|__CONTAINER_SOCKET__|$SOCKET_PATH|g" "$TOOL_REPO_DIR/templates/core-compose.yml.tmpl" > "$TARGET_DIR/infra/core-compose.yml"
sed -e "s|__ACME_EMAIL__|$ACME_EMAIL|g" "$TOOL_REPO_DIR/templates/traefik.yml.tmpl" > "$TARGET_DIR/infra/traefik/traefik.yml"

# Generate random password for Postgres
POSTGRES_ROOT_PASSWORD="$(openssl rand -hex 16)"
sed -e "s|__POSTGRES_ROOT_PASSWORD__|$POSTGRES_ROOT_PASSWORD|g" \
    -e "s|__CONTAINER_ENGINE__|$RUNTIME|g" \
    "$TOOL_REPO_DIR/templates/env.tmpl" > "$TARGET_DIR/infra/.env"

# Render STATE.md
sed -e "s|__SERVER_NAME__|$SERVER_NAME|g" \
    -e "s|__BASE_DOMAIN__|$BASE_DOMAIN|g" \
    -e "s|__BACKUP_DESTINATION__|$BACKUP_DEST|g" \
    -e "s|__CONTAINER_ENGINE__|$RUNTIME|g" \
    "$TOOL_REPO_DIR/templates/STATE.md.tmpl" > "$TARGET_DIR/STATE.md"

# Copy env.tmpl as .env.example
cp "$TOOL_REPO_DIR/templates/env.tmpl" "$TARGET_DIR/infra/.env.example"

# Create acme.json files with secure permissions
touch "$TARGET_DIR/infra/traefik/acme.json"
touch "$TARGET_DIR/infra/traefik/acme-staging.json"
chmod 600 "$TARGET_DIR/infra/traefik/acme.json"
chmod 600 "$TARGET_DIR/infra/traefik/acme-staging.json"

# Write .gitignore
cat > "$TARGET_DIR/.gitignore" << 'EOF'
.env
apps/*/.env
infra/.env
infra/traefik/acme.json
infra/traefik/acme-staging.json
EOF

# Print summary
echo "Instance repository generated at $TARGET_DIR"
echo "Next step: cd $TARGET_DIR/infra && $RUNTIME compose -f core-compose.yml up -d"
