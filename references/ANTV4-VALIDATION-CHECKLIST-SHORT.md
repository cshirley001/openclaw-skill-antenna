# ANTV4 Validation Checklist — Short Operator Version

Date: 2026-04-17
Use: rapid pre-release and pre-prod validation for Antenna.

## When to run what

### After each significant ticket
Run the **Change Gate**.

Examples:
- relay behavior
- peer/config schema
- queue / rate-limit logic
- setup / doctor / status
- auth / allowlists / gateway sync

### After a batch of related tickets or before RC
Run the **Regression Gate**.

### Before any production promotion
Run the **Release Gate**.

### Immediately after rollout
Run the **Post-Deploy Gate**.

Rule of thumb:
- **Do not wait until all tickets are done.**
- **Yes, test after Ticket A.**

---

# 1) Change Gate

- [ ] Review `git diff --stat`
- [ ] Confirm no unintended secrets/runtime junk were introduced
- [ ] Run edited scripts / affected commands for basic parse sanity
- [ ] Run `antenna status`
- [ ] Run `antenna doctor --fix-hints`
- [ ] Run one targeted smoke test for the changed surface
- [ ] Record what changed, what was tested, what was not

## If Ticket A / registry-config cleanup
Also run:
- [ ] peer/config shape check
- [ ] session allowlist sanity check
- [ ] one send dry-run
- [ ] one loopback or real relay sanity check if semantics changed

---

# 2) Regression Gate

- [ ] Valid relay accepted
- [ ] malformed envelope rejected
- [ ] unknown peer rejected
- [ ] missing/invalid auth rejected correctly
- [ ] disallowed target session rejected
- [ ] full session key rule still enforced
- [ ] inbox queue add / approve / deny / drain / clear works
- [ ] rate-limit behavior still works
- [ ] `antenna status` output is accurate
- [ ] `antenna doctor --fix-hints` output is accurate
- [ ] `antenna sessions ...` behaves correctly
- [ ] `antenna config ...` behaves correctly
- [ ] `antenna model ...` behaves correctly if touched
- [ ] `antenna-peers.json` and `antenna-config.json` are normalized
- [ ] one self-loop / loopback passes
- [ ] one peer send dry-run looks correct
- [ ] docs still match current behavior closely enough

---

# 3) Release Gate

- [ ] version/changelog updated consistently
- [ ] rollback plan written down
- [ ] fresh install path sane
- [ ] upgrade path sane
- [ ] setup / pair / send / peers / inbox / sessions / doctor / test surfaces reviewed or exercised as appropriate
- [ ] no secrets exposed
- [ ] token/secret permissions correct
- [ ] least-privilege posture still intact
- [ ] one real cross-host relay succeeds on candidate build
- [ ] one expected rejection path succeeds on candidate build
- [ ] backup gateway config and mutable runtime state before prod

---

# 4) Post-Deploy Gate

- [ ] `antenna status` sane in prod
- [ ] `antenna doctor --fix-hints` has no new critical failures
- [ ] one real inbound or loopback message succeeds
- [ ] one expected rejection path still rejects cleanly
- [ ] logs show no surprising auth / queue / rate-limit behavior
- [ ] rollback still available

---

# Minimum evidence before production

Do not promote without:
- [ ] exact commit/version
- [ ] `antenna status` output
- [ ] `antenna doctor --fix-hints` output
- [ ] one successful end-to-end relay
- [ ] one correct rejection-path test
- [ ] summary of changes since last prod
- [ ] rollback/backup note
