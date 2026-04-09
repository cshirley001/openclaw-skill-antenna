#!/usr/bin/env bash
# antenna-pair.sh — Interactive pairing wizard for connecting to a remote peer.
# Can be launched standalone (antenna pair) or auto-offered at end of setup.
#
# Usage:
#   antenna-pair.sh                    Interactive wizard
#   antenna-pair.sh --peer-id <id>     Pre-fill peer ID (still interactive)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$SKILL_DIR/bin"
ANTENNA="$BIN_DIR/antenna"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────

info()   { echo -e "${CYAN}ℹ${NC}  $*"; }
ok()     { echo -e "${GREEN}✓${NC}  $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✗${NC}  $*" >&2; }
header() { echo -e "\n${BOLD}═══ $* ═══${NC}\n"; }

# Wizard step prompt: [N]ext  [S]kip  [Q]uit
# Returns 0 for Next, 1 for Skip, exits for Quit
wizard_prompt() {
  local step_num="$1" total="$2" label="$3" can_skip="${4:-true}"
  echo ""
  echo -e "  ${DIM}Step ${step_num}/${total}${NC}  ${BOLD}${label}${NC}"
  echo ""
  if [[ "$can_skip" == "true" ]]; then
    local choice
    read -rp "$(echo -e "  ${CYAN}▸${NC} [${BOLD}N${NC}]ext  [${BOLD}S${NC}]kip  [${BOLD}Q${NC}]uit: ")" choice
    case "${choice,,}" in
      n|next|"") return 0 ;;
      s|skip)    return 1 ;;
      q|quit)
        echo ""
        info "Wizard stopped. You can resume later with: ${BOLD}antenna pair${NC}"
        exit 0
        ;;
      *) return 0 ;;
    esac
  else
    local choice
    read -rp "$(echo -e "  ${CYAN}▸${NC} [${BOLD}N${NC}]ext  [${BOLD}Q${NC}]uit: ")" choice
    case "${choice,,}" in
      q|quit)
        echo ""
        info "Wizard stopped. You can resume later with: ${BOLD}antenna pair${NC}"
        exit 0
        ;;
      *) return 0 ;;
    esac
  fi
}

prompt_value() {
  local var_name="$1" prompt_text="$2" default="${3:-}"
  local value
  if [[ -n "$default" ]]; then
    read -rp "$(echo -e "  ${CYAN}?${NC}  ${prompt_text} [${default}]: ")" value
    value="${value:-$default}"
  else
    read -rp "$(echo -e "  ${CYAN}?${NC}  ${prompt_text}: ")" value
  fi
  eval "$var_name=\$value"
}

wait_for_enter() {
  local msg="${1:-Press Enter when ready}"
  read -rp "$(echo -e "  ${CYAN}▸${NC} ${msg}... ")" _discard
}

# ── Parse args ───────────────────────────────────────────────────────────────

PEER_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --peer-id) PEER_ID="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: antenna pair [--peer-id <id>]"
      echo "  Interactive wizard for pairing with a remote Antenna peer."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

TOTAL_STEPS=7

# ══════════════════════════════════════════════════════════════════════════════

header "Antenna Peer Pairing Wizard"

echo -e "  This wizard walks you through connecting to a remote Antenna peer."
echo -e "  Each step can be skipped if you've already completed it."
echo -e "  You can quit at any time and resume later with: ${BOLD}antenna pair${NC}"

# ── Step 1: Generate exchange keypair ────────────────────────────────────────

if wizard_prompt 1 $TOTAL_STEPS "Generate exchange keypair"; then
  # Check if keypair already exists
  EXCHANGE_KEY_DIR="$SKILL_DIR/secrets"
  if [[ -f "$EXCHANGE_KEY_DIR/exchange-key.txt" ]]; then
    warn "Exchange keypair already exists."
    if ! prompt_value _regen "  Regenerate? (y/N)" "n"; then true; fi
    if [[ "${_regen,,}" == "y" || "${_regen,,}" == "yes" ]]; then
      bash "$ANTENNA" peers exchange keygen --force
    else
      ok "Keeping existing keypair."
    fi
  else
    bash "$ANTENNA" peers exchange keygen
  fi
fi

# ── Step 2: Display your public key ─────────────────────────────────────────

if wizard_prompt 2 $TOTAL_STEPS "Your public key" false; then
  echo ""
  echo -e "  ${BOLD}Share this key with your peer${NC} (safe to share openly):"
  echo ""
  PUBKEY=$("$ANTENNA" peers exchange pubkey --bare 2>/dev/null || echo "")
  if [[ -n "$PUBKEY" ]]; then
    echo -e "  ${GREEN}${PUBKEY}${NC}"
    echo ""
    info "Your peer needs this key to create an encrypted bootstrap bundle for you."
  else
    err "Could not retrieve public key. Run: antenna peers exchange keygen"
  fi
  echo ""
  wait_for_enter "Press Enter once you've shared your key with your peer"
fi

# ── Step 3: Get peer info and create bundle ──────────────────────────────────

