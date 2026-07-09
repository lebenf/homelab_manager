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

echo "Target directory: $TARGET_DIR"
