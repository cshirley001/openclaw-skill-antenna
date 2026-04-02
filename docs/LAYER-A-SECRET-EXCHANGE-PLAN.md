# Antenna Layer A — Script-Based Encrypted Secret Exchange Plan

**Date:** 2026-04-01  
**Status:** planning draft for review  
**Scope:** Layer A only (script-based encrypted exchange)  
**Related:** `SECRET-EXCHANGE-OPTIONS.md`, `ANTENNA-RELAY-FSD.md`

---

## 1. Goal

Design the first practical replacement for cleartext out-of-band exchange of Antenna bootstrap material.

The Layer A goal is:

> Let one operator package the minimum peer bootstrap bundle, encrypt it for the other operator, and deliver it over an ordinary channel without exposing hooks tokens or peer identity secrets in cleartext.

This must work **without** requiring new hosted infrastructure.

---

## 2. Non-goals

Layer A is **not** trying to solve:
- public peer discovery
- reputation/trust registry
- direct in-band handshake over Antenna transport
- perfect enterprise PKI
- automatic mutual peering without operator review

Those belong to later layers or separate workstreams.

---

## 3. Proposed crypto choice

## Use `age`

Layer A should use **`age`** public-key encryption as the default format.

### Why `age`
- simple mental model
- low ceremony
- easy CLI usage
- avoids GPG ecosystem pain
- suitable for encrypting small bootstrap payloads
- easy to wrap from shell scripts

### Assumption
Each operator will either:
- already have an `age` keypair, or
- generate one during `antenna setup` / `antenna peers exchange`

---

## 4. Data to exchange

The encrypted payload should contain only what is required to establish peering.

### Candidate payload fields
- `schema_version`
- `generated_at`
- `from_peer_id`
- `from_display_name`
- `from_endpoint_url`
- `from_agent_id` (usually `antenna`)
- `from_hooks_token`
- `from_identity_secret`
- `expected_peer_id` (optional but recommended)
- `notes` (optional operator note)

### Deliberately excluded
- unnecessary local file paths
- unrelated gateway config
- historical logs
- model configuration unrelated to peering

### File representation
Use a small JSON document as the plaintext payload before encryption.

Reason:
- easy to validate with `jq`
- easy to version
- easy to import/export across scripts

---

## 5. Operator flows

## Flow A — Initiate and send

Command sketch:

```bash
antenna peers exchange initiate <peer-id>
```

### Expected guided steps
1. Resolve local self peer and ensure required local values exist.
2. Prompt for peer email/contact path.
3. Prompt for peer public key, or load it from file.
4. Prompt for peer endpoint URL if not already known.
5. Prompt for optional display name / note.
6. Build plaintext JSON payload.
7. Encrypt with `age`.
8. Offer delivery options:
   - send via configured mail tool
   - write encrypted file
   - print armored/pasteable block
9. Save a local audit artifact noting what was sent and when (without recording the sensitive plaintext).

## Flow B — Import received bundle

Command sketch:

```bash
antenna peers exchange import <file-or-stdin>
```

### Expected guided steps
1. Read encrypted payload from file or stdin.
2. Decrypt using local `age` identity.
3. Validate JSON schema.
4. Show a review summary:
   - peer ID
   - display name
   - endpoint URL
   - agent ID
   - timestamp
5. Ask for confirmation before writing anything.
6. Write/update:
   - peer entry in `antenna-peers.json`
   - hooks token file for that peer
   - peer secret file for that peer
7. Ensure allowlists include the peer if appropriate.
8. Offer to generate a reply bundle immediately.

## Flow C — Reply / reciprocal exchange

Command sketch:

```bash
antenna peers exchange reply <peer-id>
```

or offered automatically after import.

This should:
- generate missing local identity material if needed
- package the reciprocal bootstrap payload
- encrypt it to the newly imported peer public key (if available)
- offer the same send/file/paste options

---

## 6. Delivery options

Layer A should support multiple delivery modes because the encrypted payload is portable.

### Option 1 — Local email send
Use a configured sender (e.g. Himalaya account) when available.

**Pros:** most convenient  
**Cons:** depends on mail configuration being present and working

### Option 2 — Write encrypted file
Write `.age` output locally and let the operator send it however they prefer.

**Pros:** universal and simple  
**Cons:** one extra manual step

### Option 3 — Pasteable armored block
Emit a copy-paste safe text block.

**Pros:** good for Signal/DM/manual channels  
**Cons:** awkward for larger payloads unless carefully formatted

### Recommendation
Support all three, but make **file output + optional send** the default implementation sequence.

---

## 7. Key management expectations

