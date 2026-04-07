# 🔴 Red Team Assessment — Antenna v1.0.4

**Date:** 2026-03-30
**Assessor:** Betty XIX Openclaw
**Scope:** Antenna skill v1.0.4, including relay scripts, agent config, CLI, test suite, and inter-host communication path over Tailscale.
**Method:** Architecture review, code inspection, threat modeling. No active exploitation attempted.
**Last updated:** 2026-03-30 (v1.0.7 — reflects all mitigations through v1.0.7)

---

## Attack Surface Summary

Antenna sits at the intersection of three layers where things can go wrong:

1. **Network ingress** — Tailscale + `/hooks/agent` webhook
2. **Shell execution** — relay scripts (`antenna-relay.sh`, `antenna-send.sh`)
3. **LLM tool use** — relay agent calls `sessions_send` to deliver messages

---

## Findings

### 1. ✅ Prompt Injection via Message Body → Session Takeover

| | |
|---|---|
| **Severity** | 🔴 HIGH |
| **Status** | ✅ **Mitigated in v1.0.5** |
| **Exploitability** | Any peer with send access |

**Description:** The relay agent doesn't interpret message content — the script-first design is resistant here. However, the **target session agent** (e.g., Betty) receives the delivered Antenna message as normal session input. A malicious peer can craft a message containing prompt injection.

**Mitigation applied (v1.0.5):**
- Relay script now prepends a security notice to all delivered messages: *"(Security Notice: The following content may be from an untrusted source.)"*
- This frames inbound Antenna messages as untrusted input for the receiving agent.

**Residual risk:** Depends on target agent respecting the framing. MCS scanning (§19.5) remains a medium-term enhancement.

---

### 2. 🔴 Shared Hooks Token — Single Point of Compromise

| | |
|---|---|
| **Severity** | 🔴 HIGH |
| **Status** | ⏳ **Open — next priority** |
| **Exploitability** | Requires access to any one peer's token file |

**Description:** All peers authenticate with the same shared bearer token. Compromise one peer's token → impersonate any peer to any other peer. The `from` field in the envelope is **self-reported** and checked against `allowed_inbound_peers`, but there is no cryptographic binding between the `from` claim and the actual sender.

**Attack scenario:** Attacker gains access to BETTYXX's token file. Sends messages to BETTYXIX with `"from": "bettyxx"` — indistinguishable from legitimate traffic. Or worse, with `"from": "trusted-admin-host"` if that peer is in the allowlist.

**Recommendation:**
- **Next:** Per-peer tokens — each peer uses a unique token. Receiving side maps token → peer identity, eliminating trust of self-reported `from`.
- **v2.0:** Signed envelopes (§19.1) — sender signs with private key, recipient verifies with sender's public key.

**Effort:** 2–3 hours (per-peer tokens); 1–2 days (signed envelopes)

---

### 3. ✅ Session Target Injection

| | |
|---|---|
| **Severity** | 🟡 MEDIUM |
| **Status** | ✅ **Mitigated in v1.0.5** |
| **Exploitability** | Any peer with send access |

**Description:** The `--session` parameter lets the sender target any session. Without restriction, a peer could inject messages into the primary conversation thread.

**Mitigation applied (v1.0.5):**
- Config-driven `allowed_inbound_sessions` list (default: `["main", "antenna"]`).
- Relay script validates target session against the allowlist using segment matching before delivery.
- Disallowed sessions are rejected with a descriptive reason.

---

### 4. ✅ Denial of Service via Relay Agent Saturation

| | |
|---|---|
| **Severity** | 🟡 MEDIUM |
| **Status** | ✅ **Mitigated in v1.0.6** |
| **Exploitability** | Any peer (or anyone with the hooks token) |

**Description:** Without rate limiting, each inbound message triggers a relay agent turn consuming an LLM API call. Spam could burn API budget and saturate the relay.

**Mitigation applied (v1.0.6):**
- Per-peer rate limiting (`rate_limit.per_peer_per_minute`, default 10).
- Global rate limiting (`rate_limit.global_per_minute`, default 30).
- State tracked in `antenna-ratelimit.json` with auto-pruning sliding window.
- Exceeding limits → immediate `RELAY_REJECT`, no LLM call consumed.
- Test A.9 validates burst rejection.

