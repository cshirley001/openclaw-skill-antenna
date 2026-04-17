#!/usr/bin/env bash
# antenna-doctor.sh — Pre-flight and post-install health check for Antenna.
# Verifies gateway config has required entries and is valid JSON.
# Optionally backs up the gateway config before changes.
#
# Usage:
#   antenna doctor                     Full check
#   antenna doctor --backup            Back up openclaw.json before any changes
#   antenna doctor --fix-hints         Show copy-paste fix commands
#   antenna doctor --gateway <path>    Override gateway config path
#
set -uo pipefail
# Note: set -e intentionally omitted — diagnostic tool must not abort on non-fatal failures

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SKILL_DIR/antenna-config.json"
PEERS_FILE="$SKILL_DIR/antenna-peers.json"

# Peer-shape filter: only iterate entries that are objects with a .url string
PEER_JQ_KEYS='to_entries[] | select((.value | type) == "object" and (.value.url? | type) == "string") | .key'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0
FIX_HINTS=false
DO_BACKUP=false
GATEWAY_PATH=""

# ── Helpers ──────────────────────────────────────────────────────────────────

pass() { echo -e "  ${GREEN}✓${NC}  $*"; PASS=$((PASS + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; WARN=$((WARN + 1)); }
fail() { echo -e "  ${RED}✗${NC}  $*"; FAIL=$((FAIL + 1)); }
info() { echo -e "  ${CYAN}ℹ${NC}  $*"; }
hint() { [[ "$FIX_HINTS" == true ]] && echo -e "     ${CYAN}→ $*${NC}"; }

# ── Parse flags ──────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup)      DO_BACKUP=true; shift ;;
    --fix-hints)   FIX_HINTS=true; shift ;;
    --gateway)     GATEWAY_PATH="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
antenna doctor — Health check for Antenna installation

Usage:
  antenna doctor                     Full diagnostic check
  antenna doctor --backup            Back up gateway config first
  antenna doctor --fix-hints         Show copy-paste fix suggestions
  antenna doctor --gateway <path>    Override gateway config path

Checks:
  1. Antenna config files exist and are valid JSON
  2. Gateway config exists and is valid JSON
  3. Hooks are enabled with correct settings
  4. Antenna agent is registered
  5. Required allowlist entries are present
  6. Secret files exist with correct permissions
  7. Peer connectivity (basic)
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Locate gateway config ───────────────────────────────────────────────────

find_gateway_config() {
  if [[ -n "$GATEWAY_PATH" ]]; then
    echo "$GATEWAY_PATH"
    return
  fi

  # Standard locations
  local candidates=(
    "$HOME/.openclaw/openclaw.json"
    "/home/$USER/.openclaw/openclaw.json"
  )
  # Add OPENCLAW_HOME if set
  [[ -n "${OPENCLAW_HOME:-}" ]] && candidates+=("$OPENCLAW_HOME/openclaw.json")

  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      echo "$c"
      return
    fi
  done

  echo ""
}

GATEWAY_CONFIG=$(find_gateway_config)

# ── Banner ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}📡 Antenna Doctor — Installation Health Check${NC}"
echo ""

# ── 1. Antenna config files ─────────────────────────────────────────────────

echo -e "${BOLD}1. Antenna Configuration${NC}"

if [[ -f "$CONFIG_FILE" ]]; then
  if jq empty "$CONFIG_FILE" 2>/dev/null; then
    pass "antenna-config.json exists and is valid JSON"
  else
    fail "antenna-config.json exists but is INVALID JSON"
    hint "Fix syntax errors in: $CONFIG_FILE"
  fi
else
  fail "antenna-config.json not found"
  hint "Run: antenna setup"
fi

if [[ -f "$PEERS_FILE" ]]; then
  if jq empty "$PEERS_FILE" 2>/dev/null; then
    pass "antenna-peers.json exists and is valid JSON"

    # Check self-peer exists
    local_self=$(jq -r 'to_entries[] | select(.value.self == true) | .key' "$PEERS_FILE" 2>/dev/null || echo "")
    if [[ -n "$local_self" ]]; then
      pass "Self-peer found: $local_self"
    else
      fail "No self-peer defined (no entry with \"self\": true)"
      hint "Add a self entry to antenna-peers.json or re-run: antenna setup"
    fi
  else
    fail "antenna-peers.json exists but is INVALID JSON"
    hint "Fix syntax errors in: $PEERS_FILE"
  fi
