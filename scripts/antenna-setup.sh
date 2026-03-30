#!/usr/bin/env bash
# antenna-setup.sh — First-run setup wizard for Antenna.
# Creates config, peers file, identity secret, and prints gateway registration instructions.
#
# Usage:
#   antenna-setup.sh                           Interactive wizard
#   antenna-setup.sh --host-id <id>            Non-interactive (all flags)
#     --display-name <name>
#     --url <url>
#     --agent-id <agent-id>
#     --model <provider/model>
#     --token-file <path>
#     [--force]                                Overwrite existing config
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SKILL_DIR/antenna-config.json"
PEERS_FILE="$SKILL_DIR/antenna-peers.json"
SECRETS_DIR="$SKILL_DIR/secrets"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo -e "${CYAN}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✓${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
err()   { echo -e "${RED}✗${NC}  $*" >&2; }
header(){ echo -e "\n${BOLD}$*${NC}"; }

prompt() {
  local var_name="$1" prompt_text="$2" default="${3:-}"
  local value
  if [[ -n "$default" ]]; then
    read -rp "$(echo -e "${CYAN}?${NC}  ${prompt_text} [${default}]: ")" value
    value="${value:-$default}"
  else
    read -rp "$(echo -e "${CYAN}?${NC}  ${prompt_text}: ")" value
  fi
  eval "$var_name=\$value"
}

prompt_yn() {
  local prompt_text="$1" default="${2:-y}"
  local yn
  read -rp "$(echo -e "${CYAN}?${NC}  ${prompt_text} [${default}]: ")" yn
  yn="${yn:-$default}"
  [[ "${yn,,}" == "y" || "${yn,,}" == "yes" ]]
}

# ── Parse non-interactive flags ──────────────────────────────────────────────

NI_HOST_ID="" NI_DISPLAY="" NI_URL="" NI_AGENT="" NI_MODEL="" NI_TOKEN="" NI_FORCE=false
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-id)       NI_HOST_ID="$2"; INTERACTIVE=false; shift 2 ;;
    --display-name)  NI_DISPLAY="$2"; shift 2 ;;
    --url)           NI_URL="$2"; shift 2 ;;
    --agent-id)      NI_AGENT="$2"; shift 2 ;;
    --model)         NI_MODEL="$2"; shift 2 ;;
    --token-file)    NI_TOKEN="$2"; shift 2 ;;
    --force)         NI_FORCE=true; shift ;;
    -h|--help)
      cat <<'EOF'
antenna setup — First-run setup wizard for Antenna

Interactive:
  antenna setup

Non-interactive:
  antenna setup --host-id myhost \
    --display-name "My Host (Server)" \
    --url "https://myhost.tailXXXXX.ts.net" \
    --agent-id betty \
    --model "openai/gpt-5.4" \
    --token-file /path/to/hooks_token \
    [--force]

Creates:
  - antenna-config.json (system settings)
  - antenna-peers.json (peer registry with self-peer entry)
  - secrets/antenna-peer-<host-id>.secret (your identity secret)
  - Prints gateway registration instructions
EOF
      exit 0
      ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Pre-flight checks ───────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  err "jq not found — required for Antenna. Install with: apt install jq / brew install jq"
  exit 1
fi

if ! command -v curl &>/dev/null; then
  err "curl not found — required for Antenna."
  exit 1
fi

if ! command -v openssl &>/dev/null; then
  err "openssl not found — required for secret generation."
  exit 1
fi

# Check for existing config
if [[ -f "$CONFIG_FILE" && "$NI_FORCE" != "true" ]]; then
  if [[ "$INTERACTIVE" == "true" ]]; then
    warn "Antenna is already configured ($CONFIG_FILE exists)."
    if ! prompt_yn "Overwrite and start fresh?" "n"; then
      info "Setup cancelled. Use 'antenna status' to check your current config."
      exit 0
    fi
  else
    err "Config already exists. Use --force to overwrite."
    exit 1
  fi
fi

# ── Banner ───────────────────────────────────────────────────────────────────

