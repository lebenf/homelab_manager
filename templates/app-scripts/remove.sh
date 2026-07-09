#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/../../../infra/.env" ] && set -a && source "$SCRIPT_DIR/../../../infra/.env" && set +a
ENGINE="${CONTAINER_ENGINE:-podman}"
COMPOSE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker-compose.yml"

# Parse flags
YES=false
WITH_DATA=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      YES=true
      shift
      ;;
    --with-data)
      WITH_DATA=true
      shift
      ;;
    *)
      echo "Usage: $0 [--yes] [--with-data]" >&2
      exit 1
      ;;
  esac
done

# Confirmation prompt unless --yes is given
if [[ "$YES" != "true" ]]; then
  read -rp "This will remove the app containers. Continue? [y/N] " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
fi

# Stop and remove containers
"$ENGINE" compose -f "$COMPOSE_FILE" down

# Remove volumes if --with-data is given
if [[ "$WITH_DATA" == "true" ]]; then
  "$ENGINE" compose -f "$COMPOSE_FILE" down -v
fi
