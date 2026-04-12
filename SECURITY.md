# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Antenna, **please report it privately** rather than opening a public GitHub issue.

**Email:** [help@clawreef.io](mailto:help@clawreef.io)

Include:
- A description of the vulnerability
- Steps to reproduce (if applicable)
- The version of Antenna you're running
- Any relevant logs or configuration (redact secrets)

We will acknowledge your report within 48 hours and aim to provide a fix or mitigation within 7 days for critical issues.

## Scope

This policy covers the Antenna skill itself — scripts, relay protocol, trust model, and configuration handling. For vulnerabilities in OpenClaw core, please report to the [OpenClaw project](https://github.com/openclaw/openclaw) directly.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.2.x   | ✅ Current |
| < 1.2   | ❌ Upgrade recommended |

## Known Security Considerations

Antenna's security model is documented in the [Relay Protocol FSD](references/ANTENNA-RELAY-FSD.md) and the [User Guide](references/USER-GUIDE.md). Key design decisions:

- **Sandbox off + allowlist execution** — the relay agent runs with `sandbox: off` and `exec.security: allowlist`. This is mitigated by a restrictive binary allowlist, deny lists, peer authentication, rate limits, and session constraints.
- **Secrets at rest** — hooks tokens and peer identity secrets are stored as plaintext files with `chmod 600`. No encryption at rest.
- **Untrusted input framing** — all relayed messages include a security notice so receiving agents treat content as external input.

For a full security assessment, see the references directory.
