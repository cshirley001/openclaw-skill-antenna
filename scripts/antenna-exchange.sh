#!/usr/bin/env bash
# antenna-exchange.sh — Guided per-peer secret exchange for Antenna.
#
# Two modes:
#   1. Interactive guided exchange (walks through the full flow)
#   2. Quick import (non-interactive, for experienced users)
#
# Usage:
#   antenna-exchange.sh <peer-id>                    Guided exchange
#   antenna-exchange.sh <peer-id> --import <file>    Import peer's secret from file
#   antenna-exchange.sh <peer-id> --import-value <hex>  Import peer's secret from value
#   antenna-exchange.sh <peer-id> --export           Print your identity secret for copy
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PEERS_FILE="$SKILL_DIR/antenna-peers.json"
CONFIG_FILE="$SKILL_DIR/antenna-config.json"
SECRETS_DIR="$SKILL_DIR/secrets"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✓${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
err()   { echo -e "${RED}✗${NC}  $*" >&2; }
header(){ echo -e "\n${BOLD}$*${NC}"; }

prompt_yn() {
  local prompt_text="$1" default="${2:-y}"
  local yn
  read -rp "$(echo -e "${CYAN}?${NC}  ${prompt_text} [${default}]: ")" yn
  yn="${yn:-$default}"
  [[ "${yn,,}" == "y" || "${yn,,}" == "yes" ]]
}

# ── Parse args ───────────────────────────────────────────────────────────────

PEER_ID="${1:-}"
if [[ -z "$PEER_ID" || "$PEER_ID" == "-h" || "$PEER_ID" == "--help" ]]; then
  cat <<'EOF'
antenna peers exchange — Per-peer secret exchange

Guided (walks you through the full flow):
  antenna peers exchange <peer-id>

Quick import (experienced users):
  antenna peers exchange <peer-id> --import /path/to/their-secret.file
  antenna peers exchange <peer-id> --import-value abcdef1234...

Export your identity secret (for sending to a peer):
  antenna peers exchange <peer-id> --export

What happens:
  1. Ensures YOUR identity secret exists (generates if needed)
  2. Shows you how to send YOUR secret to the peer
  3. Imports THEIR secret for verifying their identity
  4. Updates antenna-peers.json with peer_secret_file paths
  5. Updates allowed_inbound_peers and allowed_outbound_peers in config
  6. Verifies the setup
EOF
  exit 0
fi
shift

MODE="guided"  # guided | import-file | import-value | export
IMPORT_PATH=""
IMPORT_VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --import)        MODE="import-file"; IMPORT_PATH="$2"; shift 2 ;;
    --import-value)  MODE="import-value"; IMPORT_VALUE="$2"; shift 2 ;;
    --export)        MODE="export"; shift ;;
    -h|--help)
      cat <<'EOF'
antenna peers exchange — Per-peer secret exchange

Guided (walks you through the full flow):
  antenna peers exchange <peer-id>

Quick import (experienced users):
  antenna peers exchange <peer-id> --import /path/to/their-secret.file
  antenna peers exchange <peer-id> --import-value abcdef1234...

Export your identity secret (for sending to a peer):
  antenna peers exchange <peer-id> --export

What happens:
  1. Ensures YOUR identity secret exists (generates if needed)
  2. Shows you how to send YOUR secret to the peer
  3. Imports THEIR secret for verifying their identity
  4. Updates antenna-peers.json with peer_secret_file paths
  5. Updates allowed_inbound_peers and allowed_outbound_peers in config
  6. Verifies the setup
EOF
      exit 0
      ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Pre-flight ───────────────────────────────────────────────────────────────

if [[ ! -f "$PEERS_FILE" ]]; then
  err "No peers file found. Run 'antenna setup' first."
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  err "No config file found. Run 'antenna setup' first."
  exit 1
fi

# Get self info
SELF_ID=$(jq -r 'to_entries[] | select(.value.self == true) | .key' "$PEERS_FILE" 2>/dev/null || echo "")
if [[ -z "$SELF_ID" ]]; then
  err "No self-peer found in peers file. Run 'antenna setup' first."
  exit 1
fi

SELF_SECRET_FILE="$SECRETS_DIR/antenna-peer-${SELF_ID}.secret"

# Check if peer exists in registry
PEER_EXISTS=$(jq -r --arg p "$PEER_ID" 'has($p) | tostring' "$PEERS_FILE" 2>/dev/null || echo "false")

# ── Export mode ──────────────────────────────────────────────────────────────

