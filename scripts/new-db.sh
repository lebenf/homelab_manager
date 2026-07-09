#!/usr/bin/env bash
set -euo pipefail

# Resolve container engine using the sourcing convention
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/../.env" ] && set -a && source "$SCRIPT_DIR/../.env" && set +a
ENGINE="${CONTAINER_ENGINE:-podman}"

# Check arguments
if [[ $# -lt 1 ]]; then
  echo "Usage: new-db.sh <app-name>" >&2
  exit 1
fi

APP_NAME="$1"

# Check if role exists
ROLE_EXISTS=$("$ENGINE" exec -i postgres psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${APP_NAME}'" 2>/dev/null || true)

# Check if database exists
DB_EXISTS=$("$ENGINE" exec -i postgres psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${APP_NAME}'" 2>/dev/null || true)

if [[ -z "$ROLE_EXISTS" ]] || [[ -z "$DB_EXISTS" ]]; then
  # Generate password for new database
  PASSWORD=$(openssl rand -hex 16)

  # Create role if it doesn't exist
  if [[ -z "$ROLE_EXISTS" ]]; then
    "$ENGINE" exec -i postgres psql -U postgres -c "CREATE ROLE ${APP_NAME} WITH LOGIN PASSWORD '${PASSWORD}';"
  fi

  # Create database if it doesn't exist
  if [[ -z "$DB_EXISTS" ]]; then
    "$ENGINE" exec -i postgres psql -U postgres -c "CREATE DATABASE ${APP_NAME} OWNER ${APP_NAME};"
  fi

  echo "DATABASE_URL=postgresql://${APP_NAME}:${PASSWORD}@postgres:5432/${APP_NAME}"
else
  echo "DATABASE_URL=postgresql://${APP_NAME}:(unchanged)@postgres:5432/${APP_NAME}"
fi
