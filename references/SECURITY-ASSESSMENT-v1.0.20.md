# Antenna Security Risk Assessment — v1.0.20

_Date: 2026-04-06_
_Scope: Security exposures introduced by installing Antenna on a host starting from near-default OpenClaw configuration_

## Risk Assessment

| Ref# | Issue | Severity | Risks | File(s) Affected |
|------|-------|----------|-------|-------------------|
| **SEC-1** | Sandbox disabled on Antenna agent | **HIGH** | • `sandbox: { mode: "off" }` allows relay agent to execute shell commands without isolation • Prompt-injection via crafted message body could theoretically escape script-first pattern if LLM interprets body • Blast radius is full user account | `antenna-setup.sh`, gateway config |
| **SEC-2** | Exec ask disabled (`ask: "off"`) | **HIGH** | • No human-in-the-loop approval for allowlisted binaries • If attacker influences relay agent command (via prompt injection), execution is silent • Mitigated by: allowlist mode, restrictive `tools.deny`, agent instructions prohibiting body interpretation | `antenna-setup.sh`, gateway config |
| **SEC-3** | `commands.ownerDisplay = "raw"` is gateway-wide | **MEDIUM** | • Not scoped to Antenna — changes display for ALL agents/hooks • Could expose internal/system messages previously hidden • Users may not realize one skill changes entire UI behavior | `antenna-setup.sh`, gateway config |
| **SEC-4** | Hooks token stored in plaintext files | **MEDIUM** | • `secrets/hooks_token_*` at `chmod 600` • Setup auto-copies gateway hooks token to skill dir (duplication increases surface) • No encryption at rest | `antenna-setup.sh`, `antenna-peers.json`, `secrets/` |
| **SEC-5** | Per-peer identity secrets in plaintext | **MEDIUM** | • `secrets/antenna-peer-*.secret` hex strings at `chmod 600` • Compromise allows sender impersonation • Generated with good entropy (`openssl rand -hex 32`) but stored unencrypted | `antenna-setup.sh`, `antenna-exchange.sh`, `secrets/` |
| **SEC-6** | Prompt injection via message body | **MEDIUM** | • Message passed as argument to wrapper script • Agent instructions prohibit interpreting body, but LLM compliance is probabilistic • Untrusted-input framing is a soft control • Mechanical model reduces but doesn't eliminate risk | `agent/AGENTS.md`, `antenna-relay-exec.sh`, `antenna-relay.sh` |
| **SEC-7** | Gateway config auto-mutation | **MEDIUM** | • Setup edits `~/.openclaw/openclaw.json` via `jq` transforms • Creates backup but mid-edit corruption possible • Auto-adds hooks, agent entries, tokens, display settings | `antenna-setup.sh` |
| **SEC-8** | Message body passed as shell argument | **MEDIUM** | • Full raw message as `$1` to wrapper • Written to temp file via `printf '%s'` (no shell interpretation) • `max_message_length` default 10000 chars mitigates pathological payloads | `antenna-relay-exec.sh`, `antenna-relay.sh` |
| **SEC-9** | New HTTPS endpoint exposed | **MEDIUM** | • `/hooks/agent` must be reachable over HTTPS • Tailscale Funnel makes this internet-facing • Bearer token is only ingress protection (no IP allowlist, no mTLS) • Rate limits default 10/min peer, 30/min global | `antenna-setup.sh`, `SKILL.md` |
| **SEC-10** | Temp files in shared `/tmp` | **LOW** | • Wrapper writes to `/tmp/antenna-relay-msg.XXXXXX` • Uses `mktemp` + `trap` cleanup • Brief window where content exists on shared filesystem | `antenna-relay-exec.sh` |
| **SEC-11** | Log file may contain sensitive metadata | **LOW** | • `antenna.log` records sender IDs, sessions, timestamps • Verbose mode adds message previews • Auth failure logs secret prefix/suffix hints • Log file at `chmod 644` (world-readable) | `antenna-relay.sh`, `antenna-send.sh` |
| **SEC-12** | Exchange bundle email transport | **LOW** | • Email metadata unencrypted (reveals peering relationship) • Bundle content is `age`-encrypted • Compromise of email alone doesn't expose secrets | `antenna-exchange.sh` |
| **SEC-13** | `tools.sessions.visibility = "all"` may be required | **LOW** | • Gateway-wide setting for multi-agent relay • Allows any agent to see/interact with other agent sessions • Not auto-set by setup, but documented as sometimes needed | `SKILL.md`, continuity docs |
| **SEC-14** | Allowlisted binaries are general-purpose | **LOW** | • `/usr/bin/bash` allowlisted — can run any script • Controlled by: agent-scoped allowlist, `tools.deny` blocks most categories • If agent hijacked, bash = full shell | `antenna-setup.sh`, approvals config |

## Summary

| Severity | Count | Key Theme |
|----------|-------|-----------|
| HIGH | 2 | Sandbox off + silent exec = trust in LLM instruction compliance |
| MEDIUM | 7 | Plaintext secrets, config mutation, prompt injection surface, network exposure |
| LOW | 5 | Temp files, logging, email metadata, cross-agent visibility |

## Mitigations in Place
- Script-first relay (LLM doesn't parse/validate)
- Agent `tools.deny` blocks most tool categories
- Untrusted-input security framing on relayed content
- Per-peer secret authentication
- Rate limiting (per-peer + global)
- Inbound session + peer allowlisting
- Gateway config backup before mutation
- `chmod 600` on all secret files

## Biggest Combined Risk
SEC-1 + SEC-2: sandbox off with silent exec. Necessary for function (confirmed v1.0.20), but means trusting the relay agent never executes anything other than the wrapper script. Mitigations are solid but are soft controls on an LLM, not hard enforcement.