if [[ "$MODE" == "export" ]]; then
  if [[ ! -f "$SELF_SECRET_FILE" ]]; then
    err "No identity secret found at: $SELF_SECRET_FILE"
    err "Run 'antenna setup' or 'antenna peers generate-secret $SELF_ID' to create one."
    exit 1
  fi
  echo ""
  echo -e "${BOLD}Your identity secret for $SELF_ID:${NC}"
  echo ""
  cat "$SELF_SECRET_FILE"
  echo ""
  echo ""
  info "Send this value to $PEER_ID through a secure channel (scp, encrypted chat, etc.)"
  info "They should import it with: antenna peers exchange $SELF_ID --import-value <this-value>"
  exit 0
fi

# ── Quick import modes ───────────────────────────────────────────────────────

do_import() {
  local secret="$1"

  # Validate secret format (should be 64 hex chars)
  if ! echo "$secret" | grep -qE '^[0-9a-f]{64}$'; then
    err "Invalid secret format. Expected 64 lowercase hex characters."
    err "Got: ${secret:0:20}... (${#secret} chars)"
    exit 1
  fi

  mkdir -p "$SECRETS_DIR"
  local peer_secret_path="$SECRETS_DIR/antenna-peer-${PEER_ID}.secret"
  echo -n "$secret" > "$peer_secret_path"
  chmod 600 "$peer_secret_path"
  ok "Saved ${PEER_ID}'s identity secret to: $peer_secret_path"

  # Update peer record with secret file reference
  if [[ "$PEER_EXISTS" == "true" ]]; then
    local tmp; tmp=$(mktemp)
    jq --arg p "$PEER_ID" --arg psf "secrets/antenna-peer-${PEER_ID}.secret" \
      '.[$p].peer_secret_file = $psf' "$PEERS_FILE" > "$tmp" && mv "$tmp" "$PEERS_FILE"
    ok "Updated $PEER_ID in peers file with peer_secret_file"
  else
    warn "Peer $PEER_ID is not in peers file yet. Add them with:"
    echo "  antenna peers add $PEER_ID --url <url> --token-file <path>"
  fi

  # Update allowed lists in config
  update_allowed_lists

  ok "Import complete for $PEER_ID"
}

