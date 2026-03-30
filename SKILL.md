---
name: antenna
version: 1.0.2
description: >
  Inter-host OpenClaw session messaging over Tailscale using built-in gateway webhook hooks.
  Use when: (1) sending a message from this OpenClaw instance to another host's OpenClaw session,
  (2) checking status/health of a remote OpenClaw peer, (3) managing the peer registry
  (adding/removing/listing known peers), (4) any cross-host agent communication that should
  NOT go through visible chat channels like Telegram/WhatsApp/Discord.
  Triggers: "send to <peer>", "message the other host", "antenna send", "antenna status",
  "cross-host message", "inter-host relay", "ping <peer>", "peer list".
---

# Antenna — Inter-Host OpenClaw Messaging (v1.0)

Send messages between OpenClaw instances over Tailscale via the built-in `/hooks/agent` webhook.

## Prerequisites

Each participating host needs:
1. OpenClaw gateway running with hooks enabled (`hooks.enabled: true`)
2. A shared hooks token (same on all peers)
3. Reachability over Tailscale (via `tailscale serve` HTTPS or direct tailnet IP)
4. `hooks.allowRequestSessionKey: true` with appropriate prefix restrictions
5. Antenna agent registered in gateway config (`agents` section)
6. `hooks.allowedAgentIds` includes `"antenna"`
7. `hooks.allowedSessionKeyPrefixes` includes `"hook:antenna"`

## Architecture

Messages flow through a script-first relay pipeline:

1. **Sender** runs `antenna-send.sh` which builds an `[ANTENNA_RELAY]` envelope and POSTs it to the recipient's `/hooks/agent` endpoint.
2. **Recipient gateway** dispatches to the dedicated **Antenna agent** (lightweight, minimal context).
3. **Antenna agent** runs `antenna-relay.sh` which deterministically parses, validates, and formats the message.
4. **Antenna agent** calls `sessions_send` to inject the formatted message into the target session.
5. **Message appears** persistently in the target conversation thread.

The LLM never touches raw envelope parsing — all logic is in the scripts.

## Configuration

All host-specific and user-specific settings live in two config files. **New installations must edit these before first use.** No hardcoded defaults assume a particular host, user, or model.

### `antenna-config.json` — System settings

```json
{
  "max_message_length": 10000,
  "default_target_session": "main",
  "relay_agent_id": "antenna",
  "relay_agent_model": "openai/gpt-5.4",
  "local_agent_id": "<your-agent-id>",
  "install_path": "<absolute-path-to-this-skill-directory>",
  "log_enabled": true,
  "log_path": "antenna.log",
  "log_max_size_bytes": 10485760,
  "log_verbose": false,
  "mcs_enabled": false,
  "mcs_model": "sonnet",
  "allowed_inbound_peers": ["<peer-a>", "<peer-b>"],
  "allowed_outbound_peers": ["<peer-a>", "<peer-b>"]
}
```

| Field | Description |
|---|---|
| `relay_agent_model` | Full provider/model ID for the relay agent. Use a specific model, not a local alias. |
| `local_agent_id` | Your primary assistant agent ID (used to resolve `main` → `agent:<id>:main`). |
| `install_path` | Absolute path to this skill directory on your host. Used by the agent to resolve script paths. |
| `allowed_inbound_peers` | Peer IDs allowed to send messages to this host. |
| `allowed_outbound_peers` | Peer IDs this host is allowed to send to. |

### `antenna-peers.json` — Peer registry

```json
{
  "<your-host-id>": {
    "url": "https://<your-tailscale-hostname>",
    "token_file": "/path/to/secrets/hooks_token",
    "agentId": "antenna",
    "display_name": "My Host (Server)",
    "self": true
  },
  "<remote-peer-id>": {
    "url": "https://<remote-tailscale-hostname>",
    "token_file": "/path/to/secrets/hooks_token",
    "agentId": "antenna",
    "display_name": "Remote Host (Laptop)"
  }
}
```

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Peer's hook base URL (Tailscale Serve HTTPS or direct tailnet IP) |
| `token_file` | Yes | Path to file containing the shared hooks token (`chmod 600`) |
| `agentId` | No | Agent ID to target on this peer (default: `"antenna"`) |
| `display_name` | No | Human-readable name for log entries and delivery headers |
| `self` | No | `true` for the local host entry (used to auto-populate `reply_to`) |

## Usage

### Send a message to a peer

```bash
# Default plain relay mode
scripts/antenna-send.sh <peer> "Your message here"

# Via the CLI wrapper
antenna msg <peer> "Your message here"

# Target a specific session on the recipient
scripts/antenna-send.sh <peer> --session "agent:<agent-id>:mychannel" "Your message"

# With a subject line
antenna msg <peer> --subject "Config sync" "Here's the block you need..."

# Optional humanized sender mode (experimental)
antenna msg <peer> --user "Your Name" "Your message"

# Read message from stdin
echo "Long message body..." | antenna send <peer> --stdin

# Dry run (print envelope without sending)
antenna send <peer> --dry-run "Test message"
```

### Check peer health

```bash
scripts/antenna-health.sh <peer>
# Returns: {"ok":true,"status":"live","peer":"<peer>"} or error
```

