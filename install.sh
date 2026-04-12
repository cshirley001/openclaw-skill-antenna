#!/usr/bin/env bash
# install.sh — Post-install bootstrap for Antenna (ClawHub or fresh clone).
#
# ClawHub does not preserve execute permissions on installed files.
# This script fixes that, then offers to run setup.
#
# Usage (after clawhub install antenna):
#   bash skills/antenna/install.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📡 Antenna — Post-Install Bootstrap"
echo ""

# ── Fix file permissions ─────────────────────────────────────────────────────
changed=0
for f in "$SCRIPT_DIR"/bin/*.sh "$SCRIPT_DIR"/scripts/*.sh; do
  if [[ -f "$f" ]] && [[ ! -x "$f" ]]; then
    chmod +x "$f"
    changed=$((changed + 1))
  fi
done

if [[ "$changed" -gt 0 ]]; then
  echo "✓ Fixed execute permissions on $changed file(s)."
else
  echo "✓ All files already executable."
fi

# ── Run setup ────────────────────────────────────────────────────────────────
echo ""
if [[ "${1:-}" == "--setup" ]]; then
  echo "Running antenna setup..."
  echo ""
  bash "$SCRIPT_DIR/bin/antenna.sh" setup
elif [[ -t 0 ]]; then
  # Interactive terminal — ask
  read -rp "Run antenna setup now? [Y/n] " answer
  case "${answer:-y}" in
    [Yy]*|"")
      echo ""
      bash "$SCRIPT_DIR/bin/antenna.sh" setup
      ;;
    *)
      echo ""
      echo "Skipped. You can run setup later with:"
      echo "  antenna setup"
      echo ""
      echo "Or if antenna isn't on PATH yet:"
      echo "  bash $SCRIPT_DIR/bin/antenna.sh setup"
      ;;
  esac
else
  # Non-interactive — just fix permissions and print next step
  echo "Next step:"
  echo "  bash $SCRIPT_DIR/bin/antenna.sh setup"
fi
