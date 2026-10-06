#!/usr/bin/env bash
# Installs a pre-commit hook that runs the private-term check.
set -euo pipefail
HOOK="$(git rev-parse --git-path hooks)/pre-commit"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/check-private-terms.sh"
EOF
chmod +x "$HOOK"
echo "Installed pre-commit hook at $HOOK"
