# Antenna Agent — Tool Reference

## Relay Script
- Path: `/home/corey/clawd/skills/antenna/scripts/antenna-relay.sh`
- Usage: `echo "<raw_message>" | bash /home/corey/clawd/skills/antenna/scripts/antenna-relay.sh --stdin`
- Outputs JSON to stdout (see AGENTS.md for response handling)

## File Locations
- Peers registry: `/home/corey/clawd/skills/antenna/antenna-peers.json`
- Config: `/home/corey/clawd/skills/antenna/antenna-config.json`
- Log: `/home/corey/clawd/skills/antenna/antenna.log`

## You Do Not Need To
- Read any of these files directly. The script handles all config/peers lookups.
- Write to any files. The script handles logging.
- Access the network. The script was already called by the sender; you just deliver locally.