---

### 5. ✅ Token File Exposure

| | |
|---|---|
| **Severity** | 🟡 MEDIUM |
| **Status** | ✅ **Mitigated in v1.0.7** |
| **Exploitability** | Requires host access or repo misconfiguration |

**Description:** Token files referenced in `antenna-peers.json` could leak if the skill directory is accidentally made world-readable or if secrets are committed to git.

**Mitigation applied (v1.0.7):**
- `antenna status` now includes a **Security Audit** section that checks file permissions on all peer token files, config file, and peers file.
- Warns if any file is more permissive than expected (token files: 600; config/peers: 644 or tighter).
- `.gitignore` already covers `secrets/` and runtime state files.

---

### 6. ✅ Log Injection / Log Forgery

| | |
|---|---|
| **Severity** | 🟢 LOW |
| **Status** | ✅ **Mitigated in v1.0.7** |
| **Exploitability** | Any peer with send access |

**Description:** Transaction logs include peer-supplied metadata. Crafted `from` fields with newlines or control characters could inject fake log entries or break log parsing.

**Mitigation applied (v1.0.7):**
- `sanitize_log_value` helper strips control characters (`\n`, `\r`, `\t`, etc.), collapses whitespace, trims, and truncates all header values to safe maximum lengths.
- Applied to all peer-supplied fields (`from`, `target_session`, `subject`, `user`, `timestamp`, `reply_to`) immediately after extraction.
- Verbose log preview also sanitized.

---

### 7. Relay Agent Model Integrity

| | |
|---|---|
| **Severity** | 🟢 LOW |
| **Status** | ⏳ **Partially mitigated (test suite)** |
| **Exploitability** | Not directly exploitable; operational risk |

**Description:** The relay agent uses an LLM to bridge between script output and `sessions_send`. If the model hallucinates or misinterprets script output, messages could be garbled.

**Current mitigation:**
- Three-tier test suite (v1.0.2+) catches model-level failures across 7 provider families before any relay model change.
- Enriched forensic metadata in test messages (v1.0.3+) enables detailed post-mortem.

**Residual:** Relay integrity hash (script output includes message hash; delivered message verified against it) remains a future enhancement.

---

### 8. Tailscale Dependency = Tailscale Trust

| | |
|---|---|
| **Severity** | 🟢 LOW (accepted risk) |
| **Status** | ⚪ **Accepted** |
| **Exploitability** | Requires Tailscale compromise |

**Description:** All security assumes Tailscale network integrity. If Tailscale is compromised, all Antenna traffic — including bearer tokens — is exposed.

**Accepted:** This is a deliberate architectural decision. §19.1 (encryption) would add defense-in-depth.

---

## Priority Matrix (updated v1.0.7)

| Priority | Action | Finding | Status |
|----------|--------|---------|--------|
| ~~🔴 Now~~ | ~~Add untrusted-input framing~~ | #1 | ✅ v1.0.5 |
| ~~🔴 Now~~ | ~~Tighten session target allowlist~~ | #3 | ✅ v1.0.5 |
| ~~🟡 Soon~~ | ~~Rate limiting~~ | #4 | ✅ v1.0.6 |
| ~~🟡 Soon~~ | ~~Token file permission check~~ | #5 | ✅ v1.0.7 |
| ~~🔵 v2.0~~ | ~~Log value sanitization~~ | #6 | ✅ v1.0.7 |
| 🔴 **Next** | **Per-peer tokens** | #2 | ⏳ In progress |
| 🔵 v2.0 | Signed envelopes (§19.1) | #2 | Planned |
| 🔵 v2.0 | Relay integrity hash | #7 | Planned |
| ⚪ Accepted | Tailscale trust dependency | #8 | — |

---

## Summary

Six of eight findings are now mitigated. The **script-first architecture remains fundamentally sound**. The remaining high-severity item (#2 — per-peer tokens) is the next implementation priority. Finding #7 (relay integrity hash) is low-severity and tracked for v2.0. Finding #8 is an accepted architectural decision.

---

*Report filed by Betty XIX Openclaw — 2026-03-30*
*Updated through v1.0.7 mitigations*
