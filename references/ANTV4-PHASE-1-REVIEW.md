# ANTV4 Phase 1 Review

Date: 2026-04-17
Scope: review, map, and identify cleanup / optimization targets for the live Antenna skill on BETTYXIX.
Basis: local code, local runtime files, local gateway config, and spot-checks of live ClawReef production.

## Executive summary

Antenna is now a real working system, not a concept piece. The core relay path is coherent:

1. `antenna-send.sh` builds an `[ANTENNA_RELAY]` envelope and POSTs it to `/hooks/agent`
2. the receiver dispatches to the dedicated `antenna` agent
3. the agent writes the raw message to disk and execs `antenna-relay-file.sh`
4. `antenna-relay.sh` performs deterministic parsing, auth, rate limiting, allowlist checks, and message formatting
5. the agent calls `sessions_send` into the target local session

The codebase is functional, but Phase 1 review shows four main problem classes:

1. **Mutable runtime state is mixed into the source tree**
2. **Schema and drift controls are too weak**
3. **Concurrency hardening is incomplete**
4. **The docs and operational surfaces still disagree in several important places**

The most important immediate cleanup targets are:

- normalize and validate `antenna-peers.json`
- remove stale bare-session entries from config
- fix the shared relay temp-file path in the relay agent instructions
- add locking around inbox / rate-limit state mutations
- separate runtime artifacts from the skill source tree
- align README / SKILL / FSD / status output to current 1.2.19-era reality

---

## Live snapshot observed during review

### Repo / code
- Local skill path: `/home/corey/clawd/skills/antenna`
- Current commit: `132209f`
- `git describe`: `v1.2.17-2-g132209f`
- SKILL frontmatter version: `1.2.19`
- Working tree was clean before this Phase 1 artifact was written

### Local gateway reality
- `tools.sessions.visibility = "all"`
- `tools.agentToAgent.enabled = true`
- Antenna agent registered with:
  - `agentDir = /home/corey/clawd/skills/antenna/agent`
  - `workspace = /home/corey/clawd/skills/antenna/agent`
  - `sandbox.mode = "off"`
- Hooks are enabled and allow `antenna`

### Local Antenna runtime reality
- `relay_agent_model` in `antenna-config.json`: `openrouter/openai/gpt-5.2-codex`
- registered Antenna agent model in gateway config: `openai/gpt-5.4`
- `allowed_inbound_sessions` contains both full keys and one stale bare value: `main`
- last log entry during review showed a rejected self-message due to invalid peer secret sync, which is useful evidence that auth failures are now visible and specific

### Doctor / status findings
Observed with `antenna status` and `antenna doctor --fix-hints`:

- `nexus` has missing token and missing peer secret files
- `testpeer` is stale garbage data (`http://test`, token `/tmp/test`)
- `bruce` currently unreachable
- config file permissions are `664`, which status warns is too permissive
- remote peer count is inflated by a malformed nested `peers` object inside `antenna-peers.json`

---

## Codebase map

### Primary entrypoint

#### `bin/antenna.sh` (876 LOC)
Role: user-facing dispatcher and operational shell.

Responsibilities:
- setup / pair / uninstall dispatch
- send / msg dispatch
- peer CRUD and testing
- session allowlist management
- config and model mutation
- log / doctor / test / test-suite / status
- gateway model sync and restart on model changes

Observations:
- doing too much for one shell entrypoint
- contains state mutation, reporting, peer management, and gateway sync logic in one file
- still contains stale fallback assumptions in `status` (`main`, `antenna`)
- counts peers by `to_entries[]`, so malformed registry structure pollutes output

### Relay path

#### `agent/AGENTS.md`
Role: relay agent instructions.

Current behavior described:
- write inbound raw message to `/tmp/antenna-relay-msg.txt`
- exec `bash ../scripts/antenna-relay-file.sh /tmp/antenna-relay-msg.txt`
- if relay returns success, call `sessions_send`

Phase 1 finding:
- **shared fixed temp path is a real concurrency hazard**
- this now conflicts with the hardened direction elsewhere in the codebase

#### `scripts/antenna-relay-file.sh` (27 LOC)
Role: file-based wrapper around the deterministic relay.

Observations:
- current code simply feeds file contents to `antenna-relay.sh --stdin`
- comment still says “base64-encode it”, which is stale and misleading

#### `scripts/antenna-relay.sh` (454 LOC)
Role: deterministic relay processor.

Responsibilities:
- detect envelope markers
- parse headers/body
- sanitize header values for logging
- validate sender allowlist
- validate peer existence
- verify auth secret if configured
- enforce rate limits
- enforce max message length
- optionally queue to inbox
- enforce session allowlist
- format delivered message
- emit JSON result

