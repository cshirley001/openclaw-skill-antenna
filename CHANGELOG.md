# Changelog

All notable changes to the Antenna skill are documented here.

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

### Supported providers (Tier B/C)
- OpenAI (`openai/*`)
- OpenAI Codex (`openai-codex/*`)
- OpenRouter (`openrouter/*`)
- Nvidia NIM (`nvidia/*`)
- Ollama (`ollama/*` — local models)
- Anthropic and Google: planned but not yet adapted

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
