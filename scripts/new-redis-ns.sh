#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: new-redis-ns.sh <app-name>" >&2
  exit 1
fi

app_name="$1"

echo "REDIS_URL=redis://redis:6379/0"
echo "REDIS_PREFIX=${app_name}:"
