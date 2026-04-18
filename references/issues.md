
## Issue #8: Setup should offer to generate a hooks token when autodiscovery fails

**Found:** 2026-04-03 (meat test, LOBSTERY fresh install after uninstall)
**Severity:** UX / onboarding friction
**Status:** Open

### Problem
When `antenna setup` can't auto-detect a hooks token from `gateway.hooks.token` in `openclaw.json` (e.g. after a clean uninstall, or on a brand-new host), it falls through to a manual "Token file path:" prompt with no guidance on how to create one.

A new user at this point has no idea:
1. What the token is
2. How to generate one
3. Where to put the file
4. What permissions it needs

### Expected behavior
If autodiscovery fails, setup should offer: **"No hooks token found. Generate a new one?"** → creates `secrets/hooks_token_<host-id>` with `openssl rand -hex 24`, sets `chmod 600`, and pre-fills the path.

### Workaround
Manually generate before running setup:
```bash
mkdir -p ~/clawd/skills/antenna/secrets
openssl rand -hex 24 > ~/clawd/skills/antenna/secrets/hooks_token_<host-id>
chmod 600 ~/clawd/skills/antenna/secrets/hooks_token_<host-id>
```
Then enter the path at the prompt.

### Fix scope
`scripts/antenna-setup.sh`, around line 213 — after the "Could not auto-detect" warning, add a `prompt_yn` offering to generate.

## Issue #9: Setup doesn't add relay_agent_id to hooks.allowedAgentIds

**Found:** 2026-04-03 (meat test, LOBSTERY fresh install)
**Severity:** Bug — blocks inbound message delivery
**Status:** Open

### Problem
`antenna setup` gateway registration (line ~410-413 of `antenna-setup.sh`) adds the **local agent ID** (`lobster`) and `main` to `hooks.allowedAgentIds`, but does not add the **relay agent ID** (`antenna`).

Since inbound Antenna messages are POSTed to `/hooks/agent` with the relay agent ID as the target, the gateway rejects them — effectively breaking all inbound messaging.

### Evidence
After fresh setup on LOBSTERY:
```json
"allowedAgentIds": ["lobster", "main"]  // missing "antenna"
```
`antenna doctor` correctly flags: `✗ hooks.allowedAgentIds does not include "antenna"`

### Expected behavior
Setup should read `relay_agent_id` from the config it just created and add it to `allowedAgentIds`.

### Fix scope
`scripts/antenna-setup.sh`, gateway registration jq block — the `$aid` variable should include the relay agent ID, not just the local agent.

### Workaround
```bash
jq '.hooks.allowedAgentIds += ["antenna"] | .hooks.allowedAgentIds |= unique' ~/.openclaw/openclaw.json > /tmp/oc-fix.json && mv /tmp/oc-fix.json ~/.openclaw/openclaw.json
openclaw gateway restart
```

## Issue #10: Onboarding step order puts manual `peers add` before `peers exchange`

**Found:** 2026-04-03 (meat test, LOBSTERY fresh install)
**Severity:** UX / documentation — confuses the primary onboarding path
**Status:** Open

### Problem
Setup's post-install instructions list:
```
4. Add a remote peer:  antenna peers add <peer-id> --url <url> --token-file <path>
5. Exchange identity secrets:  antenna peers exchange <peer-id>
```

This implies the user must already have the remote peer's hooks token and URL before adding them — but the whole point of `peers exchange` is to securely transmit that information. The exchange bundle contains `from_endpoint_url`, `from_hooks_token`, and peer secret.

As written, a new user hits step 4, doesn't have the remote token, and is stuck.

### Expected flow
The primary happy path should be:
1. Both sides run `setup`
2. Exchange age public keys (out-of-band: paste, email, whatever)
3. Side A: `peers exchange initiate <peer-id> --recipient-pubkey <age-pub>`
4. Side B: `peers exchange import <bundle>` → auto-creates peer entry
5. Side B: `peers exchange reply <peer-id>` → reciprocal bundle
6. Side A: `peers exchange import <bundle>`
7. Both: `peers test <peer-id>`

`peers add --url --token-file` should be documented as the **manual/legacy fallback**, not the primary path.

### Fix scope
- `scripts/antenna-setup.sh` post-install instructions
- `README.md` quickstart section
- Possibly: `peers exchange import` should auto-create the peer entry if it doesn't exist yet (needs verification)

## Issue #11: Exchange import may write token to stale/pre-existing path instead of peer-specific file

