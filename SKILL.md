---
name: antenna
description: >
  Inter-host OpenClaw session messaging over reachable HTTPS using built-in
  gateway webhook hooks. Use when: (1) sending a message from this OpenClaw
  instance to another host's session, (2) checking status/health of a remote
  peer, (3) managing the peer registry (adding/removing/listing known peers),
  (4) exchanging bootstrap trust material for new peers, (5) any cross-host
  agent communication that should NOT go through visible chat channels like
  Telegram/WhatsApp/Discord. Triggers: "send to PEER", "message the other
  host", "antenna send", "antenna status", "antenna peers exchange",
  "cross-host message", "inter-host relay", "ping PEER", "peer list",
  "check antenna inbox", "approve message".
metadata:
  version: 1.2.20
postInstall: "bash skills/antenna/bin/antenna.sh setup"
---

# Antenna — Inter-Host OpenClaw Messaging (v1.2.20)

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
3. **Antenna agent** writes the raw inbound message to a temp file using the `write` tool (structured API call, no shell metacharacter concerns).
4. **Antenna agent** execs `antenna-relay-file.sh` with the file path — the script feeds the message to `antenna-relay.sh` which deterministically parses, validates, and formats it.
5. **Antenna agent** calls `sessions_send` to inject the formatted message into the target session.
6. **Message appears** persistently in the target conversation thread.

The LLM never performs relay parsing, encoding, or transformation; the scripts do all processing.

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
  "default_target_session": "agent:betty:main",
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
  "allowed_inbound_sessions": ["agent:betty:main", "agent:betty:antenna"],
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
- `local_agent_id` — used by local CLI conveniences when expanding bare names to full session keys like `agent:<id>:main`
- `install_path` — absolute path to this skill directory
- `allowed_inbound_sessions` — inbound delivery allowlist (full session keys, e.g. `agent:betty:main`)
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
antenna msg <peer> "Your message here"                              # recipient resolves target session
antenna msg <peer> --subject "Config sync" "Here's the block you need..."
antenna msg <peer> --session "agent:<agent-id>:mychannel" "Your message"  # explicit session override
echo "Long message body..." | antenna send <peer> --stdin
antenna send <peer> --dry-run "Test message"
```

> **Session resolution:** When `--session` is omitted, `target_session` is left out of the
> envelope entirely. The recipient resolves from their own `default_target_session` config.
> You don't need to know another host's internal session layout.

### Peer pairing (interactive wizard)

```bash
antenna pair                          # Full interactive wizard
antenna pair --peer-id myserver       # Pre-fill peer ID
```

The wizard walks through keypair generation, public key sharing, optional ClawReef invite, bundle creation, optional bundle email send when mail tooling is available, exchange, connectivity test, and first message — with Next/Skip/Quit at each step. Also auto-offered at the end of `antenna setup`.

### Peer onboarding / bootstrap exchange (manual)

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

### Session allowlist management

```bash
antenna sessions list                             # Show allowed inbound session targets
antenna sessions add antv3                        # Bare name → auto-expanded to agent:<local>:antv3
antenna sessions add "agent:marie:lab1"            # Cross-agent: use full session key
antenna sessions remove antv3                     # Remove (bare names are expanded)
antenna sessions remove "agent:betty:main" --force # Core sessions need --force
```

Controls which session targets inbound messages can request via `allowed_inbound_sessions` in `antenna-config.json`.

**Convention: full session keys everywhere.** The allowlist stores full keys like `agent:betty:main` and `agent:marie:lab1`. The relay requires full keys from senders — bare names are rejected. The CLI auto-expands bare names to `agent:<local_agent>:<name>` for convenience when adding/removing, but the stored value is always the full key.

Core sessions (`agent:<local>:main`, `agent:<local>:antenna`) are protected from removal unless `--force` is used. Supports batch add/remove.

### Health and status

```bash
antenna doctor
antenna uninstall --dry-run
antenna uninstall
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

### Inbox (optional approval queue)

When `inbox_enabled` is `true` in config, inbound messages from peers not in `inbox_auto_approve_peers` are queued for review instead of being relayed immediately. Auto-approved peers bypass the queue and relay instantly (current behavior).

```bash
antenna inbox                        # list pending messages (table view)
antenna inbox count                  # pending count (for heartbeat/cron checks)
antenna inbox show <ref>             # full message body for a ref
antenna inbox approve all            # approve everything pending
antenna inbox approve 1,3,5-7       # selective approval (commas and ranges)
antenna inbox deny all               # reject everything pending
antenna inbox deny 2,4               # selective denial
antenna inbox drain                  # output delivery JSON for approved, remove denied
antenna inbox clear                  # purge all processed items
```

**Delivery flow:** `antenna inbox drain` outputs one JSON line per approved message with `sessionKey` and `message` fields. The calling agent (your primary assistant) reads these and calls `sessions_send` for each. This avoids re-entering the relay agent via `/hooks/agent`.

**Configuration:**
```json
{
  "inbox_enabled": false,
  "inbox_auto_approve_peers": ["trusted-peer-id"],
  "inbox_queue_path": "antenna-inbox.json"
}
```

Notes:
- Disabled by default — existing behavior is unchanged
- Auto-approve list lets trusted peers bypass the queue (progressive trust)
- Queue file is local runtime state (gitignored)
- Ref numbers auto-increment and support range selection
- When inbox is enabled, the relay agent only needs `exec` (not `sessions_send`), reducing its required permissions

