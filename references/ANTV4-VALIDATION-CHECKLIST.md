# ANTV4 Validation and Testing Checklist

Date: 2026-04-17
Purpose: repeatable validation regimen for Antenna changes before release and production promotion.

## How to use this

Use a **tiered regimen**, not a single all-or-nothing ritual.

Recommendation:
- Run a **Change Gate** after every significant code or runtime-behavior change.
- Run an **Expanded Regression Gate** after a cluster of related tickets or before cutting a release candidate.
- Run the **Full Release / Production Gate** before tagging, publishing, or promoting to production.
- Run a **Post-Deploy Verification Gate** immediately after production rollout.

This is better than pure case-by-case judgment alone.
Case-by-case still matters, but the baseline should be fixed enough that important checks do not get skipped when we are tired or feeling clever.

---

# 1. Change Gate, run after each significant change

Run this after any change that affects:
- relay behavior
- peer/config schema
- queue or rate-limit state
- setup / doctor / status logic
- model sync / gateway config mutation
- pairing / exchange flow
- security / auth / allowlists

Examples:
- **Yes, run after Ticket A** (normalize peer registry and remove stale live debris)
- **Yes, run after relay temp-file hardening**
- **Yes, run after inbox locking changes**
- Usually **no** for pure copy edits with no behavioral effect, though docs should still be sanity-checked before release

## Checklist

### A. Workspace and artifact hygiene
- [ ] Review `git diff --stat` and confirm only intended files changed
- [ ] Confirm no unintended secrets, runtime files, exports, or test artifacts were introduced
- [ ] Confirm any migration/update script is included if data shape changed

### B. Syntax and script sanity
- [ ] Run key scripts with `--help` or equivalent where applicable
- [ ] Verify edited shell scripts execute without immediate parse/runtime failure
- [ ] If helper libraries were touched, verify all dependents still start cleanly

### C. Impacted-path validation
- [ ] Identify affected surface area: relay, send, inbox, setup, exchange, doctor, status, docs, config migration
- [ ] Run the minimal targeted checks for that surface
- [ ] Record what was intentionally not re-tested yet

### D. Health commands
- [ ] Run `antenna status`
- [ ] Run `antenna doctor --fix-hints`
- [ ] Confirm no new unexpected failures or warnings were introduced

### E. Targeted smoke tests
- [ ] Run at least one smoke test directly related to the changed area
- [ ] If config/registry changed, confirm status/doctor output reflects the new truth
- [ ] If relay logic changed, confirm one local deterministic relay path still succeeds or rejects as intended
- [ ] If queue/rate-limit logic changed, test the exact affected state mutation path

### F. Regression note
- [ ] Add a short note to working notes / changelog / review log: what changed, what was tested, what remains

---

# 2. Expanded Regression Gate, run after a meaningful ticket batch or before RC

Run this when:
- 2 or more related tickets are complete
- behavior across multiple scripts changed
- release candidate is being prepared
- setup/runtime schema has changed

## Checklist

### A. Change aggregation review
- [ ] Re-read open tickets and verify the implemented set matches intent
- [ ] Confirm no ticket created a contradiction in docs or config defaults
- [ ] Confirm migration story is clear for existing installs

### B. Deterministic relay validation
- [ ] Valid envelope accepted and formatted correctly
- [ ] Missing envelope markers rejected correctly
- [ ] Unknown peer rejected correctly
- [ ] Missing auth header rejected when peer secret is configured
- [ ] Invalid auth secret rejected with actionable diagnostic
- [ ] Oversize message rejected correctly
- [ ] Disallowed target session rejected correctly
- [ ] Full session key requirement still enforced

### C. Queue and state validation
- [ ] Inbox queue add works
- [ ] Approve / deny works
- [ ] Drain emits correct JSON delivery instructions
- [ ] Clear removes processed items only
- [ ] Rate-limit state updates still work correctly
- [ ] If locking was changed, concurrent mutation behavior was exercised deliberately

### D. CLI / operational validation
- [ ] `antenna status` output is accurate
- [ ] `antenna doctor --fix-hints` output is accurate
- [ ] `antenna sessions list/add/remove` behaves correctly
- [ ] `antenna config show/set` behaves correctly
- [ ] `antenna model show/set` behaves correctly, including gateway sync if expected

### E. Peer registry and config validation
- [ ] `antenna-peers.json` shape is valid and normalized
- [ ] `antenna-config.json` shape is valid and normalized
- [ ] No stale legacy nested registry formats remain
- [ ] No stale bare session names remain where full keys are now required

### F. End-to-end smoke
- [ ] One self-loop / local loopback message succeeds
- [ ] One peer send dry-run looks correct
- [ ] One real remote send succeeds if safe and available
- [ ] Log output is sane and not misleading

### G. Docs drift check
- [ ] README version and behavior summary match current reality
- [ ] SKILL metadata and body match current reality
- [ ] CHANGELOG reflects the actual release step
- [ ] Historical FSD/reference docs are clearly marked if they are no longer authoritative

---

# 3. Full Release / Production Promotion Gate

Run this before:
- tagging a version
- publishing to ClawHub / GitHub release surface
- promoting from test/staging to production runtime

## Checklist

### A. Release readiness
- [ ] Version number is updated consistently across release surfaces
- [ ] Changelog entry is complete and accurate
- [ ] Release notes distinguish shipped behavior from future design ideas
- [ ] Rollback plan is written down

### B. Clean install / upgrade path
- [ ] Fresh install path works on a clean environment
- [ ] Upgrade path from previous known-good version works
- [ ] Existing runtime files are preserved or migrated correctly
- [ ] No stale setup assumptions remain in scripts or docs