## Local keys
Antenna should have a notion of a local encryption identity for exchange operations.

### Suggested files
- local `age` private key: stored in `secrets/` with `chmod 600`
- local `age` public key: exportable and safe to share

### Suggested command additions
```bash
antenna peers exchange keygen
antenna peers exchange pubkey
```

These would:
- create a local exchange keypair if missing
- print the public key for sharing or registry publication

---

## 8. Validation and safety checks

Before sending:
- self peer exists
- self endpoint URL exists
- hooks token file exists and is non-empty
- self identity secret exists or can be generated
- peer public key parses as valid `age` recipient

Before importing:
- decrypt succeeds
- payload schema version is recognized
- required fields exist
- endpoint URL looks sane
- peer ID is valid/non-empty
- operator confirms before write

After import:
- written secret files use restrictive permissions
- peer entry appears in config
- optional peer test command is offered

---

## 9. Suggested plaintext schema (draft)

```json
{
  "schema_version": 1,
  "generated_at": "2026-04-01T22:00:00Z",
  "from_peer_id": "bettyxix",
  "from_display_name": "Betty XIX",
  "from_endpoint_url": "https://bettyxix.tailde275c.ts.net",
  "from_agent_id": "antenna",
  "from_hooks_token": "<token>",
  "from_identity_secret": "<hex-secret>",
  "expected_peer_id": "nexus",
  "notes": "Antenna pilot bootstrap bundle"
}
```

This schema is intentionally narrow and can evolve later.

---

## 10. CLI surface (draft)

### New subcommands
```bash
antenna peers exchange keygen
antenna peers exchange pubkey
antenna peers exchange initiate <peer-id>
antenna peers exchange import [file]
antenna peers exchange reply <peer-id>
```

### Optional flags
```bash
--email <addr>
--pubkey <age-pubkey>
--pubkey-file <path>
--endpoint <url>
--output <path>
--send-email
--print
--yes
```

### UX principle
Guided interactive flow first, non-interactive flags second.

---

## 11. Implementation sketch

### Likely files/scripts
- `scripts/antenna-exchange-keygen.sh`
- `scripts/antenna-exchange-initiate.sh`
- `scripts/antenna-exchange-import.sh`
- `scripts/antenna-exchange-reply.sh`
- updates to `bin/antenna`

### Shared helpers to add
- resolve self peer
- load local hooks token
- load/generate identity secret
- validate `age` dependency
- validate payload schema
- write secrets with safe permissions
- optional mail-send wrapper

### Dependency question
Need to decide whether `age` becomes:
- a documented prerequisite, or
- something Antenna can bootstrap/check for and guide-install

My recommendation: treat `age` as a required dependency for encrypted exchange features and fail with clear instructions if missing.

---

## 12. Threat model improvement over current fallback

### Current bad path
- cleartext hooks token and secret may be emailed or pasted directly
- channel compromise exposes reusable credentials immediately

### Layer A improvement
- channel compromise reveals only encrypted ciphertext
- only possession of recipient private key exposes the bootstrap payload
- operator still confirms import before local config is modified

### Residual risks
- recipient private key compromise
- sending to wrong recipient public key
- operator social engineering / mistaken peer identity
- plaintext lingering in shell history or temp files if implementation is sloppy

---

## 13. Open design questions

1. Should hooks token and identity secret travel in the same bundle, or in separate bundles?
2. Should import auto-create allowlist entries, or ask interactively?
3. Should reply flow require the recipient to provide their public key during import if it was not already known?
4. Should we support ASCII armor / paste-friendly wrapping by default?
5. Should email sending be first-class or just a convenience wrapper around encrypted files?
6. Should Layer A use a single exchange keypair for the host, or per-peer exchange keys?

---

## 14. Recommended first implementation slice

### Phase 1
- add `keygen` + `pubkey`
- add `initiate` producing encrypted file output
- add `import` from file/stdin
- no mail integration yet
- no registry integration yet

### Phase 2
- add optional email send wrapper
- add guided reply generation
- add better confirmation/review UX

### Phase 3
- integrate with future ClawReef registry for public-key lookup

This staged approach gets rid of cleartext exchange quickly without waiting on website or registry work.

---

## 15. Review summary

### What this plan tries to optimize for
- immediate practical security improvement
- low infrastructure burden
- understandable operator workflow
- future compatibility with a registry model

### What I would review closely with Corey before implementation
- whether `age` is the right default with minimal operator friction
- whether email send should be built in at phase 1 or deferred
- how much config import should be automatic versus confirm-first
- whether the payload should include both hooks token and identity secret together
