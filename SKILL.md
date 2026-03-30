---
name: antenna
version: 1.0.0
description: >
  Inter-host OpenClaw session messaging over Tailscale using built-in gateway webhook hooks.
  Use when: (1) sending a message from this OpenClaw instance to another host's OpenClaw session,
  (2) checking status/health of a remote OpenClaw peer, (3) managing the peer registry
  (adding/removing/listing known peers), (4) any cross-host agent communication that should
  NOT go through visible chat channels like Telegram/WhatsApp/Discord.
  Triggers: "send to bettyxx", "message the other host", "antenna send", "antenna status",
  "cross-host message", "inter-host relay", "ping bettyxx", "peer list".
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

## Peer Registry

Peers are defined in `antenna-peers.json` (same directory as this SKILL.md).

```json
{
  "bettyxix": {
    "url": "https://bettyxix.tailde275c.ts.net",
    "token_file": "/path/to/secrets/hooks_token",
    "agentId": "antenna",
    "display_name": "Betty XIX (Server)",
    "self": true
  },
  "bettyxx": {
    "url": "https://bettyxx-1.tailde275c.ts.net",
    "token_file": "/path/to/secrets/hooks_token",
    "agentId": "antenna",
    "display_name": "Betty XX (Laptop)"
  }
}
```

### Fields

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
scripts/antenna-send.sh <peer> --session "agent:betty:antennatest1" "Your message"

# With a subject line
antenna msg <peer> --subject "Config sync" "Here's the block you need..."

# Optional humanized sender mode (experimental)
antenna msg <peer> --user Corey "Your message"

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
```

## Message Format

Messages are async fire-and-forget. Every message includes a return-address header so the receiving agent can reply via the same mechanism.

### Envelope

```
[ANTENNA_RELAY]
from: bettyxix
target_session: main
timestamp: 2026-03-28T22:20:00Z
reply_to: https://bettyxix.tailde275c.ts.net/hooks/agent
subject: NVIDIA config sync

Hey Sis, here's the config block you need...
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

## Configuration (`antenna-config.json`)

```json
{
  "max_message_length": 10000,
  "default_target_session": "main",
  "relay_agent_id": "antenna",
  "relay_agent_model": "mini",
  "local_agent_id": "betty",
  "log_enabled": true,
  "log_path": "antenna.log",
  "log_max_size_bytes": 10485760,
  "log_verbose": false,
  "mcs_enabled": false,
  "mcs_model": "sonnet",
  "allowed_inbound_peers": ["bettyxix", "bettyxx"],
  "allowed_outbound_peers": ["bettyxix", "bettyxx"]
}
```

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
├── antenna-peers.json          # Peer registry
├── antenna-config.json         # System configuration
├── antenna.log                 # Transaction log (created at runtime)
├── bin/
│   └── antenna                 # CLI dispatcher
├── scripts/
│   ├── antenna-send.sh         # Sender: builds envelope, POSTs to peer
│   ├── antenna-relay.sh        # Receiver: parses, validates, formats, logs
│   ├── antenna-health.sh       # Peer health check
│   └── antenna-peers.sh        # Peer listing utility
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
