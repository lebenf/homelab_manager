#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${STATE_FILE:-STATE.md}"

if [[ $# -lt 5 ]]; then
  echo "Usage: register-app.sh <app-name> <path> <domain> <db|nodb> <backup|nobackup>" >&2
  exit 1
fi

APP_NAME="$1"
PATH_VAL="$2"
DOMAIN="$3"
DB_STATUS="$4"
BACKUP_STATUS="$5"

ROW="| ${APP_NAME} | ${PATH_VAL} | ${DOMAIN} | ${DB_STATUS} | ${BACKUP_STATUS} |"

if [[ -f "$STATE_FILE" ]]; then
  if grep -q "^| ${APP_NAME} |" "$STATE_FILE"; then
    sed -i "s|^| ${APP_NAME} |.*|${APP_NAME} | ${PATH_VAL} | ${DOMAIN} | ${DB_STATUS} | ${BACKUP_STATUS} |" "$STATE_FILE"
  else
    sed -i "/<!-- APPS_TABLE_ROWS -->/a\\${ROW}" "$STATE_FILE"
  fi
fi
