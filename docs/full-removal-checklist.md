# Antenna Full Removal Checklist

How to return a host to pre-Antenna state. Use this when testing fresh installs
or fully decommissioning Antenna from a host.

## 1. Antenna Uninstall (built-in)

```bash
cd ~/clawd/skills/antenna && ./bin/antenna uninstall --yes
```

This removes:
- `antenna-config.json`
- `antenna-peers.json`
- `secrets/` directory
- `antenna.log` and rotated logs
- `antenna-ratelimit.json`
- `test-results/`
- Antenna agent/hooks entries from gateway config

Does NOT remove:
- Skill code directory itself
- External token files outside the skill dir
- Bundle files (`.age.txt`)
- Gateway backup files created by Antenna
- `age` package
- Git remote configuration

## 2. Remove bundle files

```bash
rm -f ~/clawd/skills/antenna/antenna-bootstrap-*.age.txt
rm -f ~/clawd/skills/antenna/bettyxix-reply-bundle.age.txt  # or any manually named bundles
```

## 3. Remove gateway backup files

```bash
rm -f ~/.openclaw/openclaw.json.antenna-*
```

This cleans up:
- `.antenna-backup`
- `.antenna-pre-register-*`
- `.antenna-uninstall-backup-*`
- `.antenna-fix-*`
- `.antenna-manual-register-*`

## 4. Remove external/stale token files

```bash
rm -f ~/clawd/secrets/hooks_token
rm -f ~/clawd/secrets/hooks_token_*
```

## 5. Clean gateway config (if uninstall missed anything)

```python
python3 -c "
import json
gw = '$HOME/.openclaw/openclaw.json'
c = json.load(open(gw))
# Remove antenna from agents list
if 'agents' in c and 'list' in c['agents']:
    c['agents']['list'] = [a for a in c['agents']['list'] if a.get('id') != 'antenna']
# Remove Antenna-related hooks entries
if 'hooks' in c:
    c['hooks']['allowedSessionKeyPrefixes'] = [
        p for p in c['hooks'].get('allowedSessionKeyPrefixes', [])
        if 'antenna' not in p.lower()
    ]
    c['hooks']['allowedAgentIds'] = [
        a for a in c['hooks'].get('allowedAgentIds', [])
        if a != 'antenna'
    ]
json.dump(c, open(gw, 'w'), indent=2)
"
```

## 6. Uninstall age (check ALL install methods)

```bash
# Debian/Ubuntu (apt)
sudo apt-get remove -y age && sudo apt-get autoremove -y

# Homebrew / Linuxbrew (may also be present!)
brew uninstall age 2>/dev/null || true

# Check for Linuxbrew directly if brew isn't on PATH
ls /home/linuxbrew/.linuxbrew/bin/age* 2>/dev/null && \
  /home/linuxbrew/.linuxbrew/bin/brew uninstall age 2>/dev/null

# Manual / go install
rm -f ~/go/bin/age ~/go/bin/age-keygen 2>/dev/null

# Verify fully removed
which age 2>/dev/null && echo "STILL FOUND" || echo "clean"
ls /home/linuxbrew/.linuxbrew/bin/age 2>/dev/null && echo "STILL IN LINUXBREW" || echo "clean"
```

**Note:** Antenna's interactive setup may install age via Homebrew (`try_install_age`),
so even if the original was from apt, a Linuxbrew copy may exist after running setup.

## 7. Restart gateway

```bash
openclaw gateway restart
```

## 8. Verify clean state

```bash
# No age
which age && echo "STILL INSTALLED" || echo "clean"
which age-keygen && echo "STILL INSTALLED" || echo "clean"

# No Antenna runtime
ls ~/clawd/skills/antenna/antenna-config.json 2>/dev/null && echo "STILL EXISTS" || echo "clean"
ls ~/clawd/skills/antenna/antenna-peers.json 2>/dev/null && echo "STILL EXISTS" || echo "clean"
ls ~/clawd/skills/antenna/secrets 2>/dev/null && echo "STILL EXISTS" || echo "clean"

# No bundle files
ls ~/clawd/skills/antenna/*.age.txt 2>/dev/null && echo "STILL EXISTS" || echo "clean"

# No gateway backups
ls ~/.openclaw/openclaw.json.antenna-* 2>/dev/null && echo "STILL EXISTS" || echo "clean"

# No external tokens
ls ~/clawd/secrets/hooks_token* 2>/dev/null && echo "STILL EXISTS" || echo "clean"

# Gateway config clean
python3 -c "
import json
c = json.load(open('$HOME/.openclaw/openclaw.json'))
agents = [a['id'] for a in c.get('agents',{}).get('list',[])]
print('antenna in agents:', 'antenna' in agents)
print('antenna in allowedAgentIds:', 'antenna' in c.get('hooks',{}).get('allowedAgentIds',[]))
"
```

## Notes

- The skill code directory (`~/clawd/skills/antenna/`) is intentionally preserved.
  To remove it too, add `--purge-skill-dir` to the uninstall command.
- Git remote for the skill repo may need re-adding after this process
  (`git remote add origin <url>`). This is a known quirk (#15).
- This checklist was created 2026-04-03 during the v1.0.18 meat testing marathon.
