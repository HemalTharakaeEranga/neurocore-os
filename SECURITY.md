<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# Security Policy

## Supported Versions

| Version | Status | Security Support |
| --- | --- | --- |
| `0.1.0-alpha` ("Spark") | Active development preview | Best-effort security updates and CVE triage |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, report vulnerabilities privately via:

1. **GitHub Private Vulnerability Reporting** (Security Advisories tab in this repository), or
2. Email `security@neurocore-os.org` (include affected component, version/profile,
   reproduction steps, and impact assessment).

### Response Targets

- **Acknowledgement**: within 72 hours.
- **Triage & Severity Assessment**: within 7 days.
- **Coordinated Disclosure**: patches, updated SBOMs, and security advisories
  published once a fix or mitigation is verified.

## Release Verification & Supply-Chain Integrity

Every official release publishes:

- `SHA256SUMS` covering all `.iso`, `.vdi`, `.qcow2`, and `-sources.tar.zst` files
- Keyless Sigstore `cosign` bundles (`*.sigstore.json`)
- SLSA v1 build provenance attestations (`gh attestation verify`)
- Dual Syft SBOMs (`*.spdx.json` and `*.cdx.json`) audited with `grype --fail-on critical`

Verify downloaded artifacts before booting:

```bash
cosign verify-blob \
  --bundle neurocore-0.1.0-alpha-baremetal-foss-amd64.iso.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/HemalTharakaeEranga/neurocore-os/' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  neurocore-0.1.0-alpha-baremetal-foss-amd64.iso
```
