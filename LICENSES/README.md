<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# Canonical SPDX License Texts (`LICENSES/`)

Per the FSFE REUSE 3.3 specification, this directory holds canonical full-text
SPDX license files corresponding to every identifier declared in `REUSE.toml`
and individual file headers:

- `GPL-2.0-only.txt`
- `Apache-2.0.txt`
- `MIT.txt`
- `BSD-3-Clause.txt`
- `CC-BY-4.0.txt`
- `CC-BY-SA-4.0.txt`
- `CC0-1.0.txt`
- `LLVM-exception.txt`

Populate all canonical texts directly from the official SPDX License List (or
via the FSFE `reuse` tool) by running:

```bash
./scripts/fetch-spdx-licenses.sh
# or:
reuse download --all
```
