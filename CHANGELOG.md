# Changelog

All notable changes to the Antenna skill are documented here.

This file is the forward-looking, `[Unreleased]` + recent-releases changelog shipped with the skill.
For the complete version history prior to `1.3.0`, see:

- GitHub releases: https://github.com/cshirley001/openclaw-skill-antenna/releases
- Full historical changelog (in-repo): [`references/CHANGELOG-HISTORY.md`](references/CHANGELOG-HISTORY.md)

## [Unreleased]

## [1.3.2] — 2026-04-21

### Docs
- **README rendering fix for ClawHub.** Removed the `# H1` heading from the top of `README.md` and moved the project tagline into a blockquote. ClawHub's skill-page "README" tab was falling back to `SKILL.md` when `README.md` opened with its own `# ` heading (an emoji-prefixed H1 in our case); the new layout matches the convention used by other skills that ship both files so the registry renders the real README body.
  Docs impact: readme_rendering

## [1.3.1] — 2026-04-21

### Changed
- **Changelog slimmed down.** Pre-`1.3.0` entries moved to `references/CHANGELOG-HISTORY.md`. The current file covers `[Unreleased]` plus the most recent releases; full history lives on GitHub and in the history file.
  Docs impact: changelog_layout
- **Registry bundle trimmed.** Added `.clawhubignore` so internal review/QA documents and historical drafts stay in the git repo but are no longer shipped to the ClawHub registry. Specifically excluded: `references/ANTV4-PHASE-1-REVIEW.md`, `references/ANTV4-VALIDATION-CHECKLIST.md`, `references/ANTV4-VALIDATION-CHECKLIST-SHORT.md`, `references/copy-draft-v1.2.0.md`, `references/issues.md`, `references/setup-completion-v1.1.8.md`, `references/GAPS.md`.
  Docs impact: registry_bundle_contents

### Docs
- README "Version" section updated to reflect the current published release and to point at the in-repo full-history changelog.
  Docs impact: version_number

## [1.3.0] — 2026-04-20

### Security
- **REF-603 — plaintext bootstrap bundle JSON could leak in `/tmp` on failure.** `scripts/antenna-exchange.sh` now streams outbound bootstrap JSON directly from `jq` into `age` instead of writing a plaintext temp file first, and the import path installs cleanup traps immediately after decrypt so decrypted plaintext JSON is removed on normal return, validation failure, or signal interruption.
  Docs impact: bootstrap_bundle_handling
- **REF-400 — envelope-marker collisions could smuggle fake headers.** `scripts/antenna-relay.sh` now rejects any message whose body or sanitized header values contain `[ANTENNA_RELAY]` or `[/ANTENNA_RELAY]`, logging `status:MALFORMED (marker in body|headers)`. Sender (`antenna-send.sh`) also guards against injecting markers outbound.
- **REF-402 — no timestamp freshness check on inbound messages.** Relay now validates `timestamp:` against a freshness window (default: max 300s old, 60s future skew), configurable via `.security.max_message_age_seconds` / `.security.max_future_skew_seconds`. Rejected lines carry `nonce:` for correlation, consistent with REF-1501.
- **REF-403 (partial) — plaintext auth envelope persisted on receiver disk.** Relay temp files (`antenna-relay-exec.sh`, `antenna-relay-file.sh`) are now created under `umask 077`, `chmod 0600`'d, and `shred`'d-before-unlink on cleanup (best-effort, falls back to truncate+rm). The `/tmp/antenna-relay` parent dir is tightened to `0700` when owned. Full REF-403 (removing `auth:` from the wire) remains tracked alongside REF-402 HMAC work.
- **REF-404 — self-id fell back to `$(hostname)` if config was missing.** `antenna-send.sh` now fails fast with a clear error instead of silently using the machine hostname as a peer identity, preventing accidental cross-host identity collisions.
- **REF-501 — auth comparison was not constant-time.** Relay-side peer-secret comparison now uses a constant-time path to eliminate timing side-channels on secret verification.
- **REF-601 — expired bundle import succeeded silently.** `antenna-exchange.sh` import path now validates bundle expiry and refuses expired material with a clear error, covered by `tests/ref-601-expired-bundle-refusal.sh`.
- **REF-616 — exchange-bundle emails sent with bogus `antenna@localhost` From address.** `scripts/antenna-exchange.sh` now resolves sender email from the Himalaya TOML config at `${HIMALAYA_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/himalaya/config.toml}`. Both `send_bundle_email` and `send_pubkey_email` hard-fail if the account's email cannot be resolved. Interactive flows use selection-only confirmation through `confirm_from_account`. `--account <name>` remains supported as strict selection of a configured account.
  Docs impact: exchange_email_from_resolution

### Fixed
- **REF-300 / REF-303 — `antenna peers add` silently overwrote existing entries and null-ed out un-supplied fields.** `cmd_peers add` now refuses to touch an existing peer unless `--force` is given, and `--force` applies merge semantics: only fields explicitly supplied on the command line are overwritten, everything else (including unknown top-level fields like `.self` set by peer-exchange) is preserved.
  Docs impact: peers_add_overwrite_policy, peer_registry_merge_semantics