### C. Full command sanity
- [ ] `antenna setup`
- [ ] `antenna pair`
- [ ] `antenna send` / `antenna msg`
- [ ] `antenna peers list/add/remove/test`
- [ ] `antenna peers exchange ...`
- [ ] `antenna inbox ...`
- [ ] `antenna sessions ...`
- [ ] `antenna doctor`
- [ ] `antenna test`
- [ ] `antenna test-suite`
- [ ] `antenna uninstall` at least sanity-reviewed and, if safe, exercised in test env

### D. Security and safety review
- [ ] No secrets are newly tracked or exposed
- [ ] Token and secret file permissions are correct
- [ ] Hook settings remain correct and no broader than intended
- [ ] Agent registration remains least-privilege for current design
- [ ] Any legacy fallback still present is clearly marked and intentionally retained
- [ ] Log messages do not leak sensitive values

### E. Cross-host integration
- [ ] Known peer registry works for at least one real peer
- [ ] Session delivery reaches visible target session, not just hook mailbox
- [ ] Failures are actionable when peer secret, token, or allowlist is wrong
- [ ] Control/UI behavior matches operational reality

### F. Production-specific backup and promotion readiness
- [ ] Backup gateway config before rollout
- [ ] Backup mutable Antenna runtime state before rollout
- [ ] Confirm production endpoint / DNS / tunnel / TLS path is correct
- [ ] Confirm emergency rollback command sequence is ready

---

# 4. Post-Deploy Verification Gate

Run immediately after production rollout.

## Checklist
- [ ] `antenna status` looks sane in production
- [ ] `antenna doctor --fix-hints` has no new critical failures
- [ ] One real inbound or loopback message succeeds
- [ ] One expected rejection path still rejects cleanly
- [ ] No unexpected auth failures appear in logs
- [ ] No unexpected queue buildup appears
- [ ] No unexpected rate-limit behavior appears
- [ ] Production site/surface check passes if user-facing web/docs were updated
- [ ] Rollback remains possible and unblocked

---

# 5. Test matrix by change type

Use this to decide what must run after a specific ticket.

## A. Registry / config normalization changes
Examples:
- Ticket A, peer registry cleanup
- config schema normalization
- migration code

Run:
- [ ] Change Gate, full
- [ ] Expanded checks for peer/config validation
- [ ] `antenna status`
- [ ] `antenna doctor --fix-hints`
- [ ] session allowlist checks
- [ ] one send dry-run
- [ ] one real or loopback relay if registry semantics changed

Usually not required immediately:
- full multi-provider `test-suite` unless release candidate or send/relay semantics changed too

## B. Relay parser / delivery logic changes
Examples:
- header parsing
- auth logic
- formatting logic
- temp-file strategy

Run:
- [ ] Change Gate, full
- [ ] Expanded deterministic relay validation
- [ ] self-loop / loopback test
- [ ] at least one expected rejection test
- [ ] log review for correctness

Strongly consider:
- [ ] full Expanded Regression Gate if more than one relay behavior changed

## C. Queue / rate-limit / locking changes
Examples:
- inbox locking
- queue ref generation
- rate-limit mutation

Run:
- [ ] Change Gate, full
- [ ] queue lifecycle checks
- [ ] rate-limit checks
- [ ] deliberate repeat / concurrency exercise
- [ ] log review

## D. Setup / pair / exchange changes
Run:
- [ ] Change Gate, full
- [ ] fresh setup or targeted test environment pass
- [ ] doctor/status verification
- [ ] at least one pairing / exchange happy path if touched
- [ ] one migration/upgrade sanity check if existing installs are affected

## E. Docs-only changes
Run:
- [ ] confirm docs match code
- [ ] spot-check commands/examples
- [ ] full release gate later before production publish if docs are part of the release

---

# 6. Suggested default policy

## Default rule
For Antenna, do **not** wait until “all tickets are done” to validate.

Instead:
- run the **Change Gate after each significant ticket**
- run the **Expanded Regression Gate after each logical batch**
- run the **Full Release / Production Gate before promotion**

This gives us both:
- early fault isolation, and
- a proper final release gate

## Practical interpretation

### After Ticket A, yes, test
Because Ticket A changes live registry truth, it can break:
- status accuracy
- doctor accuracy
- peer selection/counting
- send path lookups
- migration assumptions

So after Ticket A, we should absolutely run:
- Change Gate
- peer/config validation subset
- status + doctor
- at least one send/loopback sanity check

### After several cleanup tickets, test again more broadly
Once we clear a small cluster, for example:
- Ticket A, registry normalization
- Ticket B, temp-file strategy
- Ticket C, locking

then run the Expanded Regression Gate.

### Before prod, always run the full gate
No exceptions for meaningful releases.

---

# 7. Minimum required evidence before production promotion

Do not promote unless you can point to all of the following:
- [ ] exact commit/version being promoted
- [ ] output from `antenna status`
- [ ] output from `antenna doctor --fix-hints`
- [ ] evidence of at least one successful end-to-end relay on the candidate build
- [ ] evidence of at least one correct rejection path on the candidate build
- [ ] note of what changed since the last production version
- [ ] rollback plan / backup location

---

# Bottom line

The right answer is **both**:
- a standard checklist baseline, so we stay disciplined
- case-by-case expansion based on what changed

For Antenna, the sweet spot is:
- **small gate after each meaningful ticket**
- **larger gate after each ticket cluster**
- **full gate before production**
