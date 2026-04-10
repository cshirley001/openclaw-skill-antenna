# Antenna Copy Draft — v1.2.0 (Playful Voice Pass)

Review doc for Corey. This shows the **proposed** text changes for `antenna-setup.sh` and `antenna-pair.sh`. Functional code stays identical — only user-facing strings change.

**Voice principles (from the docx):**
- Puns decorate verbs and celebrations, not nouns people need to understand
- Alternate fun and substance — not every line needs a joke
- Error messages stay clear first, warm second
- Input prompts stay crisp — comedy doesn't belong where you're typing
- Lobster 🦞 emoji appears at celebration moments, not on every line
- The doc's confidence and warmth > random quips

---

## antenna-setup.sh

### Banner (interactive mode)

**Before:**
```
📡 Antenna Setup — Inter-Host OpenClaw Messaging

  This wizard will configure Antenna on this host.
  You'll need:
    1. Your OpenClaw host ID (usually your hostname)
    2. Your reachable HTTPS hook URL
    3. Your primary agent ID (e.g., 'lobster')
    4. A relay model (e.g., 'openai/gpt-4o-mini')
    5. Whether to enable inbox mode (optional)
    6. Path to your OpenClaw hooks bearer token file
```

**After:**
```
🦞 📡 Antenna Setup — Let's Get You on the Reef

  This wizard configures Antenna on this host.
  Two minutes from now, you'll be ready to send your first
  cross-host message. No PhD required. No shellfish expertise
  necessary (though it helps).

  You'll need:
    1. A host ID (usually just your hostname)
    2. Your reachable HTTPS hook URL
    3. Your primary agent ID (e.g., 'lobster')
    4. A relay model (lightweight is best — the relay doesn't think, it dispatches)
    5. Whether to enable inbox mode (optional, more secure)
    6. Path to your OpenClaw hooks bearer token file
```

### Step headers

**Before → After:**

| Step | Before | After |
|------|--------|-------|
| 1/7 | `Host Identity` | `Host Identity — Who Are You on the Reef?` |
| 2/7 | `Reachable Endpoint` | `Reachable Endpoint — Where Do Peers Find You?` |
| 3/7 | `Agent Identity` | `Agent Identity — Who's Running the Show?` |
| 4/7 | `Relay Model` | `Relay Model — Choosing Your Dispatcher` |
| 5/7 | `Inbound Message Handling` | `Inbound Message Handling — Instant or Inspected?` |
| 6/7 | `Hooks Bearer Token` | `Hooks Bearer Token — The Key to the Door` |
| 7/7 | `Confirmation` | `Confirmation — Look Good?` |

### Step 4 model hint

**Before:**
```
The model used by the Antenna relay agent for tool dispatch.
Use a full provider/model ID (not an alias) for portability.
A lightweight/mechanical model works best — the relay agent should NOT interpret messages.
```

**After:**
```
The model used by Antenna's relay agent for tool dispatch.
Use a full provider/model ID (not an alias) for portability.
Pick something lightweight — the relay agent is a courier, not a philosopher.
It dispatches messages, not opinions.
```

### Step 5 (inbox) description

**Before:**
```
  Antenna can handle inbound messages in two ways:

    Instant relay (default)
      Messages arrive in your session immediately.
      Requires sandbox-off on the relay agent.

    Inbox queue (more secure)
      Messages are held for your review before delivery.
      You approve/deny via 'antenna inbox' commands.
      Trusted peers can auto-approve (bypass the queue).
```

**After:**
```
  When a message arrives, how should Antenna handle it?

    Instant relay (default)
      Straight to your session, no delay. Like a walkie-talkie.
      Requires sandbox-off on the relay agent.

    Inbox queue (more secure)
      Messages wait in a queue for your review first.
      You approve or deny via 'antenna inbox' commands.
      Trusted peers can skip the line.
```

### Gateway Config Backup header

**Before:** `═══ Gateway Config Backup ═══`
**After:** `═══ Backing Up Your Gateway Config (Just in Case) ═══`

### Gateway Registration header

**Before:** `═══ Gateway Registration ═══`
**After:** `═══ Registering Antenna with Your Gateway ═══`

