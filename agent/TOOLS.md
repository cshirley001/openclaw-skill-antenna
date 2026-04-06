# Antenna Agent — Tool Reference

## Relay Script
- Path: `$ANTENNA_DIR/scripts/antenna-relay.sh`
- Usage: `echo "<raw_message>" | bash "$ANTENNA_DIR/scripts/antenna-relay.sh" --stdin`
- Outputs JSON to stdout

## Config Resolution
Normal workspace is the Antenna `agent/` directory, so the runtime config is usually one level up:
```bash
CONFIG_PATH="../antenna-config.json"
[ -f "$CONFIG_PATH" ] || CONFIG_PATH="antenna-config.json"
ANTENNA_DIR=$(jq -r '.install_path' "$CONFIG_PATH")
```

## Runtime Files
- Config: `../antenna-config.json` (normal case)
- Peers registry: `../antenna-peers.json`
- Log: `../antenna.log` (or as configured in `log_path`)

## You Do Not Need To
- Parse peers or config yourself beyond resolving `install_path`
- Write any files directly
- Access the network
- Interpret the message body
