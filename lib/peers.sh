# lib/peers.sh — Shared helpers for reading antenna-peers.json
#
# SOURCE, don't execute. Callers must set PEERS_FILE before sourcing or before
# calling any helper. All helpers are read-only; mutations stay with their
# owning scripts (antenna-exchange.sh, antenna-peers.sh).
#
# Conventions:
#   - Helpers emit their result to stdout; empty string means "not found".
#   - `peers_exists` returns 0/1 via exit code.
#   - `peers_require` emits on stdout OR dies with a helpful message.
#   - Missing/invalid peers file is tolerated silently (stdout empty),
#     matching the legacy inline behavior. Callers that need strictness
#     should use `peers_require` or check `peers_exists` first.
#
# Addresses: REF-1303, REF-1405, REF-1513 (duplicated jq patterns).

# Guard against double-source.
if [[ -n "${_ANTENNA_LIB_PEERS_LOADED:-}" ]]; then
  return 0
fi
_ANTENNA_LIB_PEERS_LOADED=1

# Canonical jq predicate: "object with a url string field".
# Keeps the shape in ONE place; everything else composes on it.
_ANTENNA_PEER_OBJ_PRED='(.value | type) == "object" and (.value.url? | type) == "string"'

# peers_list_ids
#   Emits every peer ID that has a url field, one per line.
peers_list_ids() {
  [[ -f "${PEERS_FILE:-}" ]] || return 0
  jq -r "to_entries[] | select($_ANTENNA_PEER_OBJ_PRED) | .key" \
    "$PEERS_FILE" 2>/dev/null || true
}

# peers_list_self_ids
#   Emits every peer ID marked self==true (should be 0 or 1).
peers_list_self_ids() {
  [[ -f "${PEERS_FILE:-}" ]] || return 0
  jq -r "to_entries[] | select($_ANTENNA_PEER_OBJ_PRED and .value.self == true) | .key" \
    "$PEERS_FILE" 2>/dev/null || true
}

# peers_self_id
#   First self peer's ID, or empty.
peers_self_id() {
  peers_list_self_ids | head -n 1
}

# peers_self_url
#   First self peer's url, or empty.
peers_self_url() {
  [[ -f "${PEERS_FILE:-}" ]] || return 0
  jq -r "to_entries[] | select($_ANTENNA_PEER_OBJ_PRED and .value.self == true) | .value.url" \
    "$PEERS_FILE" 2>/dev/null | head -n 1
}

# peers_exists <peer_id>
#   Exit 0 if peer key exists in the file, 1 otherwise.
peers_exists() {
  local peer="${1:-}"
  [[ -n "$peer" ]] || return 1
  [[ -f "${PEERS_FILE:-}" ]] || return 1
  jq -e --arg p "$peer" 'has($p)' "$PEERS_FILE" >/dev/null 2>&1
}

# peers_get <peer_id> <field>
#   Emits .[peer][field] or empty if missing.
peers_get() {
  local peer="${1:-}" field="${2:-}"
  [[ -n "$peer" && -n "$field" ]] || return 0
  [[ -f "${PEERS_FILE:-}" ]] || return 0
  jq -r --arg p "$peer" --arg f "$field" '.[$p][$f] // empty' \
    "$PEERS_FILE" 2>/dev/null || true
}

# peers_require <peer_id> <field> <context>
#   Emits .[peer][field] or writes an error to stderr and exits 1.
#   <context> is a short phrase used in the error (e.g. "antenna send").
peers_require() {
  local peer="${1:-}" field="${2:-}" ctx="${3:-antenna}"
  local val
  val="$(peers_get "$peer" "$field")"
  if [[ -z "$val" ]]; then
    echo "$ctx: peer '$peer' is missing required field '$field' in ${PEERS_FILE:-antenna-peers.json}" >&2
    exit 1
  fi
  printf '%s\n' "$val"
}
