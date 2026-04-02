---
name: antenna
version: 1.0.10
description: >
  Inter-host OpenClaw session messaging over reachable HTTPS using built-in gateway webhook hooks.
  Use when: (1) sending a message from this OpenClaw instance to another host's OpenClaw session,
  (2) checking status/health of a remote OpenClaw peer, (3) managing the peer registry
  (adding/removing/listing known peers), (4) exchanging bootstrap trust material for new peers,
  (5) any cross-host agent communication that should NOT go through visible chat channels like
  Telegram/WhatsApp/Discord. Triggers: "send to <peer>", "message the other host",
  "antenna send", "antenna status", "antenna peers exchange", "cross-host message",
  "inter-host relay", "ping <peer>", "peer list".
---

# Antenna — Inter-Host OpenClaw Messaging (v1.0.10)

Send messages between OpenClaw instances over reachable HTTPS via the built-in `/hooks/agent` webhook.

## Prerequisites

Each participating host needs:
1. OpenClaw gateway running with hooks enabled (`hooks.enabled: true`)
2. A reachable HTTPS endpoint for `/hooks/agent`
3. Antenna agent registered in gateway config (`agents` section)
4. `hooks.allowedAgentIds` includes `"antenna"`
5. `hooks.allowedSessionKeyPrefixes` includes `"hook:antenna"`
6. Host-specific Antenna config in:
   - `antenna-config.json`
   - `antenna-peers.json`

Normal path:
- Run `antenna setup` to generate the live runtime files.
- Use `antenna-config.example.json` and `antenna-peers.example.json` as tracked reference templates only.

Notes:
- Peers do **not** need to share one tailnet or one central hub.
- Tailscale Funnel is a convenient default, but reverse proxies, VPS/domain-hosted HTTPS, Cloudflare Tunnel, and similar paths also work.

## Architecture

Messages flow through a script-first relay pipeline:

1. **Sender** runs `antenna-send.sh` which builds an `[ANTENNA_RELAY]` envelope and POSTs it to the recipient's `/hooks/agent` endpoint.
2. **Recipient gateway** dispatches to the dedicated **Antenna agent**.
3. **Antenna agent** runs `antenna-relay.sh` which deterministically parses, validates, and formats the message.
4. **Antenna agent** calls `sessions_send` to inject the formatted message into the target session.
5. **Message appears** persistently in the target conversation thread.

The LLM never performs relay parsing logic; the scripts do.

## Trust Model

Antenna trust is layered:
- **Peer URL** — where to reach that installation
- **Hook bearer token** — protects webhook ingress
- **Per-peer runtime identity secret** — authenticates claimed sender identity when configured
- **Inbound session allowlist** — limits where inbound relay may deliver
- **Untrusted-input framing** — reminds receiving agents the relayed content may be external

For peer onboarding, Antenna now prefers **Layer A encrypted bootstrap exchange** using `age`.

## Configuration

Live runtime files are local installation state:
- `antenna-config.json`
- `antenna-peers.json`

Tracked reference files live beside them:
- `antenna-config.example.json`
- `antenna-peers.example.json`

Use `antenna setup` for normal installation; use the `*.example.json` files for schema reference or manual recovery.