else
  fail "antenna-peers.json not found"
  hint "Run: antenna setup"
fi

echo ""

# ── 2. Gateway config ───────────────────────────────────────────────────────

echo -e "${BOLD}2. Gateway Configuration${NC}"

if [[ -z "$GATEWAY_CONFIG" ]]; then
  fail "Gateway config not found (checked ~/.openclaw/openclaw.json)"
  hint "Specify with: antenna doctor --gateway /path/to/openclaw.json"
  echo ""
  echo -e "${BOLD}3–5. Skipped${NC} (no gateway config found)"
  echo ""
else
  if jq empty "$GATEWAY_CONFIG" 2>/dev/null; then
    pass "Gateway config is valid JSON: $GATEWAY_CONFIG"
  else
    fail "Gateway config is INVALID JSON: $GATEWAY_CONFIG"
    echo ""
    echo -e "  ${RED}⚠  THIS IS CRITICAL — your OpenClaw gateway will not start with invalid JSON.${NC}"
    echo ""

    # Try to identify the error
    json_err=$(jq empty "$GATEWAY_CONFIG" 2>&1 || true)
    if [[ -n "$json_err" ]]; then
      echo -e "  ${RED}  Error: $json_err${NC}"
    fi

    hint "Restore from backup: cp ${GATEWAY_CONFIG}.antenna-backup $GATEWAY_CONFIG"
    hint "Or validate with: jq empty $GATEWAY_CONFIG"
    echo ""
    echo -e "${BOLD}3–5. Skipped${NC} (gateway config is invalid)"
    echo ""

    # Jump to summary
    echo -e "${BOLD}═══ Summary ═══${NC}"
    echo ""
    echo -e "  ${GREEN}Passed: $PASS${NC}  ${YELLOW}Warnings: $WARN${NC}  ${RED}Failed: $FAIL${NC}"
    echo ""
    if [[ $FAIL -gt 0 ]]; then
      echo -e "  ${RED}Gateway config is broken — fix this first!${NC}"
      echo -e "  If you have a backup: ${CYAN}cp ${GATEWAY_CONFIG}.antenna-backup $GATEWAY_CONFIG${NC}"
      echo -e "  Then restart: ${CYAN}openclaw gateway restart${NC}"
    fi
    echo ""
    exit 1
  fi

  # ── Backup if requested ──────────────────────────────────────────────────

  if [[ "$DO_BACKUP" == true ]]; then
    backup_path="${GATEWAY_CONFIG}.antenna-backup"
    cp "$GATEWAY_CONFIG" "$backup_path"
    chmod 600 "$backup_path"
    pass "Backup created: $backup_path"
  fi

  echo ""

  # ── 3. Hooks configuration ──────────────────────────────────────────────

  echo -e "${BOLD}3. Hooks Configuration${NC}"

  hooks_enabled=$(jq -r '.hooks.enabled // false' "$GATEWAY_CONFIG" 2>/dev/null)
  if [[ "$hooks_enabled" == "true" ]]; then
    pass "hooks.enabled = true"
  else
    fail "hooks.enabled is not true"
    hint "Add to gateway config: \"hooks\": { \"enabled\": true, ... }"
  fi

  allow_session=$(jq -r '.hooks.allowRequestSessionKey // false' "$GATEWAY_CONFIG" 2>/dev/null)
  if [[ "$allow_session" == "true" ]]; then
    pass "hooks.allowRequestSessionKey = true"
  else
    fail "hooks.allowRequestSessionKey is not true"
    hint "Set hooks.allowRequestSessionKey: true in gateway config"
  fi

  # Check allowedAgentIds contains "antenna"
  has_antenna_agent=$(jq -r '.hooks.allowedAgentIds // [] | map(select(. == "antenna")) | length' "$GATEWAY_CONFIG" 2>/dev/null)
  if [[ "$has_antenna_agent" -gt 0 ]]; then
    pass "hooks.allowedAgentIds includes \"antenna\""
  else
    fail "hooks.allowedAgentIds does not include \"antenna\""
    hint "Add \"antenna\" to hooks.allowedAgentIds array"
  fi

  # Check allowedSessionKeyPrefixes
  has_hook_prefix=$(jq -r '.hooks.allowedSessionKeyPrefixes // [] | map(select(. == "hook:" or . == "hook:antenna" or startswith("hook"))) | length' "$GATEWAY_CONFIG" 2>/dev/null)
  if [[ "$has_hook_prefix" -gt 0 ]]; then
    pass "hooks.allowedSessionKeyPrefixes includes hook prefix"
  else
    warn "hooks.allowedSessionKeyPrefixes may not include \"hook:\" or \"hook:antenna\""
    hint "Add \"hook:antenna\" to hooks.allowedSessionKeyPrefixes array"
  fi

  echo ""

  # ── 4. Agent registration ──────────────────────────────────────────────

  echo -e "${BOLD}4. Agent Registration${NC}"

  # Check for antenna agent in agents.list (array) or agents (map)
  has_agent=false

  # Try agents.list array format
  agent_in_list=$(jq -r '.agents.list // [] | map(select(.id == "antenna" or .name == "antenna" or (.name // "" | ascii_downcase) == "antenna relay")) | length' "$GATEWAY_CONFIG" 2>/dev/null)
  if [[ "$agent_in_list" -gt 0 ]]; then
    has_agent=true
  fi

  # Try agents map format
  if [[ "$has_agent" == false ]]; then
    agent_in_map=$(jq -r '.agents.antenna // empty' "$GATEWAY_CONFIG" 2>/dev/null)
    if [[ -n "$agent_in_map" ]]; then
      has_agent=true
    fi
  fi

  if [[ "$has_agent" == true ]]; then
    pass "Antenna agent is registered in gateway config"
  else
    fail "Antenna agent not found in gateway config"
    hint "Register the antenna agent — see: antenna setup (prints the config block)"
  fi

  echo ""

  # ── 5. Token present ──────────────────────────────────────────────────

  echo -e "${BOLD}5. Hooks Token${NC}"

  hooks_token=$(jq -r '.hooks.token // empty' "$GATEWAY_CONFIG" 2>/dev/null)
  if [[ -n "$hooks_token" ]]; then
    token_len=${#hooks_token}
    if [[ $token_len -ge 20 ]]; then
      pass "Hooks token is set (${token_len} chars)"
    else
      warn "Hooks token seems short (${token_len} chars) — consider using a stronger token"
      hint "Generate with: openssl rand -base64 32"
    fi
  else
    fail "No hooks token configured"
    hint "Set hooks.token in gateway config"
  fi

  echo ""
fi

# ── 6. Secret files ─────────────────────────────────────────────────────────

echo -e "${BOLD}6. Secrets & Permissions${NC}"

if [[ -f "$PEERS_FILE" ]]; then
  while IFS= read -r peer_id; do
    [[ -z "$peer_id" ]] && continue

    # Token file
    tf=$(jq -r --arg p "$peer_id" '.[$p].token_file // empty' "$PEERS_FILE" 2>/dev/null)
    if [[ -n "$tf" ]]; then
      # Resolve relative paths
      [[ "$tf" != /* ]] && tf="$SKILL_DIR/$tf"

      if [[ -f "$tf" ]]; then
        perms=$(stat -c '%a' "$tf" 2>/dev/null || stat -f '%Lp' "$tf" 2>/dev/null || echo "unknown")
        if [[ "$perms" == "600" || "$perms" == "400" ]]; then
          pass "$peer_id: token file OK ($perms)"
        else
          warn "$peer_id: token file permissions ($perms) — should be 600"
          hint "chmod 600 $tf"
        fi
      else
        fail "$peer_id: token file missing: $tf"
      fi
    fi

    # Peer secret file
    psf=$(jq -r --arg p "$peer_id" '.[$p].peer_secret_file // empty' "$PEERS_FILE" 2>/dev/null)
    if [[ -n "$psf" ]]; then
      [[ "$psf" != /* ]] && psf="$SKILL_DIR/$psf"

      if [[ -f "$psf" ]]; then
        ps_perms=$(stat -c '%a' "$psf" 2>/dev/null || stat -f '%Lp' "$psf" 2>/dev/null || echo "unknown")
        if [[ "$ps_perms" == "600" || "$ps_perms" == "400" ]]; then
          pass "$peer_id: peer secret OK ($ps_perms)"
        else
          warn "$peer_id: peer secret permissions ($ps_perms) — should be 600"
          hint "chmod 600 $psf"
        fi
      else
        is_self_check=$(jq -r --arg p "$peer_id" '.[$p].self // false' "$PEERS_FILE" 2>/dev/null)
        if [[ "$is_self_check" == "true" ]]; then
          fail "$peer_id (self): identity secret missing: $psf"
          hint "Run: antenna setup (or openssl rand -hex 32 > $psf && chmod 600 $psf)"
        else
          warn "$peer_id: peer secret file missing: $psf (sender won't be verified)"
          hint "Run: antenna peers exchange $peer_id"
        fi
      fi
    else
      is_self=$(jq -r --arg p "$peer_id" '.[$p].self // false' "$PEERS_FILE" 2>/dev/null)
      if [[ "$is_self" == "true" ]]; then
        warn "$peer_id (self): no peer_secret_file configured"
        hint "Run: antenna setup --force (or add peer_secret_file to your self-peer entry)"
      fi
    fi
  done < <(jq -r "$PEER_JQ_KEYS" "$PEERS_FILE" 2>/dev/null)
else
  warn "Cannot check secrets — no peers file"
fi

echo ""

# ── 7. Basic connectivity ───────────────────────────────────────────────────

echo -e "${BOLD}7. Connectivity (quick check)${NC}"

if [[ -f "$PEERS_FILE" ]]; then
  while IFS= read -r peer_id; do
    [[ -z "$peer_id" ]] && continue

    is_self=$(jq -r --arg p "$peer_id" '.[$p].self // false' "$PEERS_FILE" 2>/dev/null)
    [[ "$is_self" == "true" ]] && continue

    peer_url=$(jq -r --arg p "$peer_id" '.[$p].url // empty' "$PEERS_FILE" 2>/dev/null)
    [[ -z "$peer_url" ]] && continue

    # Quick reachability check (5s timeout)
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 "${peer_url}" 2>/dev/null) || true

    # Normalize: strip anything non-numeric, treat empty/zero as unreachable
    http_code="${http_code//[^0-9]/}"
    http_code="${http_code:-000}"

    if [[ "$http_code" == "000" || "$http_code" == "0" ]]; then
      warn "$peer_id ($peer_url): unreachable"
      hint "Check: is the peer online? Is Tailscale Funnel/tunnel active?"
    elif [[ "$http_code" -ge 200 && "$http_code" -lt 500 ]]; then
      pass "$peer_id ($peer_url): reachable (HTTP $http_code)"
    else
      warn "$peer_id ($peer_url): responded with HTTP $http_code"
    fi
  done < <(jq -r "$PEER_JQ_KEYS" "$PEERS_FILE" 2>/dev/null)
else
  warn "Cannot check connectivity — no peers file"
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo -e "${BOLD}═══ Summary ═══${NC}"
echo ""
echo -e "  ${GREEN}Passed: $PASS${NC}  ${YELLOW}Warnings: $WARN${NC}  ${RED}Failed: $FAIL${NC}"
echo ""

if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
  echo -e "  ${GREEN}All checks passed — Antenna is healthy! 📡${NC}"
elif [[ $FAIL -eq 0 ]]; then
  echo -e "  ${YELLOW}No critical issues, but $WARN warning(s) to review.${NC}"
else
  echo -e "  ${RED}$FAIL critical issue(s) found — fix these before using Antenna.${NC}"
  if [[ "$FIX_HINTS" == false ]]; then
    echo -e "  Run with ${CYAN}--fix-hints${NC} for suggested fixes."
  fi
fi

if [[ $FAIL -gt 0 || $WARN -gt 0 ]]; then
  echo -e "  Still stuck? ${CYAN}help@clawreef.io${NC} · ${CYAN}https://github.com/ClawReefAntenna/antenna/issues${NC}"
fi

echo ""

# Exit code: 0 = all good, 1 = failures present
[[ $FAIL -eq 0 ]]