if [[ "$INTERACTIVE" == "true" ]]; then
  echo ""
  echo -e "${BOLD}📡 Antenna Setup — Inter-Host OpenClaw Messaging${NC}"
  echo ""
  echo "  This wizard will configure Antenna on this host."
  echo "  You'll need:"
  echo "    1. Your OpenClaw host ID (usually your hostname)"
  echo "    2. Your Tailscale serve URL or tailnet IP"
  echo "    3. Your primary agent ID (e.g., 'betty')"
  echo "    4. A relay model (e.g., 'openai/gpt-5.4')"
  echo "    5. Path to your OpenClaw hooks bearer token file"
  echo ""
fi

# ── Gather info ──────────────────────────────────────────────────────────────

if [[ "$INTERACTIVE" == "true" ]]; then
  # Host ID
  local_hostname=$(hostname | tr '[:upper:]' '[:lower:]')
  header "Step 1/6 — Host Identity"
  prompt HOST_ID "Host ID (lowercase, no spaces — identifies you on the mesh)" "$local_hostname"
  HOST_ID=$(echo "$HOST_ID" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

  # Display name
  prompt DISPLAY_NAME "Display name (human-readable, shown in message headers)" "${HOST_ID^} ($(hostname))"

  # URL
  header "Step 2/6 — Tailscale Endpoint"
  info "This is the URL other peers use to reach your /hooks/agent endpoint."
  info "Examples: https://myhost.tailXXXXX.ts.net  or  http://100.x.y.z:4440"
  prompt HOST_URL "Your hook URL" ""
  # Strip trailing slash
  HOST_URL="${HOST_URL%/}"

  # Agent ID
  header "Step 3/6 — Agent Identity"
  info "This is your primary assistant agent's ID in your gateway config."
  info "Used to resolve 'main' → 'agent:<id>:main'."
  prompt AGENT_ID "Primary agent ID" ""

  # Relay model
  header "Step 4/6 — Relay Model"
  info "The model used by the Antenna relay agent for tool dispatch."
  info "Use a full provider/model ID (not an alias) for portability."
  info "Examples: openai/gpt-5.4, openai/gpt-5.4-nano-2026-03-17, anthropic/claude-sonnet-4-20250514"
  prompt RELAY_MODEL "Relay model" "openai/gpt-5.4"

  # Token file
  header "Step 5/6 — Hooks Bearer Token"
  info "Path to the file containing your OpenClaw hooks bearer token."
  info "This authenticates HTTP requests to /hooks/agent."
  prompt TOKEN_FILE "Token file path" ""

  if [[ ! -f "$TOKEN_FILE" ]]; then
    warn "Token file not found at: $TOKEN_FILE"
    if prompt_yn "Continue anyway? (you can fix this later)" "y"; then
      true
    else
      err "Setup cancelled — create the token file first."
      exit 1
    fi
  fi

  header "Step 6/6 — Confirmation"
else
  # Non-interactive
  HOST_ID="$NI_HOST_ID"
  DISPLAY_NAME="${NI_DISPLAY:-${HOST_ID^}}"
  HOST_URL="${NI_URL:?--url is required}"
  HOST_URL="${HOST_URL%/}"
  AGENT_ID="${NI_AGENT:?--agent-id is required}"
  RELAY_MODEL="${NI_MODEL:-openai/gpt-5.4}"
  TOKEN_FILE="${NI_TOKEN:?--token-file is required}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "  Host ID:      ${BOLD}$HOST_ID${NC}"
echo -e "  Display name: ${BOLD}$DISPLAY_NAME${NC}"
echo -e "  Hook URL:     ${BOLD}$HOST_URL${NC}"
echo -e "  Agent ID:     ${BOLD}$AGENT_ID${NC}"
echo -e "  Relay model:  ${BOLD}$RELAY_MODEL${NC}"
echo -e "  Token file:   ${BOLD}$TOKEN_FILE${NC}"
echo -e "  Install path: ${BOLD}$SKILL_DIR${NC}"
echo ""

if [[ "$INTERACTIVE" == "true" ]]; then
  if ! prompt_yn "Create configuration with these settings?" "y"; then
    info "Setup cancelled."
    exit 0
  fi
fi

# ── Create config ────────────────────────────────────────────────────────────

jq -n \
  --arg model "$RELAY_MODEL" \
  --arg agent "$AGENT_ID" \
  --arg path "$SKILL_DIR" \
  --arg host "$HOST_ID" \
  '{
    max_message_length: 10000,
    default_target_session: "main",
    relay_agent_id: "antenna",
    relay_agent_model: $model,
    local_agent_id: $agent,
    install_path: $path,
    log_enabled: true,
    log_path: "antenna.log",
    log_max_size_bytes: 10485760,
    log_verbose: false,
    rate_limit: {
      per_peer_per_minute: 10,
      global_per_minute: 30
    },
    mcs_enabled: false,
    mcs_model: "sonnet",
    allowed_inbound_sessions: ["main", "antenna"],
    allowed_inbound_peers: [$host],
    allowed_outbound_peers: [$host]
  }' > "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"
