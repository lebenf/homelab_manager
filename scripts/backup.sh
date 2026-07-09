#!/usr/bin/env bash
set -euo pipefail

# Resolve container engine using the WORKFLOW.md sourcing convention
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/../.env" ] && set -a && source "$SCRIPT_DIR/../.env" && set +a
ENGINE="${CONTAINER_ENGINE:-podman}"

# Parse arguments
APP_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Determine app directories to process
if [[ -n "$APP_NAME" ]]; then
    if [[ ! -d "apps/$APP_NAME" ]]; then
        echo "Error: App directory 'apps/$APP_NAME' does not exist" >&2
        exit 1
    fi
    APP_DIRS=("apps/$APP_NAME")
else
    APP_DIRS=()
    while IFS= read -r -d '' dir; do
        APP_DIRS+=("$dir")
    done < <(find apps -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

# Ensure backup-staging directory exists
mkdir -p infra/backup-staging

# Process each app
for app_dir in "${APP_DIRS[@]}"; do
    app_name=$(basename "$app_dir")
    compose_file="$app_dir/docker-compose.yml"

    # Skip if backup is disabled
    if grep -q "homelab.backup=false" "$compose_file" 2>/dev/null; then
        echo "Skipping $app_name (backup disabled)"
        continue
    fi

    # Dump database if needed
    if [[ -f "$app_dir/.needs-db" ]]; then
        echo "Dumping database for $app_name..."
        "$ENGINE" exec postgres pg_dump -U postgres "$app_name" > "infra/backup-staging/${app_name}.sql"
    fi

    # Run restic backup
    echo "Backing up $app_name..."
    restic backup "$app_dir" infra/backup-staging
done

echo "Backup completed"
