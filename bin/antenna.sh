#!/usr/bin/env bash
# antenna — CLI dispatcher for Antenna inter-host messaging.
#
# Usage:
#   antenna send <peer> [options] <message>
#   antenna peers list | add | remove | test
#   antenna config show | set <key> <value>
#   antenna log [--tail <n>] [--since <duration>]
#   antenna status
#
set -euo pipefail

# Resolve symlinks to find real location
REAL_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$SKILL_DIR/scripts"

# ── Self-healing permissions ─────────────────────────────────────────────────
# ClawHub doesn't preserve execute bits. Fix them on first run so install.sh
# is optional and everything Just Works after `clawhub install antenna`.
_fix_perms() {
  local fixed=0
  for f in "$SCRIPT_DIR"/*.sh "$SCRIPTS_DIR"/*.sh; do
    if [[ -f "$f" && ! -x "$f" ]]; then
      chmod +x "$f" 2>/dev/null && fixed=$((fixed + 1))
    fi
  done
  if [[ $fixed -gt 0 ]]; then
    echo -e "\033[0;36mℹ\033[0m  Fixed execute permissions on $fixed file(s)." >&2
  fi
}
_fix_perms
PEERS_FILE="$SKILL_DIR/antenna-peers.json"
CONFIG_FILE="$SKILL_DIR/antenna-config.json"

# ── Peer-shape validation helpers ────────────────────────────────────────────
# Only iterate entries that look like real peers (object with a .url string).
# This prevents legacy/malformed nested objects from polluting peer lists.

PEER_FILTER='select((.value | type) == "object" and (.value.url? | type) == "string")'

valid_peer_ids() {
  jq -r "to_entries[] | $PEER_FILTER | .key" "$PEERS_FILE" 2>/dev/null
}

remote_peer_ids() {
  jq -r "to_entries[] | $PEER_FILTER | select(.value.self != true) | .key" "$PEERS_FILE" 2>/dev/null
}

self_peer_id() {
  jq -r "to_entries[] | $PEER_FILTER | select(.value.self == true) | .key" "$PEERS_FILE" 2>/dev/null | head -n 1
}

self_peer_url() {
  jq -r "to_entries[] | $PEER_FILTER | select(.value.self == true) | .value.url" "$PEERS_FILE" 2>/dev/null | head -n 1
}

invalid_peer_keys() {
  jq -r 'to_entries[] | select((.value | type) != "object" or (.value.url? | type) != "string") | .key' "$PEERS_FILE" 2>/dev/null
}

# ── Setup guard ──────────────────────────────────────────────────────────────
# If config doesn't exist yet, only setup/help/--help/-h are allowed.
_peek_command="${1:-}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  case "$_peek_command" in
    setup|help|-h|--help) ;; # allow through
    *)
      echo ""
      echo "  Antenna is not configured yet."
      echo ""
      echo "  Run:  antenna setup"
      echo "    or: bash $(realpath "$0" 2>/dev/null || echo "$0") setup"
      echo ""
      exit 1
      ;;
  esac
fi

LOG_FILE="$SKILL_DIR/$(jq -r '.log_path // "antenna.log"' "$CONFIG_FILE" 2>/dev/null || echo "antenna.log")"

usage() {
  cat <<'EOF'
Antenna — Inter-Host OpenClaw Messaging

Usage:
  antenna setup                              First-run setup wizard
  antenna setup --host-id <id> ...           Non-interactive setup (see --help)
  antenna pair [--peer-id <id>]              Interactive peer pairing wizard
  antenna uninstall [options]                Remove Antenna runtime state / optional gateway config

  antenna doctor                             Health check: verify gateway config, secrets, connectivity
  antenna doctor --backup                    Back up gateway config before changes
  antenna doctor --fix-hints                 Show copy-paste fix suggestions
  antenna doctor --gateway <path>            Override gateway config path

  antenna send <peer> [options] <message>    Send a message to a peer
  antenna send <peer> [options] --stdin      Send message from stdin
  antenna msg <peer> [message]               Quick send (plain host mode by default)

  antenna peers list                         List known peers
  antenna peers add <id> --url <url> --token-file <path> [--peer-secret-file <path>] [--exchange-public-key <age-pub>] [--display-name <name>]
  antenna peers remove <id>
  antenna peers test <id>                    Test connectivity to a peer
  antenna peers generate-secret <id>         Generate a per-peer auth secret
  antenna peers exchange keygen [--force]    Generate local age exchange keypair
  antenna peers exchange pubkey [--bare] [--email ...] Show/email local age exchange public key
  antenna peers exchange initiate <id> ...   Create encrypted bootstrap bundle
  antenna peers exchange import [file|-]     Import encrypted bootstrap bundle
  antenna peers exchange reply <id> ...      Create reciprocal encrypted bundle
  antenna peers exchange <id> --import <file>      Legacy raw-secret import
  antenna peers exchange <id> --import-value <hex> Legacy raw-secret import by value
  antenna peers exchange <id> --export             Legacy raw-secret export

  antenna inbox list                         Show pending queued messages
  antenna inbox count                        Count pending messages
  antenna inbox show <ref>                   Show full message for a ref
  antenna inbox approve all|<refs>           Approve messages (e.g., 1,3,5-7)
  antenna inbox deny all|<refs>              Deny/reject messages
  antenna inbox drain [--execute]            Deliver approved, remove denied
  antenna inbox clear                        Remove all processed messages

  antenna sessions list                      Show allowed inbound session targets
  antenna sessions add <name> [<name>...]    Add session target(s) to the allowlist
  antenna sessions remove <name> [<name>...] Remove session target(s) (core sessions need --force)

  antenna config show                        Show current configuration
  antenna config set <key> <value>           Update a config value (syncs relay_agent_model to gateway)

  antenna model show                         Show current relay model
  antenna model set <model>                  Set relay model (syncs to gateway + restarts)

  antenna log [--tail <n>]                   View transaction log (default: last 20)
  antenna log --since <duration>             Show entries from last N minutes/hours

  antenna status                             Overall status summary

  antenna test <model> [options]             Self-loop integration test (end-to-end)
    --runs <n>                               Number of test iterations (default: 1)
    --timeout <sec>                          Per-run relay timeout (default: 15s)
    --keep-model                             Leave candidate model active after test

  antenna test-suite [options]               Three-tier model/script test suite
    --model <model>                          Single provider/model ID for B/C tiers
    --models <m1,m2,...>                     Comma-separated models for comparison (max 6)
    --tier A|B|C|all                         Run specific tier (default: all)
    --verbose                                Show full request/response payloads inline
    --report [dir]                           Save structured report (default: test-results/)
    --format terminal|markdown|json          Output format (default: terminal)
    --compare                                Enable comparison table (implied by --models)

Send options:
  --session <key>     Target session on recipient (default: main)
  --subject <text>    Optional subject line
  --user <name>       Optional human sender name (plain host mode is default)
  --reply-to <url>    Override reply URL
  --dry-run           Print envelope without sending

Examples:
  antenna msg <peer> "What's the weather like over there?"
  antenna msg <peer>                      # prompts for message interactively
  echo "long message" | antenna send <peer> --stdin --user "Your Name"
EOF
  exit 0
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_setup() {
  bash "$SCRIPTS_DIR/antenna-setup.sh" "$@"
}

cmd_pair() {
  bash "$SCRIPTS_DIR/antenna-pair.sh" "$@"
}

cmd_uninstall() {
  bash "$SCRIPTS_DIR/antenna-uninstall.sh" "$@"
}

cmd_send() {
  bash "$SCRIPTS_DIR/antenna-send.sh" "$@"
}

cmd_msg() {
  # Quick send: plain/original relay mode by default; prompts if no message
  local peer="${1:-}"
  shift || true

  if [[ -z "$peer" ]]; then
    # If only one remote peer, use it; otherwise list and ask
    local remote_peers
    remote_peers=$(remote_peer_ids)
    local peer_count
    peer_count=$(echo "$remote_peers" | grep -c '.' || echo "0")

    if [[ "$peer_count" -eq 1 ]]; then
      peer="$remote_peers"
      echo "→ Sending to: $peer"
    else
      echo "Available peers:"
      echo "$remote_peers" | while read -r p; do
        local dn
        dn=$(jq -r --arg p "$p" '.[$p].display_name // "—"' "$PEERS_FILE" 2>/dev/null)
        echo "  $p ($dn)"
      done
      echo ""
      read -rp "Peer: " peer
    fi
  fi

  # Parse msg options; stay plain/original unless --user is explicitly supplied.
  local explicit_user=""
  local msg_session=""
  local msg_subject=""
  local msg_reply_to=""
  local msg_dry_run=false
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) explicit_user="$2"; shift 2 ;;
      --session) msg_session="$2"; shift 2 ;;
      --subject) msg_subject="$2"; shift 2 ;;
      --reply-to) msg_reply_to="$2"; shift 2 ;;
      --dry-run) msg_dry_run=true; shift ;;
      -h|--help) usage ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  # Get message from remaining args or prompt
  local message=""
  if [[ ${#positional[@]} -gt 0 ]]; then
    message="${positional[*]}"
  else
    echo "Type your message (Ctrl-D or empty line to send):"
    local line
    while IFS= read -r line; do
      [[ -z "$line" && -n "$message" ]] && break
      if [[ -n "$message" ]]; then
        message="${message}
${line}"
      else
        message="$line"
      fi
    done
  fi

  if [[ -z "$message" ]]; then
    echo "No message entered. Cancelled." >&2
    exit 1
  fi

  echo ""
  local send_args=("$peer")
  [[ -n "$msg_session" ]] && send_args+=(--session "$msg_session")
  [[ -n "$msg_subject" ]] && send_args+=(--subject "$msg_subject")
  [[ -n "$msg_reply_to" ]] && send_args+=(--reply-to "$msg_reply_to")
  [[ "$msg_dry_run" == true ]] && send_args+=(--dry-run)

  if [[ -n "$explicit_user" ]]; then
    echo "Sending as $explicit_user to $peer..."
    send_args+=(--user "$explicit_user")
  else
    echo "Sending from $(hostname) to $peer..."
  fi

  send_args+=("$message")
  bash "$SCRIPTS_DIR/antenna-send.sh" "${send_args[@]}"
}

cmd_inbox() {
  bash "$SCRIPTS_DIR/antenna-inbox.sh" "$@"
}

cmd_peers() {
  local subcmd="${1:-list}"
  shift || true

  case "$subcmd" in
    list)
      echo "Known peers:"
      echo ""
      local peer_rows invalid_keys
      peer_rows=$(jq -r 'to_entries[] | select((.value | type) == "object" and (.value.url? | type) == "string") | "  \(.key)\(if .value.self then " (self)" else "" end)\n    URL:   \(.value.url)\n    Agent: \(.value.agentId // "antenna")\n    Name:  \(.value.display_name // "—")\n    Exchange key: \(if .value.exchange_public_key then "set" else "—" end)\n"' "$PEERS_FILE" 2>/dev/null)
      if [[ -n "$peer_rows" ]]; then
        printf '%s\n' "$peer_rows"
      else
        echo "  (none)"
      fi
      invalid_keys=$(invalid_peer_keys | tr '\n' ',' | sed 's/,$//')
      if [[ -n "$invalid_keys" ]]; then
        echo "Ignored malformed registry entries: $invalid_keys"
      fi
      ;;

    add)
      local id="" url="" token_file="" display_name="" peer_secret_file="" exchange_public_key=""
      id="${1:?Usage: antenna peers add <id> --url <url> --token-file <path> [--peer-secret-file <path>] [--exchange-public-key <age-pub>]}"
      shift
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --url)              url="$2"; shift 2 ;;
          --token-file)       token_file="$2"; shift 2 ;;
          --peer-secret-file) peer_secret_file="$2"; shift 2 ;;
          --exchange-public-key) exchange_public_key="$2"; shift 2 ;;
          --display-name)     display_name="$2"; shift 2 ;;
          *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
      done
      if [[ -z "$url" || -z "$token_file" ]]; then
        echo "Error: --url and --token-file are required" >&2; exit 1
      fi
      local tmp
      tmp=$(mktemp)
      jq --arg id "$id" --arg url "$url" --arg tf "$token_file" --arg dn "$display_name" --arg psf "$peer_secret_file" --arg xpk "$exchange_public_key" \
        '.[$id] = {url: $url, token_file: $tf, agentId: "antenna", display_name: (if $dn == "" then null else $dn end), peer_secret_file: (if $psf == "" then null else $psf end), exchange_public_key: (if $xpk == "" then null else $xpk end)}' \
        "$PEERS_FILE" > "$tmp" && mv "$tmp" "$PEERS_FILE"
      echo "Added peer: $id ($url)"
      if [[ -n "$peer_secret_file" ]]; then
        echo "Per-peer secret: $peer_secret_file"
      fi
      if [[ -n "$exchange_public_key" ]]; then
        echo "Exchange public key: set"
      fi

      # Prompt to add peer to allowlists (default: yes)
      local add_to_lists=true
      if [[ -t 0 && -t 1 ]]; then
        echo ""
        local yn
        read -rp "Add $id to inbound/outbound allowlists? [y]: " yn
        yn="${yn:-y}"
        if [[ "${yn,,}" != "y" && "${yn,,}" != "yes" ]]; then
          add_to_lists=false
        fi
      fi

      if [[ "$add_to_lists" == "true" ]]; then
        local cfg_tmp
        cfg_tmp=$(mktemp)
        jq --arg p "$id" '
          .allowed_inbound_peers = ((.allowed_inbound_peers // []) | if (index($p) | not) then . + [$p] else . end) |
          .allowed_outbound_peers = ((.allowed_outbound_peers // []) | if (index($p) | not) then . + [$p] else . end)
        ' "$CONFIG_FILE" > "$cfg_tmp" && mv "$cfg_tmp" "$CONFIG_FILE"
        echo "✓ Added $id to allowed_inbound_peers and allowed_outbound_peers"
      else
        echo "⚠ Peer added but NOT in allowlists. Run: antenna config set allowed_outbound_peers '[\"...\"]' to allow sending."
      fi
      ;;

    exchange)
      bash "$SCRIPTS_DIR/antenna-exchange.sh" "$@"
      ;;

    generate-secret)
      local target_id="${1:-}"
      local secret_dir="$SKILL_DIR/secrets"
      mkdir -p "$secret_dir"

      local secret
      secret=$(openssl rand -hex 32)

      if [[ -n "$target_id" ]]; then
        local secret_path="$secret_dir/antenna-peer-${target_id}.secret"
        echo -n "$secret" > "$secret_path"
        chmod 600 "$secret_path"
        echo "Generated per-peer secret for: $target_id"
        echo "  File: $secret_path"
        echo "  Secret: $secret"
        echo ""
        echo "Next steps:"
        echo "  1. Copy this secret file to the peer host"
        echo "  2. On THIS host: ensure antenna-peers.json has peer_secret_file for $target_id"
        echo "  3. On PEER host: add YOUR peer entry with peer_secret_file pointing to this secret"
      else
        echo "Generated secret: $secret"
        echo ""
        echo "Usage: antenna peers generate-secret <peer-id>"
        echo "  This creates secrets/antenna-peer-<id>.secret and prints setup instructions."
      fi
      ;;

    remove)
      local id="${1:?Usage: antenna peers remove <id>}"
      local tmp
      tmp=$(mktemp)
      jq --arg id "$id" 'del(.[$id])' "$PEERS_FILE" > "$tmp" && mv "$tmp" "$PEERS_FILE"
      echo "Removed peer: $id"
      ;;

    test)
      local id="${1:?Usage: antenna peers test <id>}"
      local peer_url token_file token
      peer_url=$(jq -r --arg p "$id" '.[$p].url // empty' "$PEERS_FILE")
      token_file=$(jq -r --arg p "$id" '.[$p].token_file // empty' "$PEERS_FILE")

      if [[ -z "$peer_url" ]]; then
        echo "Unknown peer: $id" >&2; exit 1
      fi

      # Resolve relative token paths against SKILL_DIR
      [[ "$token_file" != /* ]] && token_file="$SKILL_DIR/$token_file"
      token=$(cat "$token_file" 2>/dev/null || echo "")
      echo "Testing connectivity to $id ($peer_url)..."

      local http_code
      http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -X POST "${peer_url}/hooks/agent" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{"message":"[ANTENNA_PING]","agentId":"antenna","sessionKey":"hook:antenna"}' 2>&1) || {
        echo "FAILED: Connection error (peer unreachable)"
        exit 1
      }

      case "$http_code" in
        200) echo "OK: Peer responded (HTTP 200)" ;;
        401|403) echo "AUTH FAILED: Token rejected (HTTP $http_code)" ;;
        *) echo "UNEXPECTED: HTTP $http_code" ;;
      esac
      ;;

    *)
      echo "Unknown peers subcommand: $subcmd" >&2
      echo "Usage: antenna peers list|add|remove|test|exchange|generate-secret" >&2
      exit 1
      ;;
  esac
}

_sync_relay_model_to_gateway() {
  local new_model="$1"
  local gateway_cfg=""
  for candidate in "$HOME/.openclaw/openclaw.json" "/home/$USER/.openclaw/openclaw.json"; do
    if [[ -f "$candidate" ]]; then
      gateway_cfg="$candidate"
      break
    fi
  done

  if [[ -z "$gateway_cfg" ]]; then
    echo "⚠  Gateway config not found — skipping gateway sync. Update manually."
    return
  fi

  local has_antenna
  has_antenna=$(jq '[.agents.list // [] | .[] | select(.id == "antenna")] | length' "$gateway_cfg" 2>/dev/null || echo "0")
  if [[ "$has_antenna" -eq 0 ]]; then
    echo "⚠  Antenna agent not registered in gateway config ($gateway_cfg) — skipping gateway sync."
    return
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg model "$new_model" '
    .agents.list = [.agents.list[] | if .id == "antenna" then .model = $model else . end]
  ' "$gateway_cfg" > "$tmp" && mv "$tmp" "$gateway_cfg"
  echo "✓  Updated gateway config: antenna agent model → $new_model"

  if command -v openclaw &>/dev/null 2>&1; then
    echo "↻  Restarting gateway..."
    openclaw gateway restart
    echo "✓  Gateway restarted"
  else
    echo "⚠  openclaw not found in PATH — restart gateway manually: openclaw gateway restart"
  fi
}

cmd_sessions() {
  local subcmd="${1:-list}"
  shift || true

  local key="allowed_inbound_sessions"
  local local_agent
  local_agent=$(jq -r '.local_agent_id // "agent"' "$CONFIG_FILE" 2>/dev/null || echo "agent")
  local defaults="[\"agent:${local_agent}:main\",\"agent:${local_agent}:antenna\"]"

  # Normalize a session name to a full key (expand bare names)
  _normalize_session() {
    local name="$1"
    if [[ "$name" == *:* ]]; then
      echo "$name"
    else
      echo "agent:${local_agent}:${name}"
    fi
  }

  case "$subcmd" in
    list|ls)
      echo "Allowed inbound sessions:"
      echo ""
      jq -r --argjson d "$defaults" '.[$key] // $d | to_entries[] | "  \(.value)"' --arg key "$key" "$CONFIG_FILE"
      local count
      count=$(jq -r --argjson d "$defaults" --arg key "$key" '.[$key] // $d | length' "$CONFIG_FILE")
      echo ""
      echo "($count session target(s) allowed)"
      ;;

    add)
      if [[ $# -eq 0 ]]; then
        echo "Usage: antenna sessions add <name> [<name>...]" >&2
        exit 1
      fi
      local added=0 skipped=0
      for raw_name in "$@"; do
        local name
        name=$(_normalize_session "$raw_name")
        if [[ "$raw_name" != "$name" ]]; then
          echo "  →  Expanded '$raw_name' → '$name'"
        fi
        local already
        already=$(jq -r --argjson d "$defaults" --arg key "$key" --arg n "$name" \
          '(.[$key] // $d) | if (index($n) | not) then "no" else "yes" end' "$CONFIG_FILE")
        if [[ "$already" == "yes" ]]; then
          echo "  ⚠  '$name' already in allowlist — skipped"
          skipped=$((skipped + 1))
          continue
        fi
        local tmp
        tmp=$(mktemp)
        jq --argjson d "$defaults" --arg key "$key" --arg n "$name" \
          '.[$key] = ((.[$key] // $d) + [$n])' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        echo "  ✓  Added '$name'"
        added=$((added + 1))
      done
      echo ""
      echo "Added $added, skipped $skipped."
      if [[ $added -gt 0 ]]; then
        echo ""
        echo "Current allowlist:"
        jq -r --argjson d "$defaults" --arg key "$key" '.[$key] // $d | .[]' "$CONFIG_FILE" | sed 's/^/  /'
      fi
      ;;

    remove|rm)
      if [[ $# -eq 0 ]]; then
        echo "Usage: antenna sessions remove <name> [<name>...]" >&2
        exit 1
      fi
      local removed=0 blocked=0 notfound=0
      local protected=("agent:${local_agent}:main" "agent:${local_agent}:antenna")
      local force=false
      # Check for --force flag
      local names=()
      for arg in "$@"; do
        if [[ "$arg" == "--force" || "$arg" == "-f" ]]; then
          force=true
        else
          names+=("$arg")
        fi
      done

      for raw_name in "${names[@]}"; do
        local name
        name=$(_normalize_session "$raw_name")
        if [[ "$raw_name" != "$name" ]]; then
          echo "  →  Expanded '$raw_name' → '$name'"
        fi
        # Check if it exists
        local exists
        exists=$(jq -r --argjson d "$defaults" --arg key "$key" --arg n "$name" \
          '(.[$key] // $d) | if (index($n) | not) then "no" else "yes" end' "$CONFIG_FILE")
        if [[ "$exists" == "no" ]]; then
          echo "  ⚠  '$name' not in allowlist — skipped"
          notfound=$((notfound + 1))
          continue
        fi

        # Protect core sessions unless --force
        if [[ "$force" != true ]]; then
          for p in "${protected[@]}"; do
            if [[ "$name" == "$p" ]]; then
              echo "  ⛔ '$name' is a core session — use --force to remove"
              blocked=$((blocked + 1))
              continue 2
            fi
          done
        fi

        local tmp
        tmp=$(mktemp)
        jq --argjson d "$defaults" --arg key "$key" --arg n "$name" \
          '.[$key] = ((.[$key] // $d) | map(select(. != $n)))' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        echo "  ✓  Removed '$name'"
        removed=$((removed + 1))
      done
      echo ""
      echo "Removed $removed, blocked $blocked, not found $notfound."
      if [[ $removed -gt 0 ]]; then
        echo ""
        echo "Current allowlist:"
        jq -r --argjson d "$defaults" --arg key "$key" '.[$key] // $d | .[]' "$CONFIG_FILE" | sed 's/^/  /'
      fi
      ;;

    *)
      echo "Unknown sessions subcommand: $subcmd" >&2
      echo "Usage: antenna sessions list|add|remove" >&2
      exit 1
      ;;
  esac
}

cmd_config() {
  local subcmd="${1:-show}"
  shift || true

  case "$subcmd" in
    show)
      echo "Antenna Configuration ($CONFIG_FILE):"
      echo ""
      jq '.' "$CONFIG_FILE"
      ;;

    set)
      local key="${1:?Usage: antenna config set <key> <value>}"
      local value="${2:?Usage: antenna config set <key> <value>}"
      local tmp
      tmp=$(mktemp)

      # Try to parse value as JSON (number, bool, array); fall back to string
      if echo "$value" | jq -e '.' &>/dev/null; then
        jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$CONFIG_FILE" > "$tmp" 2>/dev/null \
          || jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$CONFIG_FILE" > "$tmp"
      else
        jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$CONFIG_FILE" > "$tmp"
      fi

      mv "$tmp" "$CONFIG_FILE"
      echo "Set $key = $value"

      # When setting the relay model, also sync to gateway config and restart
      if [[ "$key" == "relay_agent_model" ]]; then
        _sync_relay_model_to_gateway "$value"
      fi
      ;;

    *)
      echo "Unknown config subcommand: $subcmd" >&2
      echo "Usage: antenna config show|set" >&2
      exit 1
      ;;
  esac
}

cmd_model() {
  local subcmd="${1:-show}"
  shift || true

  case "$subcmd" in
    show)
      local model
      model=$(jq -r '.relay_agent_model // "unset"' "$CONFIG_FILE" 2>/dev/null || echo "unset")
      echo "Relay model: $model"
      ;;

    set)
      local model="${1:?Usage: antenna model set <model>}"
      cmd_config set relay_agent_model "$model"
      ;;

    *)
      echo "Unknown model subcommand: $subcmd" >&2
      echo "Usage: antenna model show|set <model>" >&2
      exit 1
      ;;
  esac
}

cmd_log() {
  local tail_n=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tail) tail_n="$2"; shift 2 ;;
      --since)
        # Simple grep for recent entries — works for minutes/hours
        local duration="$2"
        shift 2
        if [[ ! -f "$LOG_FILE" ]]; then
          echo "No log file yet."
          exit 0
        fi
        # Just tail for now; full since-filtering is a v0.2 feature
        echo "(Showing last 50 entries — --since filtering coming in v0.2)"
        tail -50 "$LOG_FILE"
        exit 0
        ;;
      *) echo "Unknown log option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No log file yet."
    exit 0
  fi

  tail -"$tail_n" "$LOG_FILE"
}

cmd_doctor() {
  bash "$SCRIPTS_DIR/antenna-doctor.sh" "$@"
}

cmd_test() {
  bash "$SCRIPTS_DIR/antenna-model-test.sh" "$@"
}

cmd_test_suite() {
  bash "$SCRIPTS_DIR/antenna-test-suite.sh" "$@"
}

cmd_status() {
  echo "=== Antenna Status ==="
  echo ""

  # Self identity
  local self_id self_url
  self_id=$(self_peer_id)
  self_url=$(self_peer_url)
  [[ -n "$self_id" ]] || self_id="unknown"
  [[ -n "$self_url" ]] || self_url="—"
  echo "Local host: $self_id ($self_url)"

  # Peer count
  local peer_count
  peer_count=$(jq '[to_entries[] | select((.value | type) == "object" and (.value.url? | type) == "string" and (.value.self != true))] | length' "$PEERS_FILE" 2>/dev/null || echo "0")
  echo "Remote peers: $peer_count"

  # Config summary
  local model max_len mcs
  model=$(jq -r '.relay_agent_model // "unset"' "$CONFIG_FILE" 2>/dev/null || echo "unset")
  max_len=$(jq -r '.max_message_length // 10000' "$CONFIG_FILE" 2>/dev/null || echo "10000")
  mcs=$(jq -r '.mcs_enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
  echo "Relay model: $model"
  echo "Max message: $max_len chars"
  echo "MCS: $mcs"

  # Rate limit config
  local rl_peer rl_global
  rl_peer=$(jq -r '.rate_limit.per_peer_per_minute // 10' "$CONFIG_FILE" 2>/dev/null || echo "10")
  rl_global=$(jq -r '.rate_limit.global_per_minute // 30' "$CONFIG_FILE" 2>/dev/null || echo "30")
  echo "Rate limit: ${rl_peer}/min per peer, ${rl_global}/min global"

  # Session allowlist
  local sessions local_agent
  local_agent=$(jq -r '.local_agent_id // "agent"' "$CONFIG_FILE" 2>/dev/null || echo "agent")
  sessions=$(jq -r --arg main "agent:'"$local_agent"':main" --arg antenna "agent:'"$local_agent"':antenna" '.allowed_inbound_sessions // [$main,$antenna] | join(", ")' "$CONFIG_FILE" 2>/dev/null || echo "agent:${local_agent}:main, agent:${local_agent}:antenna")
  echo "Session allowlist: $sessions"

  local invalid_keys
  invalid_keys=$(invalid_peer_keys | tr '\n' ',' | sed 's/,$//')
  if [[ -n "$invalid_keys" ]]; then
    echo "Registry hygiene: ignoring malformed entries: $invalid_keys"
  fi

  local exchange_pub_file exchange_key_file exchange_pub_status
  exchange_key_file="$SKILL_DIR/secrets/antenna-exchange.agekey"
  exchange_pub_file="$SKILL_DIR/secrets/antenna-exchange.agepub"
  if [[ -f "$exchange_key_file" && -f "$exchange_pub_file" ]]; then
    exchange_pub_status="configured"
  else
    exchange_pub_status="not configured"
  fi
  echo "Layer A exchange keys: $exchange_pub_status"

  # Log stats
  if [[ -f "$LOG_FILE" ]]; then
    local total_lines last_entry
    total_lines=$(wc -l < "$LOG_FILE")
    last_entry=$(tail -1 "$LOG_FILE" 2>/dev/null || echo "none")
    echo ""
    echo "Log entries: $total_lines"
    echo "Last entry: $last_entry"
  else
    echo ""
    echo "Log: no entries yet"
  fi

  # ── Security: token file permission audit ──
  echo ""
  echo "--- Security Audit ---"
  local warnings=0

  # Check each peer's token file
  while IFS= read -r peer_id; do
    [[ -z "$peer_id" ]] && continue
    local tf
    tf=$(jq -r --arg p "$peer_id" '.[$p].token_file // empty' "$PEERS_FILE" 2>/dev/null)
    [[ -z "$tf" ]] && continue

    # Resolve relative paths against skill dir
    if [[ "$tf" != /* ]]; then
      tf="$SKILL_DIR/$tf"
    fi

    if [[ ! -f "$tf" ]]; then
      echo "  ⚠  $peer_id: token file missing ($tf)"
      warnings=$((warnings + 1))
      continue
    fi

    local perms
    perms=$(stat -c '%a' "$tf" 2>/dev/null || stat -f '%Lp' "$tf" 2>/dev/null || echo "unknown")
    if [[ "$perms" == "600" || "$perms" == "400" ]]; then
      echo "  ✓  $peer_id: token file permissions OK ($perms)"
    else
      echo "  ⚠  $peer_id: token file too permissive ($perms) — should be 600"
      echo "     Fix: chmod 600 $tf"
      warnings=$((warnings + 1))
    fi

    # Check per-peer secret file
    local psf
    psf=$(jq -r --arg p "$peer_id" '.[$p].peer_secret_file // empty' "$PEERS_FILE" 2>/dev/null)
    if [[ -z "$psf" ]]; then
      echo "  ⚠  $peer_id: no per-peer secret configured (sender identity unverified)"
      warnings=$((warnings + 1))
    else
      # Resolve relative paths
      if [[ "$psf" != /* ]]; then
        psf="$SKILL_DIR/$psf"
      fi
      if [[ ! -f "$psf" ]]; then
        echo "  ⚠  $peer_id: peer secret file missing ($psf)"
        warnings=$((warnings + 1))
      else
        local psf_perms
        psf_perms=$(stat -c '%a' "$psf" 2>/dev/null || stat -f '%Lp' "$psf" 2>/dev/null || echo "unknown")
        if [[ "$psf_perms" == "600" || "$psf_perms" == "400" ]]; then
          echo "  ✓  $peer_id: peer secret OK ($psf_perms)"
        else
          echo "  ⚠  $peer_id: peer secret too permissive ($psf_perms) — should be 600"
          echo "     Fix: chmod 600 $psf"
          warnings=$((warnings + 1))
        fi
      fi
    fi

    local xpk
    xpk=$(jq -r --arg p "$peer_id" '.[$p].exchange_public_key // empty' "$PEERS_FILE" 2>/dev/null)
    if [[ -n "$xpk" ]]; then
      echo "  ✓  $peer_id: exchange public key present"
    else
      echo "  ⚠  $peer_id: no exchange public key recorded (encrypted Layer A bootstrap not ready)"
      warnings=$((warnings + 1))
    fi
  done < <(valid_peer_ids)

  if [[ -f "$exchange_key_file" ]]; then
    local ek_perms
    ek_perms=$(stat -c '%a' "$exchange_key_file" 2>/dev/null || stat -f '%Lp' "$exchange_key_file" 2>/dev/null || echo "unknown")
    if [[ "$ek_perms" == "600" || "$ek_perms" == "400" ]]; then
      echo "  ✓  local exchange private key permissions OK ($ek_perms)"
    else
      echo "  ⚠  local exchange private key too permissive ($ek_perms) — should be 600"
      warnings=$((warnings + 1))
    fi
  else
    echo "  ⚠  local exchange private key missing ($exchange_key_file)"
    warnings=$((warnings + 1))
  fi

  # Check config file itself
  if [[ -f "$CONFIG_FILE" ]]; then
    local cfg_perms
    cfg_perms=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || stat -f '%Lp' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
    if [[ "$cfg_perms" != "600" && "$cfg_perms" != "644" && "$cfg_perms" != "640" && "$cfg_perms" != "400" ]]; then
      echo "  ⚠  config file too permissive ($cfg_perms) — recommend 644 or 600"
      warnings=$((warnings + 1))
    fi
  fi

  # Check peers file
  if [[ -f "$PEERS_FILE" ]]; then
    local peers_perms
    peers_perms=$(stat -c '%a' "$PEERS_FILE" 2>/dev/null || stat -f '%Lp' "$PEERS_FILE" 2>/dev/null || echo "unknown")
    if [[ "$peers_perms" != "600" && "$peers_perms" != "644" && "$peers_perms" != "640" && "$peers_perms" != "400" ]]; then
      echo "  ⚠  peers file too permissive ($peers_perms) — recommend 644 or 600"
      warnings=$((warnings + 1))
    fi
  fi

  if [[ "$warnings" -eq 0 ]]; then
    echo "  ✓  All file permissions OK"
  else
    echo ""
    echo "  $warnings warning(s) — review above"
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  setup)    cmd_setup "$@" ;;
  pair)     cmd_pair "$@" ;;
  uninstall) cmd_uninstall "$@" ;;
  doctor)   cmd_doctor "$@" ;;
  send)     cmd_send "$@" ;;
  msg)      cmd_msg "$@" ;;
  peers)    cmd_peers "$@" ;;
  inbox)    cmd_inbox "$@" ;;
  sessions) cmd_sessions "$@" ;;
  config)   cmd_config "$@" ;;
  model)    cmd_model "$@" ;;
  log)      cmd_log "$@" ;;
  status)   cmd_status ;;
  test)        cmd_test "$@" ;;
  test-suite)  cmd_test_suite "$@" ;;
  help|-h|--help) usage ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Run 'antenna help' for usage." >&2
    exit 1
    ;;
esac
