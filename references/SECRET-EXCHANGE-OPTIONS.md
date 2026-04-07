# Antenna Secret Exchange — Options & Direction

**Date:** 2026-04-01  
**Status:** planning note / companion doc  
**Related:** `ANTENNA-RELAY-FSD.md`

---

## Purpose

Capture the current proposed secret-exchange approaches for Antenna peer onboarding, based on the April 1 discussion. These notes are intentionally solution-oriented and are meant to guide implementation planning.

The immediate problem to solve is the **out-of-band exchange of peer bootstrap material** without falling back to emailing cleartext hooks tokens or peer identity secrets.

---

## Layer A — Script-based encrypted exchange (immediate practical solution)

### Summary
Build a scripted exchange flow as the first real solution:

```bash
antenna peers exchange initiate <peer-id>
```

### What it should do
1. Ask for the peer's contact path and crypto material:
   - peer email address (or another delivery channel label)
   - peer public key
2. Package the local side's bootstrap information:
   - peer ID
   - endpoint URL
   - hooks token
   - local identity / peer secret
3. Encrypt the package using the peer's public key.
4. Send the encrypted payload using an available mail/send path, or emit it for manual delivery.
5. Print import instructions for the recipient.

Recipient flow:

```bash
antenna peers exchange import <file-or-paste>
```

The import path should:
- decrypt
- validate
- write/update local peer config and secret files
- optionally generate and prepare the reply payload in one step

### Preferred crypto/tooling choice
Use **`age`** as the default encryption mechanism.

Why:
- simple public-key model
- modern, minimal tool
- avoids GPG keyring complexity
- produces an encrypted blob that can travel safely over many channels

### Delivery philosophy
The encrypted payload should be channel-agnostic. It should be safe to send over:
- email
- Signal
- copy/paste in a DM
- any other ordinary operator channel

The channel itself does **not** need to be trusted if the payload is correctly encrypted.

### Why this is the best immediate answer
- no external service dependency
- works with existing operator habits
- can be implemented now
- directly fixes the embarrassing cleartext-secret fallback path

---

## Layer B — ClawReef registry for discovery and public-key distribution (near-term, optional)

### Summary
Use **ClawReef.io** as a lightweight **network registry / phone book**, not as a secret vault.

### Registry role
A registry entry could publish only:
- peer ID
- public endpoint URL
- public encryption key (e.g. `age` public key)
- optional display name / profile metadata

### What the registry should NOT store
- hooks tokens
- peer identity secrets
- any other shared secret bootstrap material

### Why this is useful
The registry solves the “how do I find you and get your public key?” problem without taking custody of the sensitive materials.

It also makes peer onboarding easier for:
- people not already in a secure side-channel together
- pilots with multiple hosts or operators
- future public/open ecosystem use where discoverability matters

### Optionality
Registry use should remain **optional**.

Manual/direct peering should still be supported without any ClawReef registration. The registry is a convenience/discovery layer, not a hard dependency.

---

## Layer C — Direct handshake over existing Antenna transport (future / aspirational)

### Summary
Longer-term, use the Antenna transport itself to negotiate peer bootstrap material.

### Conceptual flow
1. Peer A sends a handshake-initiate message to Peer B's reachable endpoint.
2. Peer B receives it through the existing hook/relay path.
3. Peer B prompts for operator approval or uses a constrained trust workflow.
4. Peer B replies with encrypted bootstrap material.
5. Both sides complete mutual configuration without relying on a third-party channel.

### Why this is attractive
- elegant end-state
- self-contained inside the Antenna product
- reduces dependency on side channels once initial trust exists

### Why it is not first priority
It still has a **bootstrapping trust problem**. Some initial trust anchor is needed before a remote handshake should be accepted. That makes it a better future refinement than the first fix.

---

## Recommended priority

### Recommended sequence
1. **Layer A:** implement script-based encrypted exchange first
2. **Layer B:** add optional ClawReef registry for discovery + public-key distribution
3. **Layer C:** explore direct transport handshake later

### Rationale
The combination of **Layer A + Layer B** provides the strongest practical near-term answer:
- secure enough bootstrap without cleartext secrets
- good operator workflow
- no need to make the registry a secret-holding service
- preserves optional/manual operation for private installs

---

## Design intent summary

- **ClawReef registry** should behave like a **phone book**, not a **vault**.
- **Encrypted exchange payloads** should be portable across whatever channel operators already have.
- **Manual peering** must remain possible.
- **Cleartext secret exchange by email** should be treated as an emergency fallback to eliminate, not normalize.

---

## Open questions for implementation planning

1. Should the default encryption format be strictly `age`, or should there be a pluggable abstraction for future methods?
2. Should the tool send email directly when possible, or default to producing an encrypted blob for the operator to send manually?
3. How much peer config should be auto-written on import versus staged for operator confirmation?
4. What minimum metadata should a ClawReef registry entry expose?
5. Should direct-transport handshake require an interactive approval step on the receiving host?
