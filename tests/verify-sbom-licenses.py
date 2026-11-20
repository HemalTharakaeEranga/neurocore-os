#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""NeuroCore OS SBOM License & Profile Hygiene Gate.

Audits Syft SPDX JSON rootfs SBOMs against tests/expected-licenses.json and
fails the build if any forbidden proprietary/source-available package (such as
Modular MAX, NVIDIA proprietary CUDA user space, or AMD proprietary/ tools)
enters either build profile, or if non-free-firmware enters `core-libre`.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def audit_spdx(spdx_data: dict, policy: dict, profile: str) -> list[str]:
    if profile not in policy["profiles"]:
        return [f"Unknown build profile '{profile}' (expected one of {list(policy['profiles'])})"]

    prof_cfg = policy["profiles"][profile]
    forbidden_pkgs = [p.lower() for p in policy["global_forbidden_package_substrings"]]
    forbidden_pkgs.extend(p.lower() for p in prof_cfg.get("forbidden_package_substrings", []))

    forbidden_lics = [l.lower() for l in policy["global_forbidden_license_substrings"]]
    forbidden_lics.extend(l.lower() for l in prof_cfg.get("forbidden_license_substrings", []))

    violations: list[str] = []
    packages = spdx_data.get("packages", [])

    for pkg in packages:
        name = str(pkg.get("name", "")).strip()
        lname = name.lower()
        declared = str(pkg.get("licenseDeclared", "") or "")
        concluded = str(pkg.get("licenseConcluded", "") or "")
        lic_combined = f"{declared} {concluded}".lower()

        for bad_pkg in forbidden_pkgs:
            if bad_pkg in lname:
                violations.append(
                    f"[FORBIDDEN PACKAGE] '{name}' matched forbidden rule '{bad_pkg}' in profile '{profile}'"
                )

        for bad_lic in forbidden_lics:
            if bad_lic in lic_combined:
                violations.append(
                    f"[FORBIDDEN LICENSE] '{name}' has license '{declared or concluded}' "
                    f"(matched '{bad_lic}') in profile '{profile}'"
                )

    return violations


def run_selftest(policy_path: Path) -> int:
    policy = json.loads(policy_path.read_text(encoding="utf-8"))

    clean_sbom = {
        "spdxVersion": "SPDX-2.3",
        "packages": [
            {"name": "linux-image-6.18.64-neurocore", "licenseDeclared": "GPL-2.0-only"},
            {"name": "mojo", "licenseDeclared": "Apache-2.0 WITH LLVM-exception"},
            {"name": "llama-cpp", "licenseDeclared": "MIT"},
            {"name": "mesa-vulkan-drivers", "licenseDeclared": "MIT"},
        ],
    }
    assert audit_spdx(clean_sbom, policy, "core-libre") == []
    assert audit_spdx(clean_sbom, policy, "baremetal-foss") == []

    fw_sbom = {
        "packages": [
            {"name": "firmware-amd-graphics", "licenseDeclared": "LicenseRef-Debian-non-free-firmware"},
        ]
    }
    assert len(audit_spdx(fw_sbom, policy, "core-libre")) >= 1
    assert audit_spdx(fw_sbom, policy, "baremetal-foss") == []

    bad_sbom = {
        "packages": [
            {"name": "modular-max-engine", "licenseDeclared": "MAX-License"},
            {"name": "nvidia-cuda-toolkit", "licenseDeclared": "NVIDIA-Proprietary-EULA"},
            {"name": "rocprof-trace-decoder", "licenseDeclared": "AMD-Proprietary-EULA"},
        ]
    }
    assert len(audit_spdx(bad_sbom, policy, "baremetal-foss")) >= 3
    assert len(audit_spdx(bad_sbom, policy, "core-libre")) >= 3

    print("[PASS] verify-sbom-licenses.py policy self-test passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify NeuroCore OS Syft SPDX SBOM license policy")
    parser.add_argument("--spdx", type=Path, help="Path to Syft SPDX JSON file")
    parser.add_argument(
        "--policy",
        type=Path,
        default=Path(__file__).with_name("expected-licenses.json"),
    )
    parser.add_argument("--profile", default="baremetal-foss", choices=["core-libre", "baremetal-foss"])
    parser.add_argument("--self-test", action="store_true", help="Run built-in policy unit tests")
    args = parser.parse_args()

    if args.self_test:
        return run_selftest(args.policy)

    if not args.spdx or not args.spdx.exists():
        print(f"ERROR: SPDX SBOM file not found: {args.spdx}", file=sys.stderr)
        return 2

    spdx_data = json.loads(args.spdx.read_text(encoding="utf-8"))
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    violations = audit_spdx(spdx_data, policy, args.profile)

    if violations:
        print(f"[FAIL] SBOM license policy audit failed ({len(violations)} violation(s)):", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    pkg_count = len(spdx_data.get("packages", []))
    print(f"[PASS] SBOM policy verified: {pkg_count} packages clean for profile '{args.profile}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
