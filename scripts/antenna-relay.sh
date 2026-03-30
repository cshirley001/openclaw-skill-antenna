#!/usr/bin/env bash
# antenna-relay.sh — Deterministic relay processor for inbound Antenna messages.
# Parses [ANTENNA_RELAY] envelope, validates, formats delivery message, logs.
# Called by the Antenna agent via exec. Outputs JSON to stdout.
#
# Usage:
#   antenna-relay.sh <raw_message>
#   echo "<raw_message>" | antenna-relay.sh --stdin
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PEERS_FILE="$SKILL_DIR/antenna-peers.json"
CONFIG_FILE="$SKILL_DIR/antenna-config.json"

# ── Helpers ──────────────────────────────────────────────────────────────────

json_ok() {
  jq -n \
    --arg sessionKey "$1" \
    --arg message "$2" \
    --arg from "$3" \
    --arg timestamp "$4" \
    --argjson chars "$5" \
    '{action:"relay", status:"ok", sessionKey:$sessionKey, message:$message, from:$from, timestamp:$timestamp, chars:$chars}'
}

json_reject() {
  local reason="$1"
  local from="${2:-unknown}"
  jq -n \
    --arg reason "$reason" \
    --arg from "$from" \
    '{action:"reject", status:"rejected", reason:$reason, from:$from}'
}

json_malformed() {
  local reason="$1"
  jq -n \
    --arg reason "$reason" \
    '{action:"reject", status:"malformed", reason:$reason}'
}

