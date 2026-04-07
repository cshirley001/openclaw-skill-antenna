# Changelog

All notable changes to the Antenna skill are documented here.

## [Unreleased]

## [1.1.5] — 2026-04-06

### Changed
- **Lean skill package:** Split docs into two tiers for distribution clarity:
  - `references/` (ships with skill): `ANTENNA-RELAY-FSD.md`, `issues.md` — files the agent may load during work
  - `docs/` (repo-only, operator/historical): security assessment, red team report, removal checklist, design-history docs
- Updated file inventory in SKILL.md and fixed cross-references in CHANGELOG.md.

## [1.1.4] — 2026-04-06

### Changed
- **Directory convention:** Renamed `docs/` → `references/` to align with AgentSkills spec (`scripts/`, `references/`, `assets/` canonical layout). All internal cross-references updated.
- `agent/` and `bin/` retained as-is — these are infrastructure-skill necessities with no spec equivalent.

## [1.1.3] — 2026-04-06

### Fixed
- **SKILL.md frontmatter compliance:** Removed non-standard `version` key (moved to `metadata.version`); replaced angle brackets in description with uppercase placeholders. Now passes AgentSkills `quick_validate.py` cleanly.
- **Trigger coverage:** Added "check antenna inbox" and "approve message" to description triggers.

## [1.1.2] — 2026-04-06

### Added
- **CLI PATH symlink:** `antenna setup` now automatically symlinks `bin/antenna` into a PATH directory (`/usr/local/bin` or `~/.local/bin`), so agents and humans can run `antenna` directly without knowing the skill install path. Falls back to manual instructions if symlink cannot be created.

## [1.1.1] — 2026-04-06

### Fixed
- **Setup Step 5 display:** `echo` → `echo -e` for ANSI bold/color codes in the inbox mode description
- **Agent ID auto-detection:** Setup now reads gateway config to pre-fill the primary agent ID, reducing the chance of entering the wrong value and getting misrouted sessions (e.g., `agent:betty:main` vs `agent:main:main`)
- **Cross-agent session visibility:** Setup now auto-configures `tools.sessions.visibility=all` and `tools.agentToAgent.enabled=true` in the gateway config, fixing "Session send visibility is restricted" errors on fresh installs
- **Manual fallback instructions** updated with the new visibility/agent-to-agent settings (Step 4) and renumbered

## [1.1.0] — 2026-04-06

### Summary
Inbox: optional approval queue for inbound messages. Directly addresses the two HIGH severity security findings (SEC-1, SEC-2) from the v1.0.20 security assessment by making sandbox-off + silent exec optional rather than required.