if wizard_prompt 3 $TOTAL_STEPS "Create bootstrap bundle for your peer"; then
  echo ""
  # Get peer ID
  if [[ -z "$PEER_ID" ]]; then
    prompt_value PEER_ID "Peer ID (a short name for the remote host, e.g. 'myserver')"
  else
    echo -e "  ${CYAN}ℹ${NC}  Peer ID: ${BOLD}${PEER_ID}${NC}"
  fi

  if [[ -z "$PEER_ID" ]]; then
    err "Peer ID is required."
  else
    prompt_value PEER_PUBKEY "Their age public key (starts with age1...)"
    if [[ -z "$PEER_PUBKEY" ]]; then
      err "Public key is required to create an encrypted bundle."
    else
      echo ""
      info "Creating encrypted bootstrap bundle..."
      echo ""
      BUNDLE_OUTPUT=$(bash "$ANTENNA" peers exchange initiate "$PEER_ID" --pubkey "$PEER_PUBKEY" 2>&1) || true
      echo "$BUNDLE_OUTPUT"

      # Extract bundle file path from output
      BUNDLE_FILE=$(echo "$BUNDLE_OUTPUT" | grep -oP 'Bundle file: \K.*' || echo "")
      if [[ -n "$BUNDLE_FILE" ]]; then
        echo ""
        ok "Bundle created!"
        echo ""
        echo -e "  ${BOLD}Send this file to your peer:${NC}"
        echo -e "  ${CYAN}${BUNDLE_FILE}${NC}"
        echo ""
        echo -e "  ${DIM}Recommended methods: scp, email attachment, or secure file share.${NC}"
        echo -e "  ${DIM}Avoid pasting the contents inline — email clients can corrupt the encoding.${NC}"
      fi
    fi
  fi
  echo ""
  wait_for_enter "Press Enter once you've sent the bundle to your peer"
fi

# ── Step 4: Wait for their bundle ───────────────────────────────────────────

if wizard_prompt 4 $TOTAL_STEPS "Wait for their reply bundle"; then
  echo ""
  echo -e "  Your peer needs to:"
  echo -e "    1. Import your bundle:  ${DIM}antenna peers exchange import <your-bundle>${NC}"
  echo -e "    2. Create a reply:      ${DIM}antenna peers exchange reply ${PEER_ID:-<your-host-id>}${NC}"
  echo -e "    3. Send you the reply bundle file"
  echo ""
  wait_for_enter "Press Enter once you've received their reply bundle"
fi

# ── Step 5: Import their bundle ─────────────────────────────────────────────

if wizard_prompt 5 $TOTAL_STEPS "Import their reply bundle"; then
  echo ""
  prompt_value IMPORT_FILE "Path to the bundle file you received"
  if [[ -z "$IMPORT_FILE" ]]; then
    err "No file path provided."
  elif [[ ! -f "$IMPORT_FILE" ]]; then
    err "File not found: $IMPORT_FILE"
  else
    echo ""
    bash "$ANTENNA" peers exchange import "$IMPORT_FILE" || true
    echo ""
  fi
fi

# ── Step 6: Test connectivity ────────────────────────────────────────────────

if wizard_prompt 6 $TOTAL_STEPS "Test connectivity"; then
  echo ""
  # Use PEER_ID if we have it, otherwise ask
  if [[ -z "$PEER_ID" ]]; then
    prompt_value PEER_ID "Peer ID to test"
  fi
  if [[ -n "$PEER_ID" ]]; then
    info "Testing connection to ${BOLD}${PEER_ID}${NC}..."
    echo ""
    bash "$ANTENNA" peers test "$PEER_ID" || true
    echo ""
  else
    err "No peer ID provided."
  fi
fi

# ── Step 7: Send first message ──────────────────────────────────────────────

if wizard_prompt 7 $TOTAL_STEPS "Send your first message!"; then
  echo ""
  if [[ -z "$PEER_ID" ]]; then
    prompt_value PEER_ID "Peer ID to message"
  fi
  if [[ -n "$PEER_ID" ]]; then
    prompt_value FIRST_MSG "Message to send" "Hello from the other side! 👋"
    echo ""
    info "Sending to ${BOLD}${PEER_ID}${NC}..."
    echo ""
    bash "$ANTENNA" msg "$PEER_ID" "$FIRST_MSG" || true
    echo ""
  else
    err "No peer ID provided."
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────

header "Pairing Complete"

echo -e "  You're connected! Here are some handy commands:"
echo ""
echo -e "  ${BOLD}Send a message:${NC}     antenna msg ${PEER_ID:-<peer>} \"Your message\""
echo -e "  ${BOLD}Target a session:${NC}   antenna msg ${PEER_ID:-<peer>} --session agent:main:test \"Hi\""
echo -e "  ${BOLD}Check status:${NC}       antenna peers test ${PEER_ID:-<peer>}"
echo -e "  ${BOLD}List peers:${NC}         antenna peers list"
echo -e "  ${BOLD}Run diagnostics:${NC}    antenna doctor"
echo ""
ok "Happy messaging! 📡"
echo ""