log_entry() {
  local log_enabled log_path
  log_enabled=$(jq -r '.log_enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  log_path=$(jq -r '.log_path // "antenna.log"' "$CONFIG_FILE" 2>/dev/null || echo "antenna.log")

  if [[ "$log_enabled" != "true" ]]; then
    return 0
  fi

  # Resolve relative log path against skill dir
  if [[ "$log_path" != /* ]]; then
    log_path="$SKILL_DIR/$log_path"
  fi

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$ts] $*" >> "$log_path"
}

# ── Read input ───────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--stdin" ]]; then
  RAW_MESSAGE=$(cat)
elif [[ $# -ge 1 ]]; then
  RAW_MESSAGE="$1"
else
  json_malformed "No input provided"
  exit 0
fi

# ── Detect envelope markers ─────────────────────────────────────────────────

if ! echo "$RAW_MESSAGE" | grep -q '\[ANTENNA_RELAY\]'; then
  json_malformed "No [ANTENNA_RELAY] envelope detected"
  log_entry "INBOUND  | status:MALFORMED (no envelope markers)"
  exit 0
fi

if ! echo "$RAW_MESSAGE" | grep -q '\[/ANTENNA_RELAY\]'; then
  json_malformed "No closing [/ANTENNA_RELAY] marker"
  log_entry "INBOUND  | status:MALFORMED (no closing marker)"
  exit 0
fi

# ── Extract envelope content ────────────────────────────────────────────────

# Get everything between [ANTENNA_RELAY] and [/ANTENNA_RELAY]
ENVELOPE=$(echo "$RAW_MESSAGE" | sed -n '/\[ANTENNA_RELAY\]/,/\[\/ANTENNA_RELAY\]/p' | sed '1d;$d')

# ── Parse headers ────────────────────────────────────────────────────────────
# Headers are key: value lines before the first blank line.
# Body is everything after the first blank line.

HEADERS=""
BODY=""
IN_BODY=false

while IFS= read -r line; do
  if [[ "$IN_BODY" == "true" ]]; then
    if [[ -n "$BODY" ]]; then
      BODY="${BODY}
${line}"
    else
      BODY="$line"
    fi
  elif [[ -z "$line" ]]; then
    IN_BODY=true
  else
    if [[ -n "$HEADERS" ]]; then
      HEADERS="${HEADERS}
${line}"
    else
      HEADERS="$line"
    fi
  fi
done <<< "$ENVELOPE"

# Extract individual header values
get_header() {
  echo "$HEADERS" | grep -i "^${1}:" | head -1 | sed "s/^${1}:[[:space:]]*//" || true
}

FROM=$(get_header "from")
REPLY_TO=$(get_header "reply_to")
TARGET_SESSION=$(get_header "target_session")
TIMESTAMP=$(get_header "timestamp")
SUBJECT=$(get_header "subject")
USER_NAME=$(get_header "user")

# ── Validate required fields ────────────────────────────────────────────────

if [[ -z "$FROM" ]]; then
  json_reject "Missing required field: from"
  log_entry "INBOUND  | status:REJECTED (missing from)"
  exit 0
fi

if [[ -z "$TARGET_SESSION" ]]; then
  # Use default from config
  TARGET_SESSION=$(jq -r '.default_target_session // "main"' "$CONFIG_FILE" 2>/dev/null || echo "main")
fi

if [[ -z "$TIMESTAMP" ]]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

# ── Validate sender against allowed inbound peers ───────────────────────────

ALLOWED=$(jq -r --arg from "$FROM" '
  .allowed_inbound_peers // [] | if (. | length) == 0 then "allowed"
  elif (. | index($from)) then "allowed"
  else "denied" end
' "$CONFIG_FILE" 2>/dev/null || echo "allowed")

if [[ "$ALLOWED" == "denied" ]]; then
  json_reject "Unknown or disallowed sender: $FROM" "$FROM"
  log_entry "INBOUND  | from:$FROM | status:REJECTED (not in allowed_inbound_peers)"
  exit 0
fi

# Also check peers file for existence
PEER_EXISTS=$(jq -r --arg from "$FROM" 'has($from) | tostring' "$PEERS_FILE" 2>/dev/null || echo "false")
if [[ "$PEER_EXISTS" != "true" ]]; then
  json_reject "Unknown peer: $FROM (not in peers registry)" "$FROM"
  log_entry "INBOUND  | from:$FROM | status:REJECTED (unknown peer)"
  exit 0
fi

# ── Validate message length ─────────────────────────────────────────────────

MAX_LEN=$(jq -r '.max_message_length // 10000' "$CONFIG_FILE" 2>/dev/null || echo "10000")
BODY_LEN=${#BODY}

if [[ "$BODY_LEN" -gt "$MAX_LEN" ]]; then
  json_reject "Message body exceeds max length ($BODY_LEN > $MAX_LEN chars)" "$FROM"
  log_entry "INBOUND  | from:$FROM | status:REJECTED (over max length: $BODY_LEN > $MAX_LEN)"
  exit 0
fi

# ── Resolve target session ──────────────────────────────────────────────────

if [[ "$TARGET_SESSION" == "main" ]]; then
  LOCAL_AGENT=$(jq -r '.local_agent_id // "betty"' "$CONFIG_FILE" 2>/dev/null || echo "betty")
  TARGET_SESSION="agent:${LOCAL_AGENT}:main"
fi

# ── Format delivery message ─────────────────────────────────────────────────

DISPLAY_NAME=$(jq -r --arg from "$FROM" '.[$from].display_name // $from' "$PEERS_FILE" 2>/dev/null || echo "$FROM")

# Convert UTC timestamp to a friendlier format if possible
FRIENDLY_TS="$TIMESTAMP"
if command -v date &>/dev/null; then
  FRIENDLY_TS=$(TZ="America/Toronto" date -d "$TIMESTAMP" +"%Y-%m-%d %H:%M %Z" 2>/dev/null || echo "$TIMESTAMP")
fi

# If a human user sent this, show their name prominently
if [[ -n "$USER_NAME" ]]; then
  DELIVERY_MSG="📡 Antenna from ${USER_NAME} via ${DISPLAY_NAME} (${FROM}) — ${FRIENDLY_TS}"
else
  DELIVERY_MSG="📡 Antenna from ${DISPLAY_NAME} (${FROM}) — ${FRIENDLY_TS}"
fi

if [[ -n "$SUBJECT" ]]; then
  DELIVERY_MSG="${DELIVERY_MSG}
Subject: ${SUBJECT}"
fi

DELIVERY_MSG="${DELIVERY_MSG}

${BODY}"

# ── Log ──────────────────────────────────────────────────────────────────────

log_entry "INBOUND  | from:$FROM | session:$TARGET_SESSION | status:relayed | chars:$BODY_LEN"

# Check if verbose logging is enabled
LOG_VERBOSE=$(jq -r '.log_verbose // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
if [[ "$LOG_VERBOSE" == "true" ]]; then
  PREVIEW="${BODY:0:100}"
  log_entry "INBOUND  | from:$FROM | preview:${PREVIEW}..."
fi

# ── Output result ────────────────────────────────────────────────────────────

json_ok "$TARGET_SESSION" "$DELIVERY_MSG" "$FROM" "$TIMESTAMP" "$BODY_LEN"
