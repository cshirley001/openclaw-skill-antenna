#!/usr/bin/env bash
# install.sh — Post-install bootstrap for Antenna (ClawHub or fresh clone).
#
# Usage (after clawhub install antenna):
#   bash skills/antenna/install.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "  🦞 Antenna — Post-Install Bootstrap"
echo "  ════════════════════════════════════"
echo ""
echo "  Here's the deal: ClawHub is great at delivering skill packages,"
echo "  but it has a small quirk — it doesn't preserve file permissions."
echo "  That means all the shell scripts that make Antenna tick just"
echo "  arrived without their execute bits. Think of it like shipping"
echo "  a lobster trap with the door wired shut."
echo ""
echo "  This script cracks open that wire. It finds every .sh file in"
echo "  Antenna's bin/ and scripts/, flips on the execute permission,"
echo "  and gets you ready to dive in."
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
  echo "  🔧 Fixed execute permissions on $changed file(s)."
  echo "     Everything's seaworthy now."
else
  echo "  ✓ All files already executable — nothing to fix."
  echo "    Looks like someone got here before us. Nice."
fi

# ── Run setup ────────────────────────────────────────────────────────────────
echo ""
echo "  Next up: antenna setup — the wizard that wires you into the reef."
echo "  It handles host identity, gateway registration, CLI path, and"
echo "  all the plumbing so you can start sending messages."
echo ""

if [[ "${1:-}" == "--setup" ]]; then
  echo "  Diving straight into setup..."
  echo ""
  bash "$SCRIPT_DIR/bin/antenna.sh" setup
elif [[ -t 0 ]]; then
  read -rp "  Run antenna setup now? [Y/n] " answer
  case "${answer:-y}" in
    [Yy]*|"")
      echo ""
      bash "$SCRIPT_DIR/bin/antenna.sh" setup
      ;;
    *)
      echo ""
      echo "  No rush — the reef isn't going anywhere."
      echo ""
      echo "  When you're ready:"
      echo "    antenna setup"
      echo ""
      echo "  Or if antenna isn't on PATH yet:"
      echo "    bash $SCRIPT_DIR/bin/antenna.sh setup"
      echo ""
      ;;
  esac
else
  echo "  When you're ready:"
  echo "    bash $SCRIPT_DIR/bin/antenna.sh setup"
  echo ""
fi

echo "  Need help? 🪨"
echo "    📧 help@clawreef.io"
echo "    🐛 https://github.com/ClawReefAntenna/antenna/issues"
echo ""
