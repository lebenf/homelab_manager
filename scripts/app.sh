#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: $0 <app-name> <install|update|backup-now|remove|start|stop|restart|status|logs> [extra args...]" >&2
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

APP_NAME="$1"
ACTION="$2"
shift 2

ACTION_SCRIPT="$SCRIPT_DIR/../apps/$APP_NAME/scripts/$ACTION.sh"

if [[ ! -f "$ACTION_SCRIPT" ]]; then
  echo "Error: No $ACTION script found for app '$APP_NAME' at $ACTION_SCRIPT" >&2
  exit 1
fi

exec "$ACTION_SCRIPT" "$@"
