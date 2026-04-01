# 📡 Antenna — Inter-Host OpenClaw Messaging

Send messages between OpenClaw instances using the built-in `/hooks/agent` webhook. Works across Tailscale (direct or Funnel), or any public HTTPS endpoint — your infrastructure, your choice. No custom server, no persistent connections — just fire-and-forget relay with full audit logging.

## What It Does

- **Cross-host messaging** between OpenClaw instances — Tailscale, Funnel, Cloudflare Tunnel, reverse proxy, or any reachable HTTPS URL
- **Script-first relay** — all parsing, validation, and formatting is deterministic (no LLM interpretation of message content)
- **Dedicated lightweight relay agent** — minimal context, minimal cost per relay
- **Peer registry** — manage known hosts with URLs, tokens, and display names
- **Transaction logging** — every send/receive is logged with metadata
- **CLI interface** — `antenna msg`, `antenna peers`, `antenna status`, etc.

## Quick Start

### Prerequisites

1. Two or more OpenClaw instances, each with a **reachable HTTPS endpoint** (Tailscale Funnel, Cloudflare Tunnel, reverse proxy, VPS — any works)
2. Hooks enabled on all instances (`hooks.enabled: true`)
3. Each peer's hooks bearer token (exchanged out-of-band; per-peer, not shared)
4. Per-peer identity secrets for sender authentication (generated during `antenna setup` / `antenna peers exchange`)
5. The `antenna` agent registered on each instance

### Install & Configure

1. Copy or install the skill into your OpenClaw `skills/antenna/` directory
2. Edit `antenna-config.json` — set `local_agent_id`, `install_path`, `relay_agent_model`, and your allowed peers
3. Edit `antenna-peers.json` — add your hosts (mark one as `"self": true`)
4. Register the `antenna` agent in your gateway config

### Send a message

```bash
antenna msg <peer-id> "Hello from across the reef!"
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

## Testing

Built-in three-tier test suite to validate relay script correctness and model compatibility across 7 provider families (OpenAI, OpenAI Codex, OpenRouter, Nvidia NIM, Ollama, Anthropic, Google Gemini):

```bash
# Script-only validation (no model, no network)
antenna test-suite --tier A

# Full suite against a single model
antenna test-suite --model openai/gpt-5.4

# Compare multiple models side-by-side (max 6)
antenna test-suite --models "anthropic/claude-sonnet-4-20250514,google/gemini-2.5-flash,openai/gpt-5.4"

# Save structured report with request/response dumps
antenna test-suite --models "anthropic/claude-sonnet-4-20250514,google/gemini-2.5-flash" --report
```

| Tier | Tests | What it checks |
|------|-------|----------------|
| A | 8 | Relay script parsing, validation, rejection, session mapping |
| B | 4 | Model correctly calls `exec` with relay script and envelope |
| C | 4 | Model correctly calls `sessions_send` with relay output |

Each provider uses its **native API format** — Anthropic's Messages API, Google's generateContent, OpenAI-compatible chat/completions — with provider-specific tool schemas and multi-turn conventions.

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

**1.0.4** — Anthropic + Google Gemini native API support in test suite (7 provider families).

## License

MIT
