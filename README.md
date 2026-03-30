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

### Send a message

```bash
antenna msg bettyxx "Hey Sis, what's the weather like over there?"
```

### Check peer health

```bash
antenna peers test bettyxx
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

Edit `antenna-config.json` for system defaults and `antenna-peers.json` for the peer registry. See `SKILL.md` for full documentation.

## Version

**1.0.0** — Stable baseline. Plain relay mode. Tested between Betty XIX (WSL2 server) and Betty XX (laptop).

## License

MIT
