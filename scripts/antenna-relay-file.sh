#!/usr/bin/env bash
# antenna-relay-file.sh — Read raw message from a file and pass it to
# antenna-relay.sh via stdin.
#
# Usage: bash antenna-relay-file.sh /path/to/message-file
#
# Designed so the calling agent never needs to base64-encode or use
# shell metacharacters. The agent writes raw message text to a temp file
# (via the write tool), then execs this script with the file path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-}"

if [[ -z "$INPUT_FILE" ]]; then
    echo '{"action":"reject","status":"error","reason":"No input file path provided"}'
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "{\"action\":\"reject\",\"status\":\"error\",\"reason\":\"Input file not found: $INPUT_FILE\"}"
    exit 1
fi

cleanup_input_file() {
    case "$INPUT_FILE" in
        /tmp/antenna-relay/*|/tmp/antenna-relay-msg.*)
            rm -f "$INPUT_FILE" 2>/dev/null || true
            ;;
    esac
}

trap cleanup_input_file EXIT

# Feed the raw message to the relay script via stdin
bash "$SCRIPT_DIR/antenna-relay.sh" --stdin < "$INPUT_FILE"