### Auto-registration success messages

These stay mostly the same (they're ✓ confirmations), but the final validation line changes:

**Before:**
```
✓ Gateway config is valid JSON after changes
```

**After:**
```
✓ Gateway config is valid JSON — nothing broken, nothing weird.
```

### CLI PATH Setup header

**Before:** `═══ CLI PATH Setup ═══`
**After:** `═══ Putting Antenna on Your PATH ═══`

### Next Steps section

**Before:**
```
═══ Next Steps ═══

  1. Restart the gateway to activate changes:
     openclaw gateway restart
  2. Verify the registration:
     antenna doctor
```

**After:**
```
═══ Almost There! ═══

  1. Restart the gateway to bring Antenna online:
     openclaw gateway restart

  2. Run the doctor to make sure everything checks out:
     antenna doctor
```

### Pairing section at end

**Before:**
```
═══ Pairing with a Remote Peer ═══

  Ready to connect to a remote peer? The pairing wizard walks you
  through keypair generation, bundle exchange, and first message.

  You can also run it later:  antenna pair
```

**After:**
```
═══ Ready to Connect? ═══

  The fun part! The pairing wizard walks you through connecting
  to another host — keypair exchange, encrypted bundles, and your
  first message.

  Run it now or save it for later:  antenna pair
```

### Final success line

**Before:**
```
✓ Setup complete! Your host ID is: <host>
```

**After:**
```
✓ Setup complete! Welcome to the reef, <host>. 🦞
```

### Pairing wizard auto-offer

**Before:**
```
Would you like to pair with a remote peer now?
```

**After:**
```
Ready to pair with your first peer? (The wizard handles everything.)
```

---

## antenna-pair.sh

### Header and intro

**Before:**
```
═══ Antenna Peer Pairing Wizard ═══

  This wizard walks you through connecting to a remote Antenna peer.
  Each step can be skipped if you've already completed it.
  You can quit at any time and resume later with: antenna pair
```

**After:**
```
═══ 🦞 Antenna Pairing Wizard ═══

  Let's connect you to another host on the reef.
  Each step has Next / Skip / Quit — go at your own pace.
  You can bail out anytime and pick up where you left off:  antenna pair
```

### Step labels

| Step | Before | After |
|------|--------|-------|
| 1/7 | `Generate exchange keypair` | `Generate your exchange keypair` |
| 2/7 | `Your public key` | `Share your public key` |
| 3/7 | `Create bootstrap bundle for your peer` | `Build a bootstrap bundle for your peer` |
| 4/7 | `Wait for their reply bundle` | `Wait for their reply` |
| 5/7 | `Import their reply bundle` | `Import their bundle` |
| 6/7 | `Test connectivity` | `Test the connection` |
| 7/7 | `Send your first message!` | `Send your first message! 🦞` |

### Step 1: keypair exists warning

**Before:**
```
Exchange keypair already exists.
```

**After:**
```
You've already got a keypair — no need to generate a new one unless you want a fresh start.
```

### Step 2: pubkey display

**Before:**
```
  Share this key with your peer (safe to share openly):

  <key>

  Your peer needs this key to create an encrypted bootstrap bundle for you.
```

**After:**
```
  Here's your public key — share it with your peer.
  It's safe to post openly; it's a lock, not a key.

  <key>

  Your peer needs this to encrypt a bootstrap bundle that only you can open.
```

**Wait prompt before → after:**
- `Press Enter once you've shared your key with your peer`
- `Press Enter once your peer has your key`

### Step 3: bundle creation

**Info line before → after:**
- `Creating encrypted bootstrap bundle...`
- `Building your encrypted bootstrap bundle...`

**Success block before:**
```
  Bundle created!

  Send this file to your peer:
  <path>

  Recommended methods: scp, email attachment, or secure file share.
  Avoid pasting the contents inline — email clients can corrupt the encoding.
```

**After:**
```
  Bundle created!

  Send this file to your peer:
  <path>

  Email attachment, scp, carrier pigeon — whatever works.
  Just don't paste the contents inline; email clients love to mangle encoded text.
```

**Wait prompt before → after:**
- `Press Enter once you've sent the bundle to your peer`
- `Press Enter once you've sent it off`

### Step 4: waiting

**Before:**
```
  Your peer needs to:
    1. Import your bundle:  antenna peers exchange import <your-bundle>
    2. Create a reply:      antenna peers exchange reply <peer-id>
    3. Send you the reply bundle file
```

**After:**
```
  Ball's in their court. They need to:
    1. Import your bundle:  antenna peers exchange import <your-bundle>
    2. Create a reply:      antenna peers exchange reply <peer-id>
    3. Send you the reply file

  This is a good time to grab coffee. ☕
```

**Wait prompt before → after:**
- `Press Enter once you've received their reply bundle`
- `Press Enter once you have their reply bundle`

### Step 5: import prompt

**Before:**
```
Path to the bundle file you received
```

**After:**
```
Path to the reply bundle you received
```

### Step 6: test connectivity

**Before:**
```
Testing connection to <peer>...
```

**After:**
```
Pinging <peer> — let's see if anyone's home...
```

### Step 7: first message

**Default message before → after:**
- `Hello from the other side! 👋`
- `Hello from the other side of the reef! 🦞`

**Sending line before → after:**
- `Sending to <peer>...`
- `Releasing the lobster to <peer>... 🦞`

### Completion

**Before:**
```
═══ Pairing Complete ═══

  You're connected! Here are some handy commands:

  Send a message:     antenna msg <peer> "Your message"
  Target a session:   antenna msg <peer> --session agent:main:test "Hi"
  Check status:       antenna peers test <peer>
  List peers:         antenna peers list
  Run diagnostics:    antenna doctor

✓ Happy messaging! 📡
```

**After:**
```
═══ 🦞 You're Claw-nected! ═══

  Welcome to the reef. Here's your cheat sheet:

  Send a message:     antenna msg <peer> "Your message"
  Target a session:   antenna msg <peer> --session agent:main:test "Hi"
  Check status:       antenna peers test <peer>
  List peers:         antenna peers list
  Run diagnostics:    antenna doctor

✓ Happy messaging! The ocean just got smaller. 🦞 📡
```

### Quit message (throughout)

**Before:**
```
Wizard stopped. You can resume later with: antenna pair
```

**After:**
```
No worries — pick up where you left off anytime:  antenna pair
```

### Error messages

Keep these clear, add a light touch only where it doesn't obscure:

| Context | Before | After |
|---------|--------|-------|
| Missing peer ID | `Peer ID is required.` | `Need a peer ID to continue — what do you call the other host?` |
| Missing pubkey | `Public key is required to create an encrypted bundle.` | `Can't build a bundle without their public key — ask your peer for it.` |
| File not found | `File not found: <path>` | `Can't find that file: <path> — double-check the path?` |
| No pubkey available | `Could not retrieve public key. Run: antenna peers exchange keygen` | `No public key found — run: antenna peers exchange keygen` |

---

## What stays unchanged

- All functional code, validation logic, non-interactive mode text
- Helper function signatures and color codes  
- ✓/ℹ/⚠/✗ prefix patterns (keep the visual system)
- Input prompt text (the `?` lines where users type) — these stay crisp
- Auto-registration success confirmations (these are status reports, not celebrations)
- Technical descriptions in the gateway registration manual-fallback block
- Anything behind `--help`

---

## Notes for review

1. **Emoji density:** 🦞 appears exactly 6 times across both scripts (banner, step 7 label, default message, sending line, completion header, completion footer). Enough to feel branded, not enough to feel like a Slack channel.

2. **"The reef" as metaphor:** Used sparingly — banner, step 1 header, completion. Establishes setting without beating it to death.

3. **Puns used:** "Claw-nected" (completion only), "shellfish expertise" (banner only). That's it. Two puns across ~500 lines of output.

4. **Tone shift:** The biggest change isn't jokes — it's *warmth*. "This wizard will configure..." → "Let's get you on the reef." "Press Enter once you've shared your key with your peer" → "Press Enter once your peer has your key." More human, same information.

5. **Step header subtitles on setup only:** The pair wizard keeps short labels because steps move fast. Setup has longer headers because each step needs more context.