Observations:
- this is the actual trust boundary and central logic surface
- message formatting logic is duplicated between queued and direct-relay branches
- rate-limit state mutation is atomic via temp file rename but **not lock-safe**
- allowlist check is exact-match only, which is correct for current policy
- header parsing is intentionally simple and deterministic, which is good

### Send / outbound path

#### `scripts/antenna-send.sh` (275 LOC)
Role: build outbound envelope and POST to remote `/hooks/agent`.

Responsibilities:
- validate peer and token
- load config defaults
- enforce outbound allowlist and message size
- load self identity secret
- construct envelope and POST payload
- handle HTTP response and structured output

Observations:
- clear and compact compared with setup/exchange
- good candidate to stay relatively standalone
- token reading is less normalized than some other paths, but not a major problem

### Inbox path

#### `scripts/antenna-inbox.sh` (406 LOC)
Role: local approval queue manager.

Responsibilities:
- queue file lifecycle
- list / count / show
- approve / deny
- drain approved messages as JSON delivery instructions
- clear processed items
- internal `queue-add`

Observations:
- queue semantics are sensible and intentionally avoid re-entering relay hooks
- all writes are atomic via temp file rename, but **not lock-safe**
- sequential ref generation via `next_ref()` is race-prone under concurrent writers
- queue item validation is lightweight and does not enforce schema versioning

### Setup / install / repair path

#### `scripts/antenna-setup.sh` (1041 LOC)
Role: installer, configurator, gateway registrar.

Responsibilities:
- interactive and noninteractive setup
- config generation
- self-peer generation
- secret generation
- `.gitignore` bootstrap
- gateway config backup
- automatic hooks / agent / visibility registration
- exec allowlist registration
- path symlink management

Observations:
- large and operationally important
- mixes pure config generation with host mutation and UX output
- still carries history from several previous setup strategies
- default config generation is mostly current, but downstream runtime files can drift later

#### `scripts/antenna-doctor.sh` (420 LOC)
Role: installation health check.

Observations:
- useful and practical
- catches missing secrets and connectivity issues
- does not strongly validate registry schema shape, so malformed peer registry can still partially pass

### Pairing / exchange path

#### `scripts/antenna-exchange.sh` (1083 LOC)
Role: Layer A encrypted bundle exchange and legacy fallback.

Responsibilities:
- key generation
- pubkey export/email
- encrypted bundle build/import/reply
- legacy secret export/import fallback
- peer entry updates
- allowlist updates

Observations:
- biggest non-test script besides setup
- feature-rich but high maintenance burden
- includes several temporary file flows and multiple modes in one file
- likely the ripest candidate for decomposition after relay hardening

#### `scripts/antenna-pair.sh` (342 LOC)
Role: interactive pairing wizard built on top of exchange/setup primitives.

Observation:
- mostly UX orchestration, not core protocol logic

### Tests

#### `scripts/antenna-test-suite.sh` (1423 LOC)
Role: three-tier validation harness.

Tiers:
- Tier A: deterministic script validation
- Tier B: model emits exec correctly
- Tier C: model emits `sessions_send` correctly

Observations:
- very useful, but large enough to merit modularization later
- still references some historical assumptions in docs around base64 and versioning

#### `scripts/antenna-model-test.sh` (266 LOC)
Role: self-loop end-to-end model validation.

### Small wrappers / support scripts
- `antenna-health.sh` (51 LOC)
- `antenna-peers.sh` (27 LOC)
- `antenna-relay-exec.sh` (36 LOC, now legacy)
- `antenna-uninstall.sh` (289 LOC)

Observations:
- `antenna-relay-exec.sh` is still present as legacy fallback, which is acceptable, but comments and docs around it need stricter framing

---

## Runtime data model map

### Source-tracked reference files
- `antenna-config.example.json`
- `antenna-peers.example.json`
- `SKILL.md`
- `README.md`
- `CHANGELOG.md`
- `references/*`

### Mutable runtime files currently stored inside the skill tree
- `antenna-config.json`
- `antenna-peers.json`
- `antenna-inbox.json`
- `antenna-ratelimit.json` (not present during review, but created at runtime)
- `antenna.log`
- `secrets/*`
- `test-results/*`
- `tmp/*`
- many exported bootstrap bundles `*.age.txt`

### Structural problem
Antenna currently treats the skill directory as both:
- the immutable shipped product, and
- the mutable live installation state directory

That design has worked for iteration, but it now creates avoidable risk:
- source and runtime clutter are mixed together
- review diffs are noisier
- backups and removals are harder to reason about
- local secrets and exports accumulate in the same tree as publishable code
- schema migration becomes trickier

