# Antenna Agent — Tool Reference

## Relay Script
- Path: `./scripts/antenna-relay.sh` (relative to skill directory)
- Usage: `echo "<raw_message>" | bash ./scripts/antenna-relay.sh --stdin`
- Outputs JSON to stdout (see AGENTS.md for response handling)

## File Locations (relative to skill directory)
- Peers registry: `./antenna-peers.json`
- Config: `./antenna-config.json`
- Log: `./antenna.log` (or as configured in `log_path`)

## Absolute Path Resolution
If relative paths don't resolve, read `install_path` from `antenna-config.json`:
```bash
ANTENNA_DIR=$(jq -r '.install_path' ./antenna-config.json)
bash "$ANTENNA_DIR/scripts/antenna-relay.sh" --stdin
```

## You Do Not Need To
- Read any of these files directly. The script handles all config/peers lookups.
- Write to any files. The script handles logging.
- Access the network. The script was already called by the sender; you just deliver locally.