- **REF-604 — `ensure_peer_entry_updated()` lost unknown peer-entry fields:** jq merge switched from `+` to `*` so nested peer fields (including `.self`) are preserved additively during peer updates.
  Docs impact: peer_registry_merge_semantics
- **REF-605 — legacy identity-secret export could leak over non-TTY stdout:** `legacy_export_runtime_secret()` now refuses to print the runtime identity secret when stdout is not a TTY and points operators at Layer A encrypted bootstrap instead.
  Docs impact: identity_secret_handling
- **REF-901 — setup could silently overwrite gateway `hooks.token`:** `scripts/antenna-setup.sh` now preserves an existing gateway `hooks.token` and only writes from Antenna's token file when the gateway value is absent or already matches.
  Docs impact: gateway_hooks_token_setup
- **REF-903 — setup reruns silently stripped operator `tools.exec` policy from the antenna agent:** the existing-agent repair path in `scripts/antenna-setup.sh` no longer does `del(.exec)`, so expert `tools.exec` overrides survive reruns. Setup still forces `sandbox.mode = "off"` and seeds the default deny list only when `tools.deny` is absent.
  Docs impact: setup_agent_update_behavior
- **REF-1206c — pair wizard no longer falsely implies bootstrap email delivery succeeded.** `scripts/antenna-pair.sh` now checks the real exit status from `antenna peers exchange initiate ... --send-email`, treats non-zero send attempts as failures, tells the operator the bundle was not sent, and falls back to explicit manual-delivery acknowledgement instead of fake-success wording.
  Docs impact: pair_wizard_email_delivery_behavior
- **REF-1501 — poll-loop couldn't fast-fail on auth/peer/rate-limit REJECTED:** `scripts/antenna-relay.sh` now tags all post-body REJECTED log lines with `nonce:$NONCE`. Combined with REF-1502, `antenna test <model>` now exits on the first nonce-scoped REJECTED instead of waiting for `--timeout`.
  Docs impact: model_test_behavior
- **REF-1502 — `TEST_NONCE` generated but not used for log correlation:** `scripts/antenna-model-test.sh` now polls for nonce-scoped PASS and nonce-scoped REJECTED instead of session-only matching, so concurrent runs can't cross-poison each other's results.
  Docs impact: model_test_behavior
- **REF-1504 — model-test swap bypassed gateway sync:** `scripts/antenna-model-test.sh` now swaps and restores `relay_agent_model` through `antenna config set ... --no-restart` (which also updates the antenna agent's `.model` in `openclaw.json`). Gateway is bounced exactly once after the initial swap and once in the cleanup trap, instead of per-run.
  Docs impact: model_test_behavior

### Added
- **`--no-restart` flag on `antenna config set` and `antenna model set`** for rapid-batch callers that want to write gateway config now and restart the gateway once at the end. Internal helper `_sync_relay_model_to_gateway` split into `_write_relay_model_to_gateway_config` (no restart) and `_restart_gateway`.
  Docs impact: model_test_behavior

### Changed
- **Test-suite provider request compatibility and fixture freshness refresh.** `scripts/antenna-test-suite.sh` now sends OpenAI-family requests with `max_completion_tokens`, Anthropic requests with `max_tokens`, and uses a fresh current UTC timestamp in Tier A.15 so the REF-500 regression once again exercises session-target rejection instead of tripping freshness validation first. Fresh validation evidence now includes clean full-suite runs for `openai/gpt-5.4-nano`, `openai/gpt-5.4-mini-2026-03-17`, `anthropic/claude-sonnet-4-5`, and `google/gemini-2.5-pro`.
  Docs impact: test_suite_behavior, relay_model_recommendation
- **Recommended relay model updated to `openai/gpt-5.4-nano`.** Operator-facing docs and config examples now present `openai/gpt-5.4-nano` as the recommended relay model on speed/fit grounds.
  Docs impact: relay_model_recommendation, version_number

### Docs
- README version/status refreshed for the `v1.3.0` release, SKILL metadata includes canonical repository/homepage URLs for provenance, and operator-facing docs/config examples now present `openai/gpt-5.4-nano` as the recommended relay model.
  Docs impact: version_number, relay_model_recommendation

## [1.2.22] — 2026-04-20

### Note
- Historical/prepared release waypoint retained for continuity. Its substantive fixes were rolled into the `1.3.0` release narrative above.

## [1.2.21] — 2026-04-18

### Fixed
- **Session resolution: sender no longer injects its own default session into outbound envelopes.** When `--session` is omitted, `target_session` is omitted from the envelope entirely; the recipient resolves from their own `default_target_session` config. Sender no longer needs to know the recipient's internal session layout. (Issue #17)
  Docs impact: session_resolution, version_number

---

For all releases prior to `1.2.21`, see [`references/CHANGELOG-HISTORY.md`](references/CHANGELOG-HISTORY.md) or the [GitHub releases page](https://github.com/cshirley001/openclaw-skill-antenna/releases).