### `antenna-config.json`

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
  "allowed_inbound_sessions": ["main", "antenna"],
  "allowed_inbound_peers": ["<peer-a>", "<peer-b>"],
  "allowed_outbound_peers": ["<peer-a>", "<peer-b>"],
  "rate_limit": {
    "per_peer_per_minute": 10,
    "global_per_minute": 30
  }
}
```

Key fields:
- `relay_agent_model` — use a full provider/model ID, not a local alias
- `local_agent_id` — used to resolve `main` → `agent:<id>:main`
- `install_path` — absolute path to this skill directory
- `allowed_inbound_sessions` — inbound delivery allowlist
- `allowed_inbound_peers` / `allowed_outbound_peers` — peer allowlists
- `rate_limit.*` — inbound abuse controls

### `antenna-peers.json`

```json
{
  "<your-host-id>": {
    "url": "https://<your-reachable-hostname>",
    "token_file": "secrets/hooks_token_<your-host-id>",
    "peer_secret_file": "secrets/antenna-peer-<your-host-id>.secret",
    "exchange_public_key": "age1...",
    "agentId": "antenna",
    "display_name": "My Host",
    "self": true
  },
  "<remote-peer-id>": {
    "url": "https://<remote-reachable-hostname>",
    "token_file": "secrets/hooks_token_<remote-peer-id>",
    "peer_secret_file": "secrets/antenna-peer-<remote-peer-id>.secret",
    "exchange_public_key": "age1...",
    "agentId": "antenna",
    "display_name": "Remote Host"
  }
}
```

Key fields:
- `url` — reachable HTTPS hook base URL
- `token_file` — bearer token for that peer
- `peer_secret_file` — per-peer runtime identity secret
- `exchange_public_key` — peer's `age` public key for Layer A exchange
- `self` — marks the local host entry

## Usage

### Send a message

```bash
scripts/antenna-send.sh <peer> "Your message here"
antenna msg <peer> "Your message here"
antenna msg <peer> --subject "Config sync" "Here's the block you need..."
antenna msg <peer> --session "agent:<agent-id>:mychannel" "Your message"
echo "Long message body..." | antenna send <peer> --stdin
antenna send <peer> --dry-run "Test message"
```

### Peer onboarding / bootstrap exchange

Preferred encrypted flow:

```bash
antenna peers exchange keygen
antenna peers exchange pubkey
antenna peers exchange initiate <peer-id> --pubkey <age1...> --print
antenna peers exchange import <bundle-file>
antenna peers exchange reply <peer-id>
```

Optional direct-send convenience:

```bash
antenna peers exchange initiate <peer-id> \
  --pubkey <age1...> \
  --email someone@example.com \
  --send-email
```

Legacy/manual fallback:

```bash
antenna peers exchange <peer-id> --export
antenna peers exchange <peer-id> --import <file>
antenna peers exchange <peer-id> --import-value <hex>
```

Notes:
- Secure Layer A requires `age` and `age-keygen`
- Optional direct-send requires `himalaya`
- Email is convenience transport only, not part of the trust model
- Import shows a preview and asks before allowlist changes unless `--yes` is used

### Health and status

```bash
antenna doctor
antenna peers list
antenna peers test <id>
antenna status
antenna log --tail 50
```

### Testing

```bash
antenna test <model>
antenna test-suite --tier A
antenna test-suite --model <m>
antenna test-suite --models "<m1>,<m2>"
antenna test-suite --report
```

## Security Notes

- Relay agent is script-first and non-interpreting
- Inbound sessions are allowlisted
- Sender peer must be allowlisted
- Per-peer identity secret can authenticate sender claims
- Tokens and secrets are file-backed and should be `chmod 600`
- `antenna status` audits secret/token file permissions
- Relayed content is framed as potentially untrusted input
- Rate limiting throttles inbound bursts

## Troubleshooting

- **Gateway won't start**: Run `antenna doctor`
- **401 Unauthorized**: wrong hook bearer token
- **403 Forbidden**: session prefix/agent restrictions or peer policy mismatch
- **Relay rejected**: peer not allowlisted, session not allowlisted, or identity secret mismatch
- **Encrypted exchange fails immediately**: `age` / `age-keygen` missing
- **Email send convenience fails**: `himalaya` missing or no suitable account configured
- **Message sent but not visible**: may be a Control UI display lag rather than delivery failure

## File Inventory

```text
skills/antenna/
├── SKILL.md
├── README.md
├── CHANGELOG.md
├── antenna-config.example.json
├── antenna-peers.example.json
├── antenna-peers.json
├── antenna-config.json
├── antenna.log
├── bin/
│   └── antenna
├── scripts/
│   ├── antenna-send.sh
│   ├── antenna-relay.sh
│   ├── antenna-health.sh
│   ├── antenna-peers.sh
│   ├── antenna-doctor.sh
│   ├── antenna-exchange.sh
│   ├── antenna-model-test.sh
│   └── antenna-test-suite.sh
├── docs/
│   └── ANTENNA-RELAY-FSD.md
└── agent/
    ├── AGENTS.md
    └── TOOLS.md
```

Notes:
- `antenna-config.json` and `antenna-peers.json` are local runtime files created by `antenna setup`
- `antenna-config.example.json` and `antenna-peers.example.json` are tracked reference templates

## Gateway / Agent Registration

On each host:
- agent `antenna` registered in OpenClaw config under `agents`
- `hooks.allowedAgentIds` includes `"antenna"`
- `hooks.allowedSessionKeyPrefixes` includes `"hook:antenna"`
