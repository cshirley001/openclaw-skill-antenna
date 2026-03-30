# 📡 Antenna — Inter-Host OpenClaw Messaging

Send messages between OpenClaw instances over Tailscale using the built-in `/hooks/agent` webhook. No custom server, no persistent connections — just fire-and-forget relay with full audit logging.

## What It Does

- **Cross-host messaging** between any OpenClaw instances on the same Tailscale network
- **Script-first relay** — all parsing, validation, and formatting is deterministic (no LLM interpretation of message content)
- **Dedicated lightweight relay agent** — minimal context, minimal cost per relay
- **Peer registry** — manage known hosts with URLs, tokens, and display names
- **Transaction logging** — every send/receive is logged with metadata
- **CLI interface** — `antenna msg`, `antenna peers`, `antenna status`, etc.

## Quick Start

### Prerequisites

1. Two or more OpenClaw instances on the same Tailscale network
2. Hooks enabled on all instances (`hooks.enabled: true`)
3. A shared hooks token across peers
4. The `antenna` agent registered on each instance

### Install & Configure

1. Copy or install the skill into your OpenClaw `skills/antenna/` directory
2. Edit `antenna-config.json` — set `local_agent_id`, `install_path`, `relay_agent_model`, and your allowed peers
3. Edit `antenna-peers.json` — add your hosts (mark one as `"self": true`)
4. Register the `antenna` agent in your gateway config

### Send a message

```bash
antenna msg <peer-id> "Hello from across the tailnet!"
```

### Check peer health

```bash
antenna peers test <peer-id>
```

### View status

```bash
antenna status
```

## How It Works

```
Sender                                  Recipient
──────                                  ─────────
antenna-send.sh                         /hooks/agent endpoint
  → builds [ANTENNA_RELAY] envelope       → Antenna agent runs antenna-relay.sh
  → POSTs to peer via Tailscale             → script parses, validates, formats
                                            → agent calls sessions_send
                                            → message appears in target session
```

## Security

- All traffic encrypted via Tailscale (WireGuard)
- Bearer token authentication on every request
- Sender validated against allowlist on receipt
- Session injection restricted by prefix allowlist
- Relay agent never interprets message body content

## Configuration

All host-specific settings live in two files that **must be edited** for your environment:
- `antenna-config.json` — model, agent ID, install path, allowed peers, logging
- `antenna-peers.json` — peer URLs, tokens, display names

No hardcoded defaults assume a particular host, user, or model. See `SKILL.md` for full documentation.

## Version

**1.0.1** — Stable baseline with portable configuration.

## License

MIT