---

## High-confidence cleanup targets

## P0, correctness / hardening

### 1. Replace the shared relay temp path
Evidence:
- `agent/AGENTS.md` still instructs the relay agent to write to `/tmp/antenna-relay-msg.txt`

Why it matters:
- concurrent inbound messages can collide
- stale content can be overwritten between write and exec
- this is the clearest remaining relay-path hardening gap

Target:
- move to unique per-run temp file generation under a controlled path
- either generate the path in-agent safely, or use a wrapper entrypoint that owns temp creation without requiring risky shell metasyntax in the agent command

### 2. Add file locking for inbox and rate-limit state
Evidence:
- `antenna-inbox.sh` uses read/modify/write with no locking
- `antenna-relay.sh` updates `antenna-ratelimit.json` with no locking

Why it matters:
- concurrent deliveries can race
- queue refs can duplicate
- rate-limit accounting can lose updates

Target:
- add advisory locking, likely `flock`, around stateful read/modify/write sections
- serialize `queue-add`, approve/deny, drain, and rate-limit mutation

### 3. Add schema validation and normalization for `antenna-peers.json`
Evidence:
- live `antenna-peers.json` contains a stale nested `peers` object alongside flat peer entries
- `status` counted this malformed object as a remote peer
- `doctor` and status loops iterate over all top-level keys without validating peer shape

Why it matters:
- operational surfaces become misleading
- stale migrations persist forever
- downstream scripts may mis-handle malformed entries

Target:
- define and enforce valid peer entry shape
- reject or auto-normalize nested legacy formats
- add explicit “registry normalize” or migration-on-read behavior

### 4. Remove stale bare session entries from live config and stale defaults from code
Evidence:
- live config still contains bare `main`
- `status` fallback still prints `main, antenna`
- older docs still show `default_target_session: "main"`

Why it matters:
- contradicts the current full-key-only rule
- weakens operator confidence in what is canonical

Target:
- migrate live config to full keys only
- remove stale fallback values from status/reporting
- ensure every user-facing surface consistently treats full session keys as canonical

## P1, maintainability

### 5. Extract shared shell library code
Evidence:
- repeated definitions of `info`, `ok`, `warn`, `err`, `log_entry`, path resolution, and config loading across many scripts
- heavy repeated `jq` lookup patterns

Why it matters:
- bugfixes must be repeated in many places
- behavior drifts between scripts
- review burden stays high

Target candidates:
- `scripts/lib/common.sh`
- `scripts/lib/log.sh`
- `scripts/lib/config.sh`
- `scripts/lib/paths.sh`
- `scripts/lib/registry.sh`

### 6. Centralize config defaults and schema
Evidence:
- defaults are embedded in multiple places: setup, status, relay, send, docs
- the same conceptual field has different fallback semantics across files

Why it matters:
- drift is already visible
- migrations become fragile

Target:
- establish one source of truth for default config values and schema validation

### 7. De-duplicate delivery-message formatting
Evidence:
- `antenna-relay.sh` formats almost the same delivery message twice: queued path and direct-relay path

Why it matters:
- future tweaks can diverge
- security notice and timestamp formatting should stay identical

Target:
- single formatting helper that returns the final delivery message

### 8. Split large operational scripts
Strong candidates:
- `antenna-setup.sh`
- `antenna-exchange.sh`
- `antenna-test-suite.sh`
- `bin/antenna.sh`

Reason:
- each mixes multiple concerns and has become hard to review safely in one pass

Suggested future split:
- gateway mutation helpers
- config generation helpers
- exchange bundle helpers
- CLI subcommand modules
- provider-specific test harness functions

## P2, operational hygiene / UX

### 9. Move mutable state out of the source tree
This is the biggest structural cleanup target after correctness items.

Suggested end state:
- keep source in the skill directory
- move mutable runtime state to a dedicated state root, for example:
  - `~/.local/state/antenna/` or
  - `~/.openclaw/skills/antenna/`

Would move:
- config
- peers
- inbox
- rate-limit
- logs
- secrets
- exports
- test results

Benefits:
- cleaner repo
- safer publishing / packaging
- easier backup / uninstall / migration semantics

### 10. Add runtime garbage collection / cleanup commands
Evidence:
- dozens of `.age.txt` bootstrap bundle exports are sitting at repo root
- stale test peer data remains live in the registry
- logs and test results accumulate indefinitely

Target:
- cleanup command for stale exports
- cleanup command for dead test peers
- optional log rotation / retention enforcement
- optional test-result retention policy

