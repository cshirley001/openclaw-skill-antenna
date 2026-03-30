# Changelog

All notable changes to the Antenna skill are documented here.

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
- `docs/ANTENNA-RELAY-FSD.md` — removed host-specific peer IDs, session keys, and display names from examples
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
- `docs/ANTENNA-RELAY-FSD.md` — full functional specification (v1.0.0)
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

Development iterations. Not individually versioned. See `docs/ANTENNA-RELAY-FSD.md` revision history for details.