ok "Created $CONFIG_FILE"

# ── Create peers file with self-peer ─────────────────────────────────────────

jq -n \
  --arg id "$HOST_ID" \
  --arg url "$HOST_URL" \
  --arg tf "$TOKEN_FILE" \
  --arg dn "$DISPLAY_NAME" \
  --arg psf "secrets/antenna-peer-${HOST_ID}.secret" \
  '{
    ($id): {
      url: $url,
      token_file: $tf,
      peer_secret_file: $psf,
      agentId: "antenna",
      display_name: $dn,
      self: true
    }
  }' > "$PEERS_FILE"
chmod 644 "$PEERS_FILE"
ok "Created $PEERS_FILE (self-peer: $HOST_ID)"

# ── Generate identity secret ────────────────────────────────────────────────

mkdir -p "$SECRETS_DIR"
SECRET_PATH="$SECRETS_DIR/antenna-peer-${HOST_ID}.secret"
SECRET=$(openssl rand -hex 32)
echo -n "$SECRET" > "$SECRET_PATH"
chmod 600 "$SECRET_PATH"
ok "Generated identity secret: $SECRET_PATH"

# ── Create .gitignore if missing ─────────────────────────────────────────────

GITIGNORE="$SKILL_DIR/.gitignore"
if [[ ! -f "$GITIGNORE" ]]; then
  cat > "$GITIGNORE" <<'GITIGNORE'
# Runtime files — don't version
antenna.log
antenna.log.*
test-results/

# Secrets — never commit
**/secrets/
*.token

# OS junk
.DS_Store
Thumbs.db
antenna-ratelimit.json
GITIGNORE
  ok "Created .gitignore"
fi

# ── Print gateway registration instructions ──────────────────────────────────

echo ""
header "═══ Gateway Registration ═══"
echo ""
echo "  Add the following to your OpenClaw gateway config (openclaw.yaml or equivalent):"
echo ""
echo -e "  ${BOLD}1. Enable hooks:${NC}"
echo "     hooks:"
echo "       enabled: true"
echo "       allowRequestSessionKey: true"
echo "       allowedAgentIds: [\"antenna\"]"
echo "       allowedSessionKeyPrefixes: [\"hook:antenna\"]"
echo ""
echo -e "  ${BOLD}2. Register the Antenna agent:${NC}"
echo "     agents:"
echo "       - id: antenna"
echo "         name: Antenna Relay"
echo "         model: $RELAY_MODEL"
echo "         systemPrompt: |"
echo "           You are the Antenna relay agent. Your ONLY job:"
echo "           1. Run: exec antenna-relay.sh --stdin (pipe the user message to stdin)"
echo "           2. Parse the JSON output"
echo "           3. If action=relay: call sessions_send with the sessionKey and message from the output"
echo "           4. If action=reject: do nothing (message was rejected by the script)"
echo "           Never interpret, summarize, or modify the message content."
echo "         agentsDir: $SKILL_DIR/agent"
echo ""
echo -e "  ${BOLD}3. Restart your gateway:${NC}"
echo "     openclaw gateway restart"
echo ""

header "═══ Next Steps ═══"
echo ""
echo "  1. Register the agent in your gateway config (see above)"
echo "  2. Restart the gateway: openclaw gateway restart"
echo "  3. Add a remote peer:"
echo "     antenna peers add <peer-id> --url <url> --token-file <path>"
echo "  4. Exchange identity secrets with that peer:"
echo "     antenna peers exchange <peer-id>"
echo "  5. Test connectivity:"
echo "     antenna peers test <peer-id>"
echo "  6. Send your first message:"
echo "     antenna msg <peer-id> \"Hello from the other side!\""
echo ""
ok "Setup complete! Your host ID is: ${BOLD}$HOST_ID${NC}"
echo ""
