# Antenna Setup Completion Output — v1.1.8

Captured 2026-04-09 from a fresh AntTest install.

```
═══ Gateway Registration ═══

? Automatically register Antenna agent and enable hooks in gateway config? [y]:
✓ Hooks enabled, token registered, and allowlists updated
ℹ Created default main agent entry (agents.list was empty)
✓ Registered Antenna agent in gateway config (sandbox off, least-privilege tools)
✓ Set commands.ownerDisplay = "raw" (required for Control UI visibility)
✓ Set tools.sessions.visibility = "all" (required for cross-agent relay)
✓ Set tools.agentToAgent.enabled = true
✓ Exec allowlist configured for antenna agent (bash, echo, jq, cat)
✓ Gateway config is valid JSON after changes

═══ CLI PATH Setup ═══
✓ Symlinked antenna CLI → /usr/local/bin/antenna (with sudo)


═══ Next Steps ═══

 1. Restart the gateway to activate changes:
    openclaw gateway restart
 2. Verify the registration:
    antenna doctor

═══ Pairing with a Remote Peer ═══

 4. Generate your age exchange keypair (if not already done):
    antenna peers exchange keygen
 5. Share your public key with the remote peer (safe to share openly):
    antenna peers exchange pubkey --bare
 6. Create an encrypted bootstrap bundle for the remote peer:
    antenna peers exchange initiate <peer-id> --pubkey <their-age-pubkey>
 7. Send the bundle file to the remote peer (email, scp, paste, etc.)
 8. Import their reciprocal bundle when you receive it:
    antenna peers exchange import <bundle-file>
 9. Test connectivity:
    antenna peers test <peer-id>
 10. Send your first message:
     antenna msg <peer-id> "Hello from the other side!"

Manual/legacy alternative (if age is unavailable):
    antenna peers add <peer-id> --url <url> --token-file <path>
    antenna peers exchange <peer-id> --legacy

Notes:
 - antenna-config.json and antenna-peers.json are local runtime files
 - tracked reference examples live at:
     antenna-config.example.json
     antenna-peers.example.json

ℹ Inbox is disabled — messages relay instantly (requires sandbox-off).
  To enable later: antenna config set inbox_enabled true

✓ Setup complete! Your host ID is: anttest
```