**Found:** 2026-04-03 (meat test, LOBSTERX importing LOBSTERY's reply bundle)
**Severity:** Bug — causes AUTH FAILED on outbound messages
**Status:** Open

### Problem
When importing a reply bundle on a host that already had a prior Antenna installation, the import wrote the peer's hooks token to `/home/corey/clawd/secrets/hooks_token` — a stale path from the old config — instead of creating a peer-specific `secrets/hooks_token_<peer-id>` file.

The result: `peers test` returned `AUTH FAILED: Token rejected (HTTP 401)` because the file contained the wrong token.

### Root cause (likely)
The import logic may be reusing an existing `token_file` reference from `antenna-peers.json` if the peer entry already existed (from previous install), rather than always generating a fresh peer-specific path.

### Expected behavior
Import should always write tokens to `secrets/hooks_token_<peer-id>` and update the peer record to point there, regardless of any pre-existing paths.

### Workaround
Manually create the correct token file and update `antenna-peers.json`:
```bash
echo -n '<correct-token>' > secrets/hooks_token_<peer-id>
chmod 600 secrets/hooks_token_<peer-id>
# Update token_file in antenna-peers.json to "secrets/hooks_token_<peer-id>"
```

### Fix scope
`scripts/antenna-exchange.sh`, import logic — force peer-specific token path on every import.

## Issue #12: Self peer token_file uses arbitrary absolute path instead of canonical relative path

**Found:** 2026-04-03 (round 2 meat test — LOBSTERX stale self token caused wrong token in exchange bundle)
**Severity:** Bug — exchange bundles package wrong hooks token, causing AUTH FAILED on import
**Status:** Fixed in v1.0.13

### Problem
Setup stored whatever path the user provided (or autodiscovered) as the self peer's `token_file` in
`antenna-peers.json`. This could be an arbitrary absolute path like `/home/corey/clawd/secrets/hooks_token`.

When the gateway token later changed (e.g. after uninstall/reinstall), the file at that absolute path
went stale. `build_plaintext_bundle()` reads `self.token_file` to package into exchange bundles,
so the wrong token got sent to peers → AUTH FAILED.

### Fix
- Setup now normalizes the self peer's token_file to the canonical relative path
  `secrets/hooks_token_<host-id>` in all cases (interactive and non-interactive).
- If the user provides a different path, the token is copied to the canonical location.
- Non-interactive mode now supports `--token-file auto` for autodiscovery/auto-generation.

## Issue #12b: Non-interactive setup doesn't autodiscover or generate tokens

**Found:** 2026-04-03 (round 2 — `--token-file auto` was passed but setup accepted it as a literal path)
**Severity:** UX bug
**Status:** Fixed in v1.0.13

### Fix
Non-interactive mode now handles `--token-file auto` and missing token files by:
1. Trying autodiscovery from gateway config
2. Falling back to `openssl rand -hex 24` generation

## Issue #13: Email transport garbles base64 bundle → decrypt fails on import

**Found:** 2026-04-03 (meat test round 4 — email reply from LOBSTERX to Corey, copy-pasted into file)
**Severity:** UX — email inline body corrupts bundle during copy-paste
**Status:** Fixed in v1.0.14

### Problem
When a bootstrap bundle is sent as inline email body text and the recipient copy-pastes it into a file,
email client rendering (line wrapping, encoding changes, whitespace) can corrupt the base64 encoding.
`age -d` then fails with "no identity matched any of the recipients" — indistinguishable from a key mismatch.

### Fix
`send_bundle_email()` now sends the bundle as a **file attachment** (via himalaya MML multipart)
instead of inline body text. The email body contains only import instructions and a note to use the
attached file directly. File attachments are binary-safe and immune to email rendering corruption.

## Issue #14: Non-interactive setup skips gateway auto-registration

**Found:** 2026-04-03 (meat test rounds 2–3)
**Severity:** UX gap
**Status:** Fixed in v1.0.14

### Fix
Non-interactive mode now auto-registers the Antenna agent and hooks in gateway config
whenever the gateway config file is found, without prompting.

## Issue #16: age not listed as dependency in README

**Found:** 2026-04-03 (meat test — age missing on LOBSTERY)
**Severity:** Documentation
**Status:** Fixed in v1.0.14

### Fix
Added Dependencies section to README listing jq, curl, openssl (required), age (required for
Layer A exchange), and himalaya (optional for email send).

## Issue #17: Bare send injects sender's default session into outbound envelope

**Found:** 2026-04-17 (session resolution architecture discussion)
**Severity:** Bug — causes rejection on recipient hosts with different session layouts
**Status:** Fixed (2026-04-17)

### Problem
`antenna msg bruce "test"` without `--session` would bake the **sender's** local `default_target_session` (e.g. `agent:betty:main`) into the outbound envelope's `target_session` header. On the recipient's host, this session key doesn't exist in their allowlist — Bruce expects `agent:bruce:main`, not `agent:betty:main`.

The sender shouldn't need to know the recipient's internal session layout.

### Root cause
`antenna-send.sh` always resolved a target session — first from explicit `--session`, then global `default_target_session`, then fallback `agent:<local_agent_id>:main` — and unconditionally included it in the envelope.

### Fix
Changed `antenna-send.sh` so that when no `--session` is explicitly provided, `target_session` is **omitted from the envelope entirely**. The recipient's `antenna-relay.sh` already handles a missing `target_session` by resolving from its own local `default_target_session` config.

- Envelope builder conditionally includes `target_session` header only when set
- Logs/output show `recipient-default` when session was omitted
- Briefly tried a per-peer `default_session` field in `antenna-peers.json`; reverted in favor of the cleaner omit approach

### Behavior after fix
- `antenna msg <peer> "msg"` → no `target_session` in envelope → recipient resolves from own config
- `antenna msg <peer> --session "agent:X:Y" "msg"` → explicit `target_session` in envelope → recipient uses it

### Remaining work
- [ ] Propagate fix to BETTYXX
- [ ] Update SKILL.md / README.md / USER-GUIDE.md to document the new behavior
- [ ] Add Tier A test for bare-send envelope shape (no `target_session` header present)
- [ ] Live end-to-end test with Bruce once reachable

### Decision reference
`DEC-2026-04-17-011` in `memory/2026-04-17.md`
