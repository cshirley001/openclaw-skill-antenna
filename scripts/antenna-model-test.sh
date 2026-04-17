#!/usr/bin/env bash
# antenna-model-test.sh — End-to-end self-loop model tester for the Antenna relay agent.
#
# Temporarily swaps relay_agent_model in config, sends a test message to self,
# and confirms relay completion via transaction log polling.
#
# Usage:
#   antenna-model-test.sh <model> [--runs <n>] [--timeout <sec>] [--keep-model]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SKILL_DIR/antenna-config.json"
PEERS_FILE="$SKILL_DIR/antenna-peers.json"
LOG_PATH=$(jq -r '.log_path // "antenna.log"' "$CONFIG_FILE" 2>/dev/null || echo "antenna.log")
SEND_SCRIPT="$SCRIPT_DIR/antenna-send.sh"

# Resolve relative log path
if [[ "$LOG_PATH" != /* ]]; then
  LOG_PATH="$SKILL_DIR/$LOG_PATH"
fi

TEST_SESSION="agent:antenna:modeltest"

# ── Defaults ─────────────────────────────────────────────────────────────────

MODEL=""
RUNS=1
TIMEOUT=15
KEEP_MODEL=false

# ── Parse args ───────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  cat >&2 <<'EOF'
Usage: antenna-model-test.sh <model> [--runs <n>] [--timeout <sec>] [--keep-model]

  <model>         Full provider/model ID to test (e.g. openai/gpt-5.4)
  --runs <n>      Number of test iterations (default: 1)
  --timeout <sec> Per-run relay timeout in seconds (default: 15)
  --keep-model    Leave candidate model active after testing
EOF
  exit 1
fi

MODEL="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)       RUNS="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    --keep-model) KEEP_MODEL=true; shift ;;
    -h|--help)
      echo "Usage: antenna-model-test.sh <model> [--runs <n>] [--timeout <sec>] [--keep-model]"
      exit 0
      ;;
    *)            echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Validate prerequisites ───────────────────────────────────────────────────

for cmd in jq curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required" >&2; exit 1
  fi
done

SELF_PEER=$(jq -r 'to_entries[] | select((.value | type) == "object" and (.value.url? | type) == "string" and .value.self == true) | .key' "$PEERS_FILE" 2>/dev/null || echo "")
if [[ -z "$SELF_PEER" ]]; then
  echo "ERROR: No self-peer found in $PEERS_FILE (need an entry with \"self\": true)" >&2
  exit 1
fi

ORIGINAL_MODEL=$(jq -r '.relay_agent_model // "unset"' "$CONFIG_FILE")

# ── Restore handler ──────────────────────────────────────────────────────────

restore_model() {
  if [[ "$KEEP_MODEL" == "false" && "$MODEL" != "$ORIGINAL_MODEL" ]]; then
    local tmp
    tmp=$(mktemp)
    if jq --arg m "$ORIGINAL_MODEL" '.relay_agent_model = $m' "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$CONFIG_FILE"
      echo ""
      echo "Restored relay_agent_model → $ORIGINAL_MODEL"
    else
      rm -f "$tmp"
      echo ""
      echo "WARNING: Failed to restore relay_agent_model. Manually set to: $ORIGINAL_MODEL" >&2
    fi
  fi
}

trap restore_model EXIT

# ── Swap model ───────────────────────────────────────────────────────────────

echo "=== Antenna Model Tester ==="
echo ""
echo "Model:     $MODEL"
echo "Self-peer: $SELF_PEER"
echo "Session:   $TEST_SESSION"
echo "Runs:      $RUNS"
echo "Timeout:   ${TIMEOUT}s per run"
echo "Original:  $ORIGINAL_MODEL"
echo ""

if [[ "$MODEL" != "$ORIGINAL_MODEL" ]]; then
  tmp=$(mktemp)
  jq --arg m "$MODEL" '.relay_agent_model = $m' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  echo "Swapped relay_agent_model → $MODEL"
  echo ""
fi

# ── Run tests ────────────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
TIMES=()

for (( i=1; i<=RUNS; i++ )); do
  # Snapshot log position BEFORE sending — anything before this line is history
  LOG_LINES_BEFORE=0
  if [[ -f "$LOG_PATH" ]]; then
    LOG_LINES_BEFORE=$(wc -l < "$LOG_PATH")
  fi

  # Send test message
  START_TS=$(date +%s%N)
  SEND_OUTPUT=""
  SEND_RC=0

  TEST_NONCE="MODELTEST_$(head -c 6 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 8)"
  TEST_BODY="[Antenna Model Test]
model: ${MODEL}
run: ${i}/${RUNS}
nonce: ${TEST_NONCE}
host: $(hostname)
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
timeout: ${TIMEOUT}s

This is an automated relay test verifying that ${MODEL} can serve as the Antenna relay agent."

  SEND_OUTPUT=$(bash "$SEND_SCRIPT" "$SELF_PEER" --session "$TEST_SESSION" "$TEST_BODY" 2>&1) || SEND_RC=$?

  if [[ $SEND_RC -ne 0 ]]; then
    END_TS=$(date +%s%N)
    ELAPSED=$(( (END_TS - START_TS) / 1000000 ))
    ELAPSED_SEC=$(awk "BEGIN {printf \"%.1f\", $ELAPSED/1000}")
    SEND_ERROR=$(echo "$SEND_OUTPUT" | jq -r '.error // empty' 2>/dev/null || echo "$SEND_OUTPUT")
    echo "RUN $i/$RUNS | model: $MODEL | status: FAIL | time: ${ELAPSED_SEC}s | error: send failed — $SEND_ERROR"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TIMES+=("$ELAPSED")
    # Cooldown even on failure — give the gateway a beat
    [[ $i -lt $RUNS ]] && sleep 5
    continue
  fi

  SEND_STATUS=$(echo "$SEND_OUTPUT" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
  if [[ "$SEND_STATUS" != "delivered" ]]; then
    END_TS=$(date +%s%N)
    ELAPSED=$(( (END_TS - START_TS) / 1000000 ))
    ELAPSED_SEC=$(awk "BEGIN {printf \"%.1f\", $ELAPSED/1000}")
    echo "RUN $i/$RUNS | model: $MODEL | status: FAIL | time: ${ELAPSED_SEC}s | error: send status=$SEND_STATUS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TIMES+=("$ELAPSED")
    [[ $i -lt $RUNS ]] && sleep 5
    continue
  fi

  # ── Poll log for THIS run's relay confirmation ─────────────────────────
  # Strategy:
  #   - Look for OUTBOUND (our send) followed by a matching INBOUND in new lines only
  #   - PASS = INBOUND with session:$TEST_SESSION and status:relayed
  #   - MALFORMED/REJECTED are only counted if no PASS appears by timeout
  #     (a stale MALFORMED from a prior run's delayed processing shouldn't poison us)
  #   - We check every second until timeout

  RESULT="timeout"
  DEADLINE=$(( $(date +%s) + TIMEOUT ))

  while [[ $(date +%s) -lt $DEADLINE ]]; do
    sleep 1
    [[ -f "$LOG_PATH" ]] || continue

    # Only look at lines added since our send
    NEW_LINES=$(tail -n +"$((LOG_LINES_BEFORE + 1))" "$LOG_PATH" 2>/dev/null || true)
    [[ -z "$NEW_LINES" ]] && continue

    # Check for success first — this is the definitive signal
    if echo "$NEW_LINES" | grep -q "INBOUND.*session:${TEST_SESSION}.*status:relayed"; then
      RESULT="pass"
      break
    fi
  done

  # If we timed out, check what DID appear for a better error message
  if [[ "$RESULT" == "timeout" && -f "$LOG_PATH" ]]; then
    NEW_LINES=$(tail -n +"$((LOG_LINES_BEFORE + 1))" "$LOG_PATH" 2>/dev/null || true)
    if echo "$NEW_LINES" | grep -q "INBOUND.*status:MALFORMED"; then
      RESULT="malformed"
    elif echo "$NEW_LINES" | grep -q "INBOUND.*status:REJECTED"; then
      RESULT="rejected"
    fi
  fi

  END_TS=$(date +%s%N)
  ELAPSED=$(( (END_TS - START_TS) / 1000000 ))
  ELAPSED_SEC=$(awk "BEGIN {printf \"%.1f\", $ELAPSED/1000}")
  TIMES+=("$ELAPSED")

  case "$RESULT" in
    pass)
      echo "RUN $i/$RUNS | model: $MODEL | status: PASS | time: ${ELAPSED_SEC}s"
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;
    malformed)
      echo "RUN $i/$RUNS | model: $MODEL | status: FAIL | time: ${ELAPSED_SEC}s | error: relay malformed (agent mangled envelope)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
    rejected)
      echo "RUN $i/$RUNS | model: $MODEL | status: FAIL | time: ${ELAPSED_SEC}s | error: relay rejected"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
    timeout)
      echo "RUN $i/$RUNS | model: $MODEL | status: FAIL | time: ${ELAPSED_SEC}s | error: relay timeout (${TIMEOUT}s)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
  esac

  # Cooldown between runs — let the hook agent session fully settle
  if [[ $i -lt $RUNS ]]; then
    sleep 5
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

if [[ $RUNS -gt 1 ]]; then
  MIN=${TIMES[0]}
  MAX=${TIMES[0]}
  SUM=0
  for t in "${TIMES[@]}"; do
    SUM=$((SUM + t))
    (( t < MIN )) && MIN=$t
    (( t > MAX )) && MAX=$t
  done
  AVG=$((SUM / RUNS))

  AVG_SEC=$(awk "BEGIN {printf \"%.1f\", $AVG/1000}")
  MIN_SEC=$(awk "BEGIN {printf \"%.1f\", $MIN/1000}")
  MAX_SEC=$(awk "BEGIN {printf \"%.1f\", $MAX/1000}")

  echo ""
  echo "=== Summary ==="
  echo "Model:   $MODEL"
  echo "Runs:    $RUNS"
  echo "Passed:  $PASS_COUNT  Failed: $FAIL_COUNT"
  echo "Avg time: ${AVG_SEC}s  Min: ${MIN_SEC}s  Max: ${MAX_SEC}s"
fi

# Exit with failure code if any run failed
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