update_allowed_lists() {
  local tmp; tmp=$(mktemp)
  # Add to allowed_inbound_peers if not already present
  jq --arg p "$PEER_ID" '
    .allowed_inbound_peers = ((.allowed_inbound_peers // []) | if index($p) then . else . + [$p] end) |
    .allowed_outbound_peers = ((.allowed_outbound_peers // []) | if index($p) then . else . + [$p] end)
  ' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  ok "Ensured $PEER_ID is in allowed_inbound_peers and allowed_outbound_peers"
}

if [[ "$MODE" == "import-file" ]]; then
  if [[ ! -f "$IMPORT_PATH" ]]; then
    err "File not found: $IMPORT_PATH"
    exit 1
  fi
  secret=$(tr -d '[:space:]' < "$IMPORT_PATH")
  do_import "$secret"
  exit 0
fi

if [[ "$MODE" == "import-value" ]]; then
  secret=$(echo "$IMPORT_VALUE" | tr -d '[:space:]')
  do_import "$secret"
  exit 0
fi

# ── Guided exchange mode ─────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}📡 Antenna — Peer Secret Exchange${NC}"
echo ""
echo "  You: ${BOLD}$SELF_ID${NC}"
echo "  Peer: ${BOLD}$PEER_ID${NC}"
echo ""
echo "  This will exchange identity secrets so both hosts can verify"
echo "  who's sending messages. Each side needs the other's secret."
echo ""

# ── Step 1: Ensure our identity secret exists ────────────────────────────────

header "Step 1/4 — Your Identity Secret"

if [[ -f "$SELF_SECRET_FILE" ]]; then
  ok "Your identity secret exists: $SELF_SECRET_FILE"
else
  info "Generating your identity secret..."
  mkdir -p "$SECRETS_DIR"
  openssl rand -hex 32 > "$SELF_SECRET_FILE"
  chmod 600 "$SELF_SECRET_FILE"
  ok "Generated: $SELF_SECRET_FILE"
fi

OUR_SECRET=$(tr -d '[:space:]' < "$SELF_SECRET_FILE")

# ── Step 2: Send our secret to the peer ──────────────────────────────────────

header "Step 2/4 — Send Your Secret to $PEER_ID"

PEER_URL=$(jq -r --arg p "$PEER_ID" '.[$p].url // empty' "$PEERS_FILE" 2>/dev/null || echo "")

echo ""
echo -e "  ${BOLD}Your identity secret:${NC}"
echo -e "  ${DIM}$OUR_SECRET${NC}"
echo ""

echo "  How to get this to $PEER_ID:"
echo ""
echo "  Option A — have them import the value directly (easiest):"
echo -e "  ${CYAN}antenna peers exchange $SELF_ID --import-value $OUR_SECRET${NC}"
echo ""
echo "  Option B — the other host's operator can pull it (if they have SSH to you):"
echo -e "  ${DIM}  They run: scp ${SELF_ID}:<antenna-skill-dir>/secrets/antenna-peer-${SELF_ID}.secret ./secrets/${NC}"
echo ""
if [[ -n "$PEER_URL" ]]; then
  SSH_HOST=$(echo "$PEER_URL" | sed 's|https\?://||; s|:.*||; s|/.*||')
  echo "  Option C — scp (if you have SSH access to $PEER_ID):"
  echo -e "  ${CYAN}scp $SELF_SECRET_FILE ${SSH_HOST}:<antenna-skill-dir>/secrets/antenna-peer-${SELF_ID}.secret${NC}"
  echo ""
fi
echo "  Option D — copy the secret above and send through any secure channel"
echo "  (encrypted chat, face-to-face, etc.)"

echo ""
read -rp "$(echo -e "${CYAN}?${NC}  Press Enter when you've sent your secret to $PEER_ID (or 'skip' to do it later): ")" step2_ack
if [[ "${step2_ack,,}" == "skip" ]]; then
  warn "Skipped sending your secret. Remember to do it later!"
fi

# ── Step 3: Import their secret ──────────────────────────────────────────────

header "Step 3/4 — Import ${PEER_ID}'s Secret"

PEER_SECRET_FILE="$SECRETS_DIR/antenna-peer-${PEER_ID}.secret"
if [[ -f "$PEER_SECRET_FILE" ]]; then
  existing_secret=$(tr -d '[:space:]' < "$PEER_SECRET_FILE")
  ok "Already have ${PEER_ID}'s secret: $PEER_SECRET_FILE"
  if prompt_yn "Replace with a new one?" "n"; then
    true  # fall through to import
  else
    info "Keeping existing secret."
    # Skip to step 4
    SKIP_IMPORT=true
  fi
fi

if [[ "${SKIP_IMPORT:-}" != "true" ]]; then
  echo ""
  echo "  How do you want to import ${PEER_ID}'s secret?"
  echo ""
  echo "    1) Paste the secret value"
  echo "    2) Provide a file path"
  echo "    3) Skip (do it later)"
  echo ""
  read -rp "$(echo -e "${CYAN}?${NC}  Choice [1/2/3]: ")" import_choice

  case "${import_choice:-1}" in
    1)
      read -rp "$(echo -e "${CYAN}?${NC}  Paste ${PEER_ID}'s identity secret: ")" pasted_secret
      pasted_secret=$(echo "$pasted_secret" | tr -d '[:space:]')
      if echo "$pasted_secret" | grep -qE '^[0-9a-f]{64}$'; then
        mkdir -p "$SECRETS_DIR"
        echo -n "$pasted_secret" > "$PEER_SECRET_FILE"
        chmod 600 "$PEER_SECRET_FILE"
        ok "Saved ${PEER_ID}'s secret to: $PEER_SECRET_FILE"
      else
        err "Invalid format — expected 64 hex chars. Got ${#pasted_secret} chars."
        warn "You can import later with: antenna peers exchange $PEER_ID --import-value <secret>"
      fi
      ;;
    2)
      read -rp "$(echo -e "${CYAN}?${NC}  Path to ${PEER_ID}'s secret file: ")" import_file
      if [[ -f "$import_file" ]]; then
        file_secret=$(tr -d '[:space:]' < "$import_file")
        if echo "$file_secret" | grep -qE '^[0-9a-f]{64}$'; then
          mkdir -p "$SECRETS_DIR"
          echo -n "$file_secret" > "$PEER_SECRET_FILE"
          chmod 600 "$PEER_SECRET_FILE"
          ok "Imported ${PEER_ID}'s secret from: $import_file"
        else
          err "File doesn't contain a valid 64-hex-char secret."
        fi
      else
        err "File not found: $import_file"
        warn "Import later with: antenna peers exchange $PEER_ID --import <file>"
      fi
      ;;
    3)
      warn "Skipped import. Import later with:"
      echo "  antenna peers exchange $PEER_ID --import-value <secret>"
      echo "  antenna peers exchange $PEER_ID --import <file>"
      ;;
  esac
fi

# ── Step 4: Update config and verify ─────────────────────────────────────────

header "Step 4/4 — Finalize"

# Update peers file: ensure peer_secret_file is set
if [[ "$PEER_EXISTS" == "true" ]]; then
  local_peer_secret_ref="secrets/antenna-peer-${PEER_ID}.secret"
  current_psf=$(jq -r --arg p "$PEER_ID" '.[$p].peer_secret_file // empty' "$PEERS_FILE" 2>/dev/null)
  if [[ "$current_psf" != "$local_peer_secret_ref" ]]; then
    tmp=$(mktemp)
    jq --arg p "$PEER_ID" --arg psf "$local_peer_secret_ref" \
      '.[$p].peer_secret_file = $psf' "$PEERS_FILE" > "$tmp" && mv "$tmp" "$PEERS_FILE"
    ok "Updated $PEER_ID's peer_secret_file in peers registry"
  fi
fi

# Also ensure self-peer has peer_secret_file set
self_psf=$(jq -r --arg p "$SELF_ID" '.[$p].peer_secret_file // empty' "$PEERS_FILE" 2>/dev/null)
if [[ "$self_psf" != "secrets/antenna-peer-${SELF_ID}.secret" ]]; then
  tmp=$(mktemp)
  jq --arg p "$SELF_ID" --arg psf "secrets/antenna-peer-${SELF_ID}.secret" \
    '.[$p].peer_secret_file = $psf' "$PEERS_FILE" > "$tmp" && mv "$tmp" "$PEERS_FILE"
  ok "Updated $SELF_ID's peer_secret_file in peers registry"
fi

# Update allowed lists
update_allowed_lists

# ── Verification summary ─────────────────────────────────────────────────────

echo ""
header "═══ Exchange Summary ═══"
echo ""

# Check our secret
if [[ -f "$SELF_SECRET_FILE" ]]; then
  our_perms=$(stat -c '%a' "$SELF_SECRET_FILE" 2>/dev/null || stat -f '%Lp' "$SELF_SECRET_FILE" 2>/dev/null || echo "?")
  echo -e "  ${GREEN}✓${NC}  Your identity secret ($SELF_ID): exists, perms=$our_perms"
else
  echo -e "  ${RED}✗${NC}  Your identity secret ($SELF_ID): MISSING"
fi

# Check their secret
if [[ -f "$PEER_SECRET_FILE" ]]; then
  their_perms=$(stat -c '%a' "$PEER_SECRET_FILE" 2>/dev/null || stat -f '%Lp' "$PEER_SECRET_FILE" 2>/dev/null || echo "?")
  echo -e "  ${GREEN}✓${NC}  Peer identity secret ($PEER_ID): exists, perms=$their_perms"
else
  echo -e "  ${YELLOW}⚠${NC}  Peer identity secret ($PEER_ID): not yet imported"
fi

# Check peer in peers file
if [[ "$PEER_EXISTS" == "true" ]]; then
  echo -e "  ${GREEN}✓${NC}  Peer $PEER_ID is in peers registry"
else
  echo -e "  ${YELLOW}⚠${NC}  Peer $PEER_ID is NOT in peers registry — add with:"
  echo "     antenna peers add $PEER_ID --url <url> --token-file <path>"
fi

# Check config allowlists
in_inbound=$(jq -r --arg p "$PEER_ID" '.allowed_inbound_peers // [] | if index($p) then "yes" else "no" end' "$CONFIG_FILE" 2>/dev/null)
in_outbound=$(jq -r --arg p "$PEER_ID" '.allowed_outbound_peers // [] | if index($p) then "yes" else "no" end' "$CONFIG_FILE" 2>/dev/null)
if [[ "$in_inbound" == "yes" && "$in_outbound" == "yes" ]]; then
  echo -e "  ${GREEN}✓${NC}  $PEER_ID is in both inbound and outbound allowlists"
else
  [[ "$in_inbound" != "yes" ]] && echo -e "  ${YELLOW}⚠${NC}  $PEER_ID missing from allowed_inbound_peers"
  [[ "$in_outbound" != "yes" ]] && echo -e "  ${YELLOW}⚠${NC}  $PEER_ID missing from allowed_outbound_peers"
fi

echo ""
if [[ -f "$PEER_SECRET_FILE" && "$PEER_EXISTS" == "true" ]]; then
  ok "Exchange complete! Test with: antenna peers test $PEER_ID"
  echo "  Then send a message:       antenna msg $PEER_ID \"Hello!\""
else
  warn "Exchange partially complete — check warnings above."
fi
echo ""
