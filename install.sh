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

echo "Target directory: $TARGET_DIR"