### 11. Improve status / doctor schema awareness
Evidence:
- `status` peer count was misleading because malformed registry structure was accepted
- `doctor` reports the consequences of bad data, but not the malformed shape itself

Target:
- report “registry malformed” explicitly
- distinguish real peers from legacy debris
- classify test/demo peers separately

---

## Documentation drift found during Phase 1

### Confirmed drift
- `README.md` still says **v1.2.7** and still describes the base64 relay era as the current version
- `SKILL.md` frontmatter says **1.2.19**, but the heading still says **v1.2.17**
- `SKILL.md` example config still shows `default_target_session: "main"`
- `references/ANTENNA-RELAY-FSD.md` is much older and still describes:
  - `default_target_session: "main"`
  - `allowed_inbound_sessions: ["main", "antenna"]`
  - segment matching
  - future ideas mixed with old current-state claims
- older docs in `docs/` still reference `commands.ownerDisplay = "raw"` as if required

### Implication
Public story, local skill instructions, and live code do not yet cleanly collapse into one truth surface.

### Cleanup target
Establish a doc hierarchy explicitly:
1. live code and runtime config
2. `SKILL.md` and README for current usage
3. CHANGELOG for historical sequence
4. FSD and older references as historical / design context only

---

## Specific live data issues discovered

### `antenna-peers.json` contains stale mixed-format data
Observed top-level keys include:
- valid peers: `bettyxix`, `bettyxx`, `nexus`, `testpeer`, `anttest`, `clawreef`, `bruce`
- invalid legacy-shaped entry: top-level key `peers` containing nested peer data

Impact:
- peer counts are wrong
- audits walk stale junk
- review surfaces are noisier than they should be

### stale / test-only peer records are still live
- `testpeer` points to `http://test` and token `/tmp/test`
- `nexus` references missing local token and secret files

Impact:
- doctor fails for reasons that may be operationally irrelevant but still clutter real health state

### model drift between config and gateway registration
- config model and registered agent model do not match

Impact:
- the runtime truth depends on which surface the operator checks
- testing and debugging become more confusing

---

## Optimization candidates

These are not urgent correctness fixes, but they will make the system easier to keep healthy.

### 1. Reduce repeated `jq` file reads
Current scripts repeatedly reopen config and peers files for small lookups.

Potential improvement:
- cache parsed values within a script invocation
- centralize common lookups in helpers

### 2. Structured logs
Current logs are human-readable and useful, but machine post-processing would improve with JSONL or a dual-format mode.

### 3. Explicit schema versioning
Add a schema version field to runtime config / peers files so migrations are explicit.

### 4. Static analysis in CI or local dev flow
`shellcheck` was not available in this environment during Phase 1 review.
A lint lane would help catch quoting / array / test-path issues earlier.

### 5. Test-surface modularization
The test suite is valuable enough that it should eventually be broken into provider adapters plus shared assertions.

---

## Recommended Phase 2 order

1. **Normalize runtime data**
   - clean `antenna-peers.json`
   - remove stale `main` session entry
   - reconcile relay model drift

2. **Close the concurrency gaps**
   - unique relay temp path
   - file locking for inbox and rate-limit state

3. **Establish schema helpers**
   - common config / peers validation
   - explicit migration path

4. **Refactor for maintainability**
   - shared shell helpers
   - split setup / exchange / dispatcher surfaces

5. **Doc truth pass**
   - README, SKILL, USER-GUIDE, FSD role clarification

6. **State-dir separation**
   - move mutable runtime files out of the source tree

---

## Proposed concrete cleanup tickets

### Ticket A
Normalize peer registry and remove legacy nested `peers` object.

### Ticket B
Fix relay temp-file strategy so the agent no longer uses a shared `/tmp/antenna-relay-msg.txt` path.

### Ticket C
Add `flock`-based serialization for inbox and rate-limit mutations.

### Ticket D
Create shared shell helper library for logging, path resolution, config reads, atomic JSON writes.

### Ticket E
Reconcile model/source-of-truth handling between `antenna-config.json`, gateway config, and `antenna model` / `antenna config set relay_agent_model`.

### Ticket F
Refresh status, doctor, README, and SKILL to current full-session-key and file-based relay reality.

### Ticket G
Design a proper runtime state directory and migration path out of the repo tree.

---

## Bottom line

Antenna is in the good kind of trouble now.

It is no longer failing because the concept is weak. It is now succeeding often enough that the remaining problems are mostly the mature ones:
- drift
- cleanup
- concurrency
- schema discipline
- source/runtime separation

That is exactly the right moment for antv4 Phase 2 to become a cleanup-and-hardening pass rather than another invention sprint.