### Added
- **Inbox approval queue** (`scripts/antenna-inbox.sh`): When `inbox_enabled` is `true`, inbound messages from non-auto-approved peers are queued for operator review instead of being relayed immediately.
- **Auto-approve peer list** (`inbox_auto_approve_peers` in config): Trusted peers bypass the queue and relay instantly. Provides progressive trust — new peers start in the queue, graduate to auto-approve once trusted.
- **CLI commands:**
  - `antenna inbox` / `antenna inbox list` — table view of pending messages (Ref#, Time, From, To, Preview)
  - `antenna inbox count` — pending count (for heartbeat/cron integration)
  - `antenna inbox show <ref>` — full message body
  - `antenna inbox approve all|<refs>` — selective approval with comma-separated refs and ranges (e.g., `1,3,5-7`)
  - `antenna inbox deny all|<refs>` — selective denial
  - `antenna inbox drain` — outputs JSON delivery instructions for approved items; calling agent delivers via `sessions_send`
  - `antenna inbox clear` — purge processed items
- **Internal `queue-add` command** for `antenna-relay.sh` to add validated messages to the queue.
- **Relay agent `queue` response**: Agent now handles `{"action":"queue"}` script output and replies `Queued: ref #N from <peer>`.

### Changed
- `antenna-relay.sh` — new inbox branch after all validation passes (peer auth, rate limiting, message length). When inbox is enabled, non-auto-approved peers' messages are fully validated then queued. Auto-approved peers and inbox-disabled mode fall through to the existing immediate relay path.
- `antenna-config.example.json` — three new fields: `inbox_enabled`, `inbox_auto_approve_peers`, `inbox_queue_path`.
- `scripts/antenna-setup.sh` — generates inbox config defaults (disabled by default).
- `bin/antenna` — `inbox` subcommand wired with help text.
- `agent/AGENTS.md` — queue response handling added to relay agent instructions.

### Design Decisions
- **Drain outputs JSON, does not self-deliver.** `antenna inbox drain` outputs `{"action":"deliver","sessionKey":"...","message":"..."}` lines to stdout. The calling agent (primary assistant or cron) reads these and calls `sessions_send`. This avoids re-entering the relay agent via `/hooks/agent` which could re-queue the message.
- **Message format is identical.** The relay script builds the complete formatted message (📡 header, security notice, body) *before* the queue decision. Approved messages arrive in the target session looking exactly the same as direct-relay messages.
- **Backwards compatible.** `inbox_enabled: false` (the default) preserves all existing behavior. No changes to the immediate relay path.
- **Inbox reduces relay agent permissions.** With inbox enabled, the relay agent only needs `exec` (to run the relay script that queues). It no longer needs `sessions_send` for queued peers, since delivery moves to the drain caller.

### Security Impact
- Operators who enable inbox mode can optionally run the relay agent with stricter security, since the relay agent no longer delivers directly for queued peers.
- Auto-approve provides tiered trust without all-or-nothing security decisions.
- Queue file has the same exposure profile as the existing antenna.log.

## [1.0.20] — 2026-04-06
### Added
- **Heredoc-free relay wrapper (`antenna-relay-exec.sh`):** New wrapper script that accepts the raw message as `$1`, writes it to a temp file, and pipes to `antenna-relay.sh --stdin`. Avoids all dynamic shell constructs in the exec call.
- **Per-agent exec policy:** Setup now configures `tools.exec.security = "allowlist"` and `tools.exec.ask = "off"` on the antenna agent.

### Changed
- **Relay agent instructions (`agent/AGENTS.md`):** Fully rewritten for allowlist compatibility. The exec command is now a single simple invocation: `bash ../scripts/antenna-relay-exec.sh '<message>'` — no config lookup, no `$(...)`, no chaining. Explicit prohibition on heredocs, here-strings, command substitution, semicolons, `&&`, `||`, and backticks added to agent rules.
- **Setup manual instructions:** Updated to include `tools.exec.security: allowlist` and `tools.exec.ask: off` in the agent registration block.

### Fixed
- **Root cause of persistent exec approvals (CONFIRMED):** OpenClaw's allowlist evaluator flags two classes of dynamic shell constructs — `requiresHeredocApproval` (triggered by `<<` tokens) and inline eval/command substitution (triggered by `$(...)` and backticks). The v1.0.19 relay instructions eliminated heredocs but still used `$(jq -r '.install_path' ...)` for config lookup, which continued to trip allowlist denial. Fixed by removing ALL dynamic constructs: the agent now calls the wrapper via relative path (`../scripts/`) with no config resolution in the exec command itself. The wrapper handles path resolution internally via `SCRIPT_DIR`.
- **Confirmed working:** Tests 11 and 12 on AntTest (clean Ubuntu 24.04 WSL2 environment) both delivered without any approval prompt or exec denial.

## [1.0.19] — 2026-04-06
### Added
- **Control UI visibility:** Setup now sets `commands.ownerDisplay = "raw"` in gateway config. Without this, hook-delivered messages (including Antenna relays) are processed and delivered but invisible in the Control UI chat view. This was the root cause of the long-standing "messages not showing up" issue.
- **Least-privilege agent registration:** Antenna agent is now registered with `sandbox: { mode: "off" }` and a restrictive `tools.deny` list. The tools.deny list blocks web, browser, image, cron, and memory tools — the relay only needs `exec` and `sessions_send`.

## [1.0.18] — 2026-04-03
### Added
- Interactive email prompt after bundle creation: when running `initiate` or `reply` interactively with gog or himalaya available, the wizard now offers to email the bundle directly — no `--send-email` flag needed.
- Multi-method email send: tries `gog` (Gmail API with native `--attach`) first, falls back to `himalaya` (raw MIME via stdin), fails clearly if neither is available.

### Fixed
- `--send-email` crash: himalaya's mail-parser panicked when raw MIME was passed as a CLI argument; switched to stdin pipe.
- Missing `From:` header in himalaya MIME path caused "cannot send message without a sender" error.

## [1.0.17] — 2026-04-03
### Fixed
- `send_bundle_email()` rewritten to use raw MIME with base64-encoded attachment instead of MML (which crashed himalaya's mail-parser).
- Added gog as primary email send method with himalaya as fallback.

## [1.0.16] — 2026-04-03
### Added
- `antenna model show` / `antenna model set <model>` — convenience commands for relay model management.
- `antenna config set relay_agent_model` now syncs the model to the gateway config (`~/.openclaw/openclaw.json`) and restarts the gateway automatically.
- Setup wizard Step 4/6 now reads model aliases from the user's gateway config and presents a numbered picker during interactive install.
- Non-interactive `--model` flag also resolves alias names to full provider/model IDs.

### Changed
- Default relay model changed from `openai/gpt-5.4` to `openai/gpt-5.4-nano-2026-03-17` (cheaper, more mechanical — better suited for relay duty).
- Updated all example/help text to reflect the new default.

## [1.0.15] — 2026-04-03
### Added
- New `antenna uninstall` command for conservative cleanup/removal of Antenna installs.

### Changed
- Began separating **tracked reference config** from **live local runtime config**.
- Added `antenna-config.example.json` and `antenna-peers.example.json` as shareable reference templates.
- Marked `antenna-config.json` and `antenna-peers.json` as local runtime files to be generated by `antenna setup` and kept out of git history.
- Updated setup/docs to point operators toward `antenna setup` for live config generation and `*.example.json` for reference/manual recovery.

### Notes
- `antenna uninstall` removes Antenna runtime files, logs, test artifacts, Antenna-owned secrets, and Antenna gateway registration entries by default, while leaving the rest of OpenClaw alone.
- `--purge-skill-dir` is available for true full removal after cleanup.

## [1.0.11] — 2026-04-03

### Summary
Onboarding hardening: seven rough edges from real first-run experience smoothed out.

### Added
- **Token autodiscovery** in `antenna setup`: reads `hooks.token` from `~/.openclaw/openclaw.json` and offers to create the token file automatically (Item #2).
- **Automatic gateway registration** in `antenna setup`: merges hooks config and registers the Antenna agent entry directly into the gateway JSON, with backup-before-edit and JSON validation. Falls back to manual instructions if user declines or gateway config is not found (Item #3).
- **Schema-aware agent registration**: agent entries omit `systemPrompt` to avoid schema rejection on OpenClaw builds that don't support it inline; uses `agentDir` (not `agentsDir`) to match observed live config schema (Item #4).
- **Interactive `age` installer** in `antenna peers exchange`: when `age` is missing, offers to install via Homebrew; if install fails or is declined, offers legacy fallback interactively instead of hard-failing (Item #5).
- **`peers add` allowlist prompt**: after adding a peer, prompts "Add to inbound/outbound allowlists?" (default: yes). Non-interactive mode auto-adds. Prevents the "not in allowed_outbound_peers" surprise (Item #6).
- **Enhanced auth mismatch diagnostics** in `antenna-relay.sh`: on invalid peer secret, logs prefix/suffix hints of received vs expected values and suggests `antenna peers exchange` resync — without exposing full secrets (Item #7).

### Changed
- `antenna setup` gateway registration section now prints manual instructions only when auto-registration was declined or unavailable.
- `antenna setup` next-steps block adapts based on whether auto-registration succeeded.

### Fixed
- Gateway registration no longer includes `systemPrompt` field that some OpenClaw builds reject (Item #4).

## [1.0.10] — 2026-04-01

### Summary
Layer A encrypted bootstrap exchange implemented and docs synced to the current transport/trust model.

### Added
- **Layer A encrypted bootstrap exchange** in `scripts/antenna-exchange.sh` using `age` armored bundles.
- New exchange commands:
  - `antenna peers exchange keygen`
  - `antenna peers exchange pubkey`
  - `antenna peers exchange initiate <peer-id>`
  - `antenna peers exchange import [file|-]`
  - `antenna peers exchange reply <peer-id>`
- **Import preview + confirmation** before applying allowlist changes.
- **Peer registry support for `exchange_public_key`**.
- **Optional Himalaya direct-send convenience** for bootstrap bundles.

### Changed
- `scripts/antenna-exchange.sh` rewritten from the older raw-secret wizard into a dispatcher that supports encrypted bundle exchange plus explicit legacy fallback.
- `bin/antenna` help text updated for the new exchange flow and peer-add support for `--exchange-public-key`.
- `antenna status` now reports local Layer A key presence and warns when peers lack exchange public keys.
- `references/ANTENNA-RELAY-FSD.md` and `SKILL.md` updated to reflect:
  - reachable HTTPS peer model,
  - layered trust (`url` + hook token + per-peer identity secret),
  - Layer A encrypted onboarding,
  - current config and peer-registry fields.

### Fixed
- `scripts/antenna-exchange.sh` key generation path no longer uses a pre-created temporary file with `age-keygen -o`, which caused `keygen` to fail during functional verification. It now generates inside a temporary directory with fresh output paths.

### Compatibility
- Legacy raw-secret commands remain available:
  - `antenna peers exchange <peer-id> --export`
  - `antenna peers exchange <peer-id> --import <file>`
  - `antenna peers exchange <peer-id> --import-value <hex>`

### Notes
- Secure Layer A requires `age` / `age-keygen`.
- Himalaya is optional; email remains convenience transport only, not part of the trust model.

## [1.0.8] — 2026-03-30

### Summary
Onboarding UX fixes from first real "meat test" (human walkthrough on clean-slate BETTYXX).

### Fixed
- **`antenna setup`** now seeds the host's own ID into `allowed_inbound_peers` and `allowed_outbound_peers` — prevents self-loopback smoke tests from failing with "not in allowed_outbound_peers" immediately after setup.
- **`antenna peers exchange` wizard** reordered secret-sharing options: **paste/import-value** is now Option A (easiest, always works); **pull from remote** is Option B (note that the *other* host's operator can grab the secret); **scp push** is now Option C (only shown when peer URL is known); **manual secure channel** is Option D. Previously SCP was listed first, which assumes bidirectional SSH access that doesn't always exist.

### Changed
- `scripts/antenna-setup.sh` — `allowed_inbound_peers` and `allowed_outbound_peers` now default to `[$host_id]` instead of `[]`.
- `scripts/antenna-exchange.sh` — reordered guided wizard Step 2 options; added "operator can pull" suggestion.

### Tested
- Clean-slate BETTYXX onboarding: `antenna setup` → `peers add` → `peers exchange` → `antenna msg` — full round-trip confirmed.
- Tier A: 11/11 on both BETTYXIX and BETTYXX after changes.

## [1.0.7] — 2026-03-30

### Summary
Token file permission audit in `antenna status` and log value sanitization in the relay script.

### Added
- **Security audit in `antenna status`:** Checks file permissions on all peer token files, config file, and peers file. Warns if any are too permissive (token files should be 600; config/peers should be 644 or tighter). Also now displays rate limit config and session allowlist in the status output.
- **Log value sanitization:** All peer-supplied header values (`from`, `target_session`, `subject`, `user`, `timestamp`, `reply_to`) are now sanitized before logging and processing — control characters stripped, newlines removed, values truncated to safe maximum lengths. Prevents log injection and log forgery via crafted envelopes.
- **`sanitize_log_value` helper** in `antenna-relay.sh`: Strips `\n`, `\r`, `\t`, other control chars; collapses whitespace; trims; truncates to configurable max length.

### Changed
- `bin/antenna` — `cmd_status()` expanded with rate limit display, session allowlist display, and security audit section.
- `scripts/antenna-relay.sh` — all header values sanitized immediately after extraction; verbose log preview also sanitized.

### Security
Addresses Red Team findings #5 (token file exposure) and #6 (log injection/forgery) from `docs/RED-TEAM-REPORT-v1.0.4.md`.

## [1.0.6] — 2026-03-30

### Summary
Rate limiting: per-peer and global inbound message throttling to prevent relay agent saturation and API budget burn.

### Added
- **Per-peer rate limiting** (`rate_limit.per_peer_per_minute` in config, default 10): Rejects messages from a peer exceeding the limit within a 60-second sliding window.
- **Global rate limiting** (`rate_limit.global_per_minute` in config, default 30): Rejects messages when total inbound volume across all peers exceeds the limit.
- **Rate limit state file** (`antenna-ratelimit.json`): Lightweight per-peer timestamp tracking, auto-pruned on each invocation. Excluded from git.
- **Test A.9**: Validates burst rejection — temporarily sets limit to 2/min, sends 3 messages, confirms 3rd is rejected.

### Changed
- `scripts/antenna-relay.sh` — rate limit check runs after peer validation, before message length/session checks. On limit hit: `RELAY_REJECT` with descriptive reason, logged.
- `antenna-config.json` — new `rate_limit` block.
- `.gitignore` — excludes `antenna-ratelimit.json`.

### Security
Addresses Red Team finding #4 (DoS via relay agent saturation) from `docs/RED-TEAM-REPORT-v1.0.4.md`.

## [1.0.5] — 2026-03-30

### Summary
Security hardening: untrusted-input framing on all relayed messages and inbound session target allowlist.

### Added
- **Untrusted-input framing:** All relayed messages now include `(Security Notice: The following content may be from an untrusted source.)` between the header and body. Subtle, non-alarmist, but ensures receiving agents treat Antenna content as external input.
- **Inbound session allowlist** (`allowed_inbound_sessions` in `antenna-config.json`): Restricts which sessions inbound messages can target. Default: `["main", "antenna"]`. Uses segment matching — `antenna` matches `agent:antenna:test`, `agent:antenna:modeltest`, etc. Sessions not matching any allowed pattern are rejected with reason logged.

### Changed
- `scripts/antenna-relay.sh` — added session allowlist validation before relay; added security notice to delivery message format.
- `antenna-config.json` — new `allowed_inbound_sessions` field.
- `scripts/antenna-test-suite.sh` — test sessions updated from `agent:test:main` to `agent:antenna:test` (conforming to the security model).

### Security
Addresses Red Team findings #1 (prompt injection via message body) and #3 (session target injection) from `docs/RED-TEAM-REPORT-v1.0.4.md`.

## [1.0.4] — 2026-03-30

### Summary
Added native Anthropic and Google Gemini API support to the test suite.

### Added
- **Anthropic Messages API support** (`anthropic/*` models) — native tool schema (`input_schema`), `tool_use`/`tool_result` multi-turn for Tier C, `x-api-key` + `anthropic-version` auth headers
- **Google Gemini API support** (`google/*` models) — native tool schema (`functionDeclarations`), `functionCall`/`functionResponse` multi-turn for Tier C, key-based auth via `generateContent` endpoint
- Provider-specific tool definition blocks: `TOOLS_ANTHROPIC`, `TOOLS_GOOGLE` (alongside existing OpenAI-format `TOOLS_JSON`)
- Unified `call_model_api` dispatcher that normalizes all provider responses to a common shape (`http_code`, `elapsed_ms`, `first_tool_name`, `first_tool_args`, `raw`)
- Provider format tag (4th field) in `resolve_model_api` output: `openai`, `anthropic`, or `google`

### Changed
- `run_tier_b()` and `run_tier_c()` rewritten to use unified dispatcher — provider-agnostic assertions
- `check_model_api()` updated to parse 4-field pipe format

### Tested
- `anthropic/claude-sonnet-4-20250514`: 8/8 suite, live smoke PASS (9.3s)
- `google/gemini-2.5-flash`: 8/8 suite, live smoke PASS (~2min — arrives correctly but the hook→agent pipeline is slower; use `--timeout 90`+ for live smoke tests with Gemini)

### Supported providers (Tier B/C) — now 7 families
- OpenAI (`openai/*`)
- OpenAI Codex (`openai-codex/*`)
- OpenRouter (`openrouter/*`)
- Nvidia NIM (`nvidia/*`)
- Ollama (`ollama/*`)
- **Anthropic** (`anthropic/*`) — NEW
- **Google Gemini** (`google/*`) — NEW

## [1.0.3] — 2026-03-30

### Summary
Enriched test messages with meaningful metadata for forensic traceability.

### Changed
- `scripts/antenna-model-test.sh` — live smoke test messages now include: model name, run number, unique nonce, hostname, timestamp, and timeout value (replaces generic "antenna-model-test run N" string)
- `scripts/antenna-test-suite.sh` — Tier B and Tier C test envelopes now include: tier label, model under test, hostname, and test timestamp (replaces static "Hello from the model tester" body)
- Tier C simulated relay output reflects enriched content for consistent C.4 validation
- C.4 assertion updated to match new message content patterns

### Why
Test messages that carry context about what produced them make relay debugging and multi-model comparison forensically useful — you can trace any delivered message back to the exact model, tier, and timestamp that generated it.

## [1.0.2] — 2026-03-30

### Summary
Three-tier test suite with multi-model comparison, structured reports, and multiple output formats.

### Added
- `scripts/antenna-test-suite.sh` — decomposed tester with three evaluation tiers:
  - **Tier A:** deterministic script validation (8 tests) — feeds envelopes into `antenna-relay.sh`, checks JSON output with `jq`. No model, no network.
  - **Tier B:** model → exec tool call (4 tests) — direct provider API call, verifies model emits correct `exec` invocation referencing relay script with envelope.
  - **Tier C:** model → sessions_send (4 tests) — simulated relay response, verifies model emits correct `sessions_send` with matching sessionKey and message.
- Multi-model comparison via `--models "a,b,c"` (max 6) with side-by-side table, scores, timing, and verdict
- `--report [dir]` saves structured output: `summary.md`, `summary.json`, `tier-a.json`, and per-model `tier-b-request.json`, `tier-b-response.json`, `tier-c-request.json`, `tier-c-response.json`
- `--format terminal|markdown|json` output formats
- `--verbose` inline request/response payloads
- CLI wiring: `antenna test-suite [options]`
- `.gitignore` updated to exclude `test-results/`

### Supported providers (Tier B/C) at time of release
- OpenAI (`openai/*`)
- OpenAI Codex (`openai-codex/*`)
- OpenRouter (`openrouter/*`)
- Nvidia NIM (`nvidia/*`)
- Ollama (`ollama/*` — local models)
- (Anthropic and Google added in v1.0.4)

### Note
The existing `antenna test` self-loop integration tester remains available as a smoke/end-to-end test. The new `antenna test-suite` is the primary model compatibility evaluator.

## [1.0.1] — 2026-03-29

### Summary
Portability cleanup. Removed hardcoded host/user/model assumptions from shareable docs and agent files. All host-specific settings now live exclusively in config files.

### Changed
- `relay_agent_model` reverted from `"mini"` alias to full `"openai/gpt-5.4"` provider/model ID
- `agent/AGENTS.md` — replaced hardcoded `/home/corey/clawd/...` paths with relative/config-driven resolution
- `agent/TOOLS.md` — same path portability fix
- `SKILL.md` — generic `<placeholder>` examples instead of Betty/Corey-specific names and URLs
- `README.md` — same generic examples treatment
- `references/ANTENNA-RELAY-FSD.md` — removed host-specific peer IDs, session keys, and display names from examples
- `bin/antenna` — generic usage examples; status fallback model shows `"unset"` instead of `"mini"`
- `scripts/antenna-relay.sh` — fallback `local_agent_id` changed from `"betty"` to `"agent"`

### Added
- `install_path` field in `antenna-config.json` — allows agent/scripts to resolve paths on any host

### Portability principle
Config files (`antenna-config.json`, `antenna-peers.json`) hold all host-specific state. Docs and agent files use generic placeholders. New installations edit config, not code.

## [1.0.0] — 2026-03-29

### Summary
First stable release. Script-first relay architecture with dedicated lightweight agent, full CLI, peer management, and transaction logging.

### Added
- `antenna-send.sh` — builds `[ANTENNA_RELAY]` envelope and POSTs to peer `/hooks/agent`
- `antenna-relay.sh` — deterministic parsing, validation, formatting, and logging on the receiving end
- `antenna-health.sh` — peer health check via `/health` endpoint
- `antenna-peers.sh` — list known peers from registry
- `bin/antenna` — CLI dispatcher (`send`, `msg`, `peers`, `config`, `log`, `status`)
- `antenna-config.json` — system configuration (max message length, allowed peers, logging, MCS toggle)
- `antenna-peers.json` — flat peer registry with URL, token file, display name, self flag
- `agent/AGENTS.md` — dedicated Antenna relay agent instructions
- `agent/TOOLS.md` — agent tool reference (relay script paths)
- `references/ANTENNA-RELAY-FSD.md` — full functional specification (v1.0.0)
- Transaction logging to `antenna.log` (metadata only; verbose mode optional)
- Sender validation against `allowed_inbound_peers` on receipt
- Outbound validation against `allowed_outbound_peers` on send
- `--dry-run` flag for envelope inspection without sending
- `--user` flag for optional humanized sender mode (experimental)
- Return-address headers for two-way messaging
- `main` session shorthand resolved to `agent:<local_agent_id>:main`

### Fixed (relative to v0.x development)
- `antenna-health.sh` updated from stale `.peers[]` registry format to current flat format
- `antenna-peers.sh` updated from stale `.peers[]` registry format to current flat format
- Removed stray `user_name` field from `antenna-config.json`
- Reconciled `relay_agent_model` across config and docs (now consistently `"openai/gpt-5.4"`)

### Architecture Decisions
- **Script-first**: all deterministic logic in bash scripts, not the LLM
- **Dedicated agent**: separate from primary assistant, minimal workspace/context (~2k tokens vs ~23k)
- **Plain relay default**: host-based envelope format is the stable path; humanized sender mode is opt-in
- **Fire-and-forget**: async messaging, no persistent connections, no blocking

### Known Limitations
- MCS (Malicious Content Scanning) designed but deferred — toggle exists in config, not yet implemented
- `--since` flag in `antenna log` not yet implemented (shows last N entries instead)
- Peer discovery is manual (no auto-discovery)
- Local model aliases may not resolve in all gateway agent configs — prefer a full provider/model ID in shareable skill defaults

## [0.x] — 2026-03-26 to 2026-03-28

Development iterations. Not individually versioned. See `references/ANTENNA-RELAY-FSD.md` revision history for details.