**Heartbeat / cron integration:**

Add to your `HEARTBEAT.md`:
```markdown
## Antenna inbox check
- Run: `antenna inbox count`
- If > 0: run `antenna inbox list` and mention it
```

Or set up a cron job for automated handling:
```
Check antenna inbox. If there are pending messages from peers
in [trusted-peer-id], approve and drain them. For anything else,
summarize the queue and ask me.
```

**Conversational usage:** Ask your assistant "any Antenna messages waiting?" — it can run `antenna inbox list`, you review, then say "approve 1 and 3, deny 2" and it handles the rest.

## ClawReef — Peer Discovery

[clawreef.io](https://clawreef.io) is the optional community registry for Antenna hosts:

- **Discover peers** — browse and search the directory
- **Send invites** — ClawReef delivers them via Antenna to the recipient's default session
- **Accept & pair** — accepting an invite starts the normal `antenna pair` flow locally

ClawReef stores webhook credentials (`hooksToken`, `identitySecret`) for push delivery alongside public keys and endpoints — standard webhook-provider behavior. It does not store messages, private age keys, or message content. All trust decisions remain local to Antenna.

The pairing wizard (`antenna pair`) offers ClawReef invites as an alternative to manual encrypted exchange. Setup also displays ClawReef info after completion.

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
- **Want a clean slate**: Run `antenna uninstall` (use `--dry-run` first if you want a preview)
- **401 Unauthorized**: wrong hook bearer token
- **403 Forbidden**: session prefix/agent restrictions or peer policy mismatch
- **Relay rejected**: peer not allowlisted, session not allowlisted, or identity secret mismatch
- **Encrypted exchange fails immediately**: `age` / `age-keygen` missing
- **Email send convenience fails**: `himalaya` missing or no suitable account configured
- **Message sent but not visible**: ensure `tools.sessions.visibility = "all"` and `tools.agentToAgent.enabled = true` on the receiver; the relay agent uses cross-agent `sessions_send`, which requires both settings. Also ensure `sandbox: { mode: "off" }` on the Antenna agent — sandboxed sessions silently clamp visibility to `tree`, blocking cross-agent delivery
- **Exec denied / allowlist miss**: ensure relay agent instructions use only simple commands (no `$(...)`, heredocs, or chaining); the `antenna-relay-file.sh` wrapper accepts a file path only
- **Repeated approval prompts**: ensure Antenna agent has `sandbox: { mode: "off" }` in registration. Do **not** set `tools.exec.security` or `tools.exec.ask` on the Antenna agent — explicit exec overrides cause silent relay failure (fixed in v1.2.14)

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
├── install.sh
├── bin/
│   └── antenna.sh
├── scripts/
│   ├── antenna-send.sh
│   ├── antenna-relay.sh
│   ├── antenna-relay-file.sh           # v1.1.8 — file-based relay input (preferred)
│   ├── antenna-relay-exec.sh            # v1.1.6 — base64 wrapper (legacy fallback)
│   ├── antenna-pair.sh                  # v1.1.9 — interactive peer pairing wizard
│   ├── antenna-health.sh
│   ├── antenna-peers.sh
│   ├── antenna-doctor.sh
│   ├── antenna-exchange.sh
│   ├── antenna-inbox.sh
│   ├── antenna-model-test.sh
│   └── antenna-test-suite.sh
├── references/
│   ├── ANTENNA-RELAY-FSD.md          # Relay architecture contract
│   └── issues.md                      # Known issues / gaps tracker
├── docs/                               # Repo-only (operator / historical)
│   ├── full-removal-checklist.md
│   ├── SECURITY-ASSESSMENT-v1.0.20.md
│   ├── RED-TEAM-REPORT-v1.0.4.md
│   ├── LAYER-A-SECRET-EXCHANGE-PLAN.md
│   └── SECRET-EXCHANGE-OPTIONS.md
└── agent/
    ├── AGENTS.md
    └── TOOLS.md
```

Notes:
- `antenna-config.json`, `antenna-peers.json`, and `antenna-inbox.json` are local runtime files (gitignored)
- `antenna-config.example.json` and `antenna-peers.example.json` are tracked reference templates

## Gateway / Agent Registration

On each host:
- agent `antenna` registered in OpenClaw config under `agents` with:
  - `agentDir` and `workspace` both pointing to the Antenna `agent/` directory
  - `sandbox: { mode: "off" }` (required — sandbox silently clamps session visibility, breaking cross-agent relay)
  - restrictive `tools.deny` (block web, browser, image, cron, memory tools)
  - **Do not** set `tools.exec.security` or `tools.exec.ask` on the Antenna agent — explicit exec overrides cause silent relay failure (see v1.2.14 changelog)
- `hooks.allowedAgentIds` includes `"antenna"`
- `hooks.allowedSessionKeyPrefixes` includes `"hook:antenna"`
- `tools.sessions.visibility` set to `"all"` (required for cross-agent `sessions_send`)
- `tools.agentToAgent.enabled` set to `true`

## Support

- 📧 **Email:** [help@clawreef.io](mailto:help@clawreef.io)
- 🐛 **Issues:** [github.com/ClawReefAntenna/antenna/issues](https://github.com/ClawReefAntenna/antenna/issues)
- 🔒 **Security:** See [SECURITY.md](SECURITY.md)
