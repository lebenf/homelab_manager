#!/usr/bin/env bash
set -uo pipefail

fail=0

# Validate all *.sh files (exclude .venv/ and .git/)
while IFS= read -r -d '' file; do
    if ! bash -n "$file" 2>/dev/null; then
        echo "Syntax error in: $file"
        fail=1
    fi
done < <(find . -path './.venv' -prune -o -path './.git' -prune -o -name '*.sh' -type f -print0 2>/dev/null)

# Validate all *compose*.yml* files (exclude .venv/)
while IFS= read -r -d '' file; do
    if ! "${CONTAINER_ENGINE:-podman}" compose -f "$file" config --quiet 2>/dev/null; then
        echo "Compose validation error in: $file"
        fail=1
    fi
done < <(find . -path './.venv' -prune -o -name '*compose*.yml*' -type f -print0 2>/dev/null)

# Validate templates/traefik.yml.tmpl if it exists
if [ -f "templates/traefik.yml.tmpl" ]; then
    if ! .venv/bin/python -c "import yaml; yaml.safe_load(open('templates/traefik.yml.tmpl'))" 2>/dev/null; then
        echo "YAML validation error in: templates/traefik.yml.tmpl"
        fail=1
    fi
fi

exit $fail