### List known peers

```bash
scripts/antenna-peers.sh list
scripts/antenna-peers.sh json
```

### Full CLI

```bash
antenna send <peer> [options] <message>    # Send a message
antenna msg <peer> [message]               # Quick send (plain mode)
antenna peers list                         # List known peers
antenna peers add <id> --url <url> --token-file <path> [--display-name <name>]
antenna peers remove <id>
antenna peers test <id>                    # Connectivity test
antenna config show                        # Show current config
antenna config set <key> <value>           # Update a config value
antenna log [--tail <n>]                   # View transaction log
antenna status                             # Overall status summary

# Testing
antenna test <model>                       # Self-loop integration test (end-to-end smoke)
antenna test-suite --tier A                # Script validation only (no model, no network)
antenna test-suite --model <m>             # Full three-tier suite against a single model
antenna test-suite --models "<m1>,<m2>"    # Compare models side-by-side (max 6)
antenna test-suite --report                # Save structured report to test-results/
antenna test-suite --format markdown       # Pasteable markdown output
antenna test-suite --verbose               # Inline request/response payloads
```

### Test Suite

The test suite evaluates relay agent model compatibility in three tiers:

| Tier | What | How | Network? |
|------|------|-----|----------|
| **A** | Relay script parsing & validation (8 tests) | Feeds envelopes directly into `antenna-relay.sh` | No |
| **B** | Model → exec tool call (4 tests) | Direct API call, checks model emits correct `exec` invocation | Yes (provider API) |
| **C** | Model → sessions_send (4 tests) | Simulated relay response, checks model emits correct `sessions_send` | Yes (provider API) |

**Multi-model comparison:** Pass `--models "a,b,c"` to run B+C against each model and produce a side-by-side comparison table with scores and timing.

**Report output:** `--report [dir]` writes per-model request/response dumps, `summary.md`, and `summary.json` for forensic review.

**Supported providers:** OpenAI, OpenAI Codex, OpenRouter, Nvidia, Ollama (local). Anthropic and Google adapters planned.

## Message Format

Messages are async fire-and-forget. Every message includes a return-address header so the receiving agent can reply via the same mechanism.

### Envelope

```
[ANTENNA_RELAY]
from: <sender-peer-id>
target_session: main
timestamp: 2026-03-28T22:20:00Z
reply_to: https://<sender-tailscale-hostname>/hooks/agent
subject: Config sync

Hey, here's the config block you need...
[/ANTENNA_RELAY]
```

### Envelope Fields

| Field | Required | Description |
|---|---|---|
| `from` | Yes | Sender peer ID (must match key in recipient's `antenna-peers.json`) |
| `target_session` | Yes | Session key to deliver into. `main` = recipient's primary agent session. |
| `timestamp` | Yes | ISO-8601 send time |
| `reply_to` | No | Sender's hook URL for replies (enables two-way) |
| `subject` | No | Optional subject/thread label |
| `user` | No | Optional human sender name (experimental) |

## Security Notes

- All traffic stays on Tailscale (WireGuard encrypted)
- Hooks token required (Bearer auth)
- `allowedSessionKeyPrefixes` restricts injectable sessions
- `allowedAgentIds` restricts which agents can be targeted
- Sender validated against `allowed_inbound_peers` on receipt
- Token is read from file at send time, never embedded in scripts
- Script-first design: relay agent never interprets message body content

## Troubleshooting

- **Connection timeout**: Check `tailscale ping <peer>` and verify gateway is running on target
- **401 Unauthorized**: Token mismatch — verify same token on both hosts
- **403 Forbidden**: Session key prefix or agent ID not in allowlist
- **Connection refused**: Gateway not listening — check `openclaw gateway status` on target
- **Message sent but not visible**: May be a Control UI refresh delay; recipient agent receives and processes promptly

## File Inventory

```
skills/antenna/
├── SKILL.md                    # This file
├── README.md                   # Public-facing overview (for ClawHub)
├── CHANGELOG.md                # Version history
├── antenna-peers.json          # Peer registry (EDIT FOR YOUR HOSTS)
├── antenna-config.json         # System configuration (EDIT FOR YOUR SETUP)
├── antenna.log                 # Transaction log (created at runtime)
├── bin/
│   └── antenna                 # CLI dispatcher
├── scripts/
│   ├── antenna-send.sh         # Sender: builds envelope, POSTs to peer
│   ├── antenna-relay.sh        # Receiver: parses, validates, formats, logs
│   ├── antenna-health.sh       # Peer health check
│   ├── antenna-peers.sh        # Peer listing utility
│   ├── antenna-model-test.sh   # Self-loop integration tester (smoke)
│   └── antenna-test-suite.sh   # Three-tier model/script test suite
├── docs/
│   └── ANTENNA-RELAY-FSD.md    # Full functional specification
└── agent/
    ├── AGENTS.md               # Antenna agent instructions
    └── TOOLS.md                # Antenna agent tool references
```

### Gateway/Agent Registration (both hosts)

- Agent `antenna` registered in `~/.openclaw/openclaw.json` under `agents`
- `hooks.allowedAgentIds` includes `"antenna"`
- `hooks.allowedSessionKeyPrefixes` includes `"hook:antenna"`
