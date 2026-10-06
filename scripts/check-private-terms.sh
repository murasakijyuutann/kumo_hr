#!/usr/bin/env bash
# Fails if any term in .private-terms appears in a tracked file.
# Usage: scripts/check-private-terms.sh            (working tree)
#        scripts/check-private-terms.sh --history  (every commit)
set -euo pipefail
TERMS_FILE=".private-terms"
[ -s "$TERMS_FILE" ] || { echo "No $TERMS_FILE found; skipping."; exit 0; }

if [ "${1:-}" = "--history" ]; then
  if git log --all -p -i -G"$(paste -sd'|' "$TERMS_FILE")" --oneline | grep -q .; then
    echo "Private term found in git history."; exit 1
  fi
else
  if git grep -n -i -I -F -f "$TERMS_FILE" -- . ':!.private-terms'; then
    echo "Private term found (lines above). Remove it before committing."; exit 1
  fi
fi
echo "No private terms found."
