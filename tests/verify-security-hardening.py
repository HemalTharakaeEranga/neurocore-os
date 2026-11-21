#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""NeuroCore OS Automated File-by-File Security Hardening & Static Bug Gate.

Audits every layer of the NeuroCore OS repository locally and in GitHub Actions:
  1. Kernel KSPP & attack-surface Kconfig flags
  2. Sysctl, nftables default-deny firewall, SSH, sudoers, modprobe blacklist, AppArmor
  3. Systemd service sandboxing (zero root daemon, IPAddressDeny, seccomp, caps)
  4. Rust, Mojo, Python & Shell source anti-patterns (shell injection, OOB, /tmp races)
  5. Unified kernel patch hunk-count integrity
  6. GitHub Actions supply-chain hygiene (no curl|sh, least-privilege permissions,
     persist-credentials: false, timeout-minutes, no @master mutable refs)
  7. Line endings (zero CRLF in Linux files) & manifest syntax (TOML/JSON/XML)
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent


class AuditReport:
    def __init__(self) -> None:
        self.passed: list[str] = []
        self.failed: list[str] = []

    def check(self, cond: bool, name: str, detail: str = "") -> None:
        if cond:
            self.passed.append(name)
        else:
            msg = f"{name}: {detail}" if detail else name
            self.failed.append(msg)


def _read(rel: str) -> str:
    p = ROOT / rel
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8")


def audit_kernel_hardening(r: AuditReport) -> None:
    cfg = _read("kernel/configs/neurocore_x86_64.fragment")
    required = [
        "CONFIG_RUST=y",
        "CONFIG_SCHED_CLASS_EXT=y",
        "CONFIG_SECURITY_LANDLOCK=y",
        "CONFIG_SECURITY_APPARMOR=y",
        "CONFIG_SECURITY_YAMA=y",
        "CONFIG_SECURITY_LOCKDOWN_LSM=y",
        "CONFIG_BPF_UNPRIV_DEFAULT_OFF=y",
        "CONFIG_SECCOMP_FILTER=y",
        "CONFIG_HARDENED_USERCOPY=y",
        "CONFIG_FORTIFY_SOURCE=y",
        "CONFIG_STACKPROTECTOR_STRONG=y",
        "CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y",
        "CONFIG_INIT_ON_FREE_DEFAULT_ON=y",
        "CONFIG_SLAB_FREELIST_HARDENED=y",
        "CONFIG_STRICT_KERNEL_RWX=y",
        "CONFIG_STRICT_MODULE_RWX=y",
        "CONFIG_DEVMEM=n",
        "CONFIG_LEGACY_TIOCSTI=n",
        "CONFIG_NF_TABLES=y",
    ]
    missing = [opt for opt in required if opt not in cfg.splitlines()]
    r.check(not missing, "Kernel KSPP hardening Kconfig", f"missing {missing}")

    fetch = _read("kernel/fetch-kernel.sh")
    r.check(
        "ABAF11C65A2970B130ABE3C479BE3E4300411886" in fetch
        and "647F28654894E3BD457199BE38DBBDC86092693E" in fetch
        and "VALIDSIG" in fetch,
        "Kernel tarball pinned GPG fingerprint verification",
        "kernel/fetch-kernel.sh missing pinned kernel.org fingerprints or VALIDSIG check",
    )


def audit_kernel_patches(r: AuditReport) -> None:
    hunk_re = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
    bad_patches: list[str] = []
    for p in sorted((ROOT / "kernel/patches").glob("*.patch")):
        lines = p.read_text(encoding="utf-8").splitlines()
        i = 0
        while i < len(lines):
            m = hunk_re.match(lines[i])
            if m:
                old_len = int(m.group(2) or "1")
                new_len = int(m.group(4) or "1")
                i += 1
                old_seen = 0
                new_seen = 0
                while i < len(lines) and not lines[i].startswith(("@@ ", "diff --git ", "-- ")):
                    ln = lines[i]
                    if ln.startswith("-"):
                        old_seen += 1
                    elif ln.startswith("+"):
                        new_seen += 1
                    elif ln.startswith(" ") or ln == "":
                        old_seen += 1
                        new_seen += 1
                    else:
                        break
                    i += 1
                if old_seen != old_len or new_seen != new_len:
                    bad_patches.append(
                        f"{p.name}: declared (-{old_len},+{new_len}) vs actual (-{old_seen},+{new_seen})"
                    )
                continue
            i += 1
    r.check(not bad_patches, "Kernel unified patch hunk integrity", "; ".join(bad_patches))


def audit_os_defense_in_depth(r: AuditReport) -> None:
    sysctl = _read("mkosi/mkosi.extra/etc/sysctl.d/99-neurocore-hardening.conf")
    for k in [
        "kernel.kptr_restrict = 2",
        "kernel.dmesg_restrict = 1",
        "kernel.unprivileged_bpf_disabled = 1",
        "net.core.bpf_jit_harden = 2",
        "kernel.yama.ptrace_scope = 2",
        "kernel.kexec_load_disabled = 1",
        "kernel.io_uring_disabled = 2",
        "fs.suid_dumpable = 0",
        "net.ipv4.tcp_syncookies = 1",
    ]:
        r.check(k in sysctl, f"Sysctl rule '{k}'", "missing from 99-neurocore-hardening.conf")

    nft = _read("mkosi/mkosi.extra/etc/nftables.conf")
    r.check(
        "hook input priority 0; policy drop;" in nft
        and "hook forward priority 0; policy drop;" in nft,
        "Default-deny nftables inbound/forward firewall",
        "missing drop policy in etc/nftables.conf",
    )

    sshd = _read("mkosi/mkosi.extra/etc/ssh/sshd_config.d/10-neurocore-hardening.conf")
    for rule in [
        "ListenAddress 127.0.0.1",
        "PermitRootLogin no",
        "PasswordAuthentication no",
        "PermitEmptyPasswords no",
        "PubkeyAuthentication yes",
    ]:
        r.check(rule in sshd, f"SSH hardening '{rule}'", "missing in 10-neurocore-hardening.conf")

    sudoers = _read("mkosi/mkosi.extra/etc/sudoers.d/90-neurocore-hardened")
    postinst = _read("mkosi/mkosi.postinst.chroot")
    sudoers_active = "\n".join(
        ln for ln in sudoers.splitlines() if not ln.lstrip().startswith("#")
    )
    postinst_active = "\n".join(
        ln for ln in postinst.splitlines() if not ln.lstrip().startswith("#")
    )
    r.check(
        "NOPASSWD" not in sudoers_active and "NOPASSWD" not in postinst_active,
        "Zero passwordless sudo (no NOPASSWD rules)",
        "found active NOPASSWD rule in sudoers or postinst",
    )
    r.check(
        "passwd -l root" in postinst and "rm -f /etc/ssh/ssh_host_" in postinst,
        "Root locked & static SSH host keys stripped in postinst",
        "postinst missing root lock or SSH host key scrub",
    )
    r.check(
        "disable ssh.service" in postinst,
        "SSH disabled by default on Live ISO",
        "postinst should disable ssh.service by default",
    )
    preset = _read("mkosi/mkosi.extra/etc/systemd/system-preset/10-neurocore-security.preset")
    r.check(
        "disable ssh.service" in preset
        and "disable ssh.socket" in preset
        and "enable nftables.service" in preset
        and "enable apparmor.service" in preset,
        "Systemd preset prevents Debian defaults from re-enabling SSH",
        "10-neurocore-security.preset missing ssh disable or nftables/apparmor enable",
    )

    apparmor = _read("mkosi/mkosi.extra/etc/apparmor.d/usr.local.libexec.neurocore-daemon")
    r.check(
        "flags=(enforce)" in apparmor and "deny network inet," in apparmor,
        "AppArmor enforce profile for neurocore-daemon",
        "missing enforce or deny inet in AppArmor profile",
    )

    blacklist = _read("mkosi/mkosi.extra/etc/modprobe.d/99-neurocore-blacklist.conf")
    r.check(
        "install dccp /bin/false" in blacklist and "install cramfs /bin/false" in blacklist,
        "Kernel module attack-surface blacklist",
        "missing module blacklist entries",
    )

    r.check(
        (ROOT / "mkosi/mkosi.repart/00-esp.conf").is_file()
        and (ROOT / "mkosi/mkosi.repart/10-root.conf").is_file(),
        "Deterministic mkosi.repart GPT ESP + ext4 root layout",
        "missing mkosi/mkosi.repart/{00-esp,10-root}.conf",
    )
    r.check(
        "getent group plugdev" in postinst,
        "Safe optional group handling in mkosi.postinst.chroot",
        "postinst should guard optional plugdev group",
    )


def audit_systemd_sandboxing(r: AuditReport) -> None:
    svc_dir = ROOT / "mkosi/mkosi.extra/etc/systemd/system"
    daemons = [
        "neurocore-daemon.service",
        "neurocore-mlflow.service",
        "neurocore-jupyter.service",
        "neurocore-llama.service",
    ]
    mandatory = [
        "User=",
        "NoNewPrivileges=yes",
        "PrivateTmp=yes",
        "ProtectSystem=strict",
        "ProtectKernelTunables=yes",
        "ProtectKernelModules=yes",
        "ProtectControlGroups=yes",
        "LockPersonality=yes",
        "RestrictSUIDSGID=yes",
        "RestrictAddressFamilies=",
        "IPAddressDeny=any",
        "SystemCallArchitectures=native",
        "CapabilityBoundingSet=",
    ]
    for name in daemons:
        txt = (svc_dir / name).read_text(encoding="utf-8")
        missing = [m for m in mandatory if m not in txt]
        r.check(not missing, f"Systemd sandbox: {name}", f"missing {missing}")
        r.check(
            "User=root" not in txt,
            f"Non-root service user: {name}",
            "service runs as root",
        )


def audit_code_security(r: AuditReport) -> None:
    check_rs = _read("rust/neuro-cli/src/check.rs")
    r.check(
        'Command::new("sh")' not in check_rs,
        "Rust neuro-cli free of sh -c shell injection",
        "found Command::new(\"sh\") in check.rs",
    )

    new_rs = _read("rust/neuro-cli/src/new.rs")
    r.check(
        "validate_project_name" in new_rs and "symlink_metadata" in new_rs,
        "Rust neuro-cli path traversal & symlink guards",
        "missing validate_project_name or symlink_metadata in new.rs",
    )

    train_rs = _read("rust/neuro-cli/src/train.rs")
    r.check(
        "starts_with('-')" in train_rs and "fs::canonicalize" in train_rs,
        "Rust neuro-cli argument injection & path canonicalization",
        "missing target validation in train.rs",
    )

    ipc_rs = _read("rust/neurocore-daemon/src/ipc_unix.rs")
    r.check(
        "MAX_CMD_BYTES" in ipc_rs and "set_read_timeout" in ipc_rs,
        "Rust neurocore-daemon bounded read & timeout DoS protection",
        "missing read cap or timeout in ipc_unix.rs",
    )

    bridge_mojo = _read("mojo/kernels/tensor_bridge.mojo")
    r.check(
        "MAX_TENSOR_ELEMS" in bridge_mojo and "MAX_MATMUL_DIM" in bridge_mojo,
        "Mojo C-ABI FFI integer-overflow & bounds protection",
        "missing dimension/overflow bounds checks in tensor_bridge.mojo",
    )

    llama_sh = _read("ml-stack/llama-cpp-build.sh")
    r.check(
        "mktemp -d" in llama_sh and "neurocore-llama-build" not in llama_sh,
        "llama-cpp-build.sh uses isolated mktemp -d (no CWE-377 race)",
        "found predictable temp build path",
    )

    datasets_sh = _read("ml-stack/fetch-datasets.sh")
    r.check(
        "md5sum -c" in datasets_sh and "--tlsv1.2" in datasets_sh,
        "Fashion-MNIST cryptographic checksum & TLS 1.2+ verification",
        "missing checksum verification in fetch-datasets.sh",
    )

    wrap_sh = _read("packaging/wrap-iso.sh")
    r.check(
        "etc/ssh/ssh_host_*" in wrap_sh,
        "ISO packaging excludes static SSH host keys",
        "wrap-iso.sh must exclude etc/ssh/ssh_host_*",
    )


def audit_github_workflows(r: AuditReport) -> None:
    wf_dir = ROOT / ".github/workflows"
    wfs = sorted(wf_dir.glob("*.yml"))
    r.check(len(wfs) >= 4, "All 4 GitHub Actions workflows present", f"found {len(wfs)}")

    sec_wf = _read(".github/workflows/security-audit.yml")
    r.check(
        "grype" in sec_wf and "trivy" in sec_wf and "dependency-review-action" in sec_wf,
        "Always-on Grype + Trivy + PR dependency vulnerability scanning",
        "security-audit.yml missing always-on Grype/Trivy vulnerability scan",
    )
    ci_wf = _read(".github/workflows/ci-build-test.yml")
    r.check(
        "if-no-files-found: ignore" in ci_wf,
        "CI boot-log artifact upload handles missing logs cleanly",
        "ci-build-test.yml missing if-no-files-found: ignore",
    )

    for wf in wfs:
        txt = wf.read_text(encoding="utf-8")
        rel = wf.name
        r.check(
            "permissions: {}" in txt,
            f"Workflow least-privilege default permissions: {rel}",
            "missing top-level `permissions: {}`",
        )
        r.check(
            "persist-credentials: false" in txt,
            f"Workflow checkout persist-credentials=false: {rel}",
            "missing `persist-credentials: false`",
        )
        r.check(
            "timeout-minutes:" in txt,
            f"Workflow job timeout-minutes set: {rel}",
            "missing timeout-minutes",
        )
        r.check(
            not re.search(r"\|\s*(?:sudo\s+)?(?:ba|da|z)?sh(?:\s|$)", txt)
            and "bash <(curl" not in txt,
            f"Workflow free of remote curl|sh execution: {rel}",
            "found remote script pipe execution",
        )
        r.check(
            "@master" not in txt,
            f"Workflow free of mutable @master action ref: {rel}",
            "found @master action ref",
        )
        r.check(
            not re.search(r'(?:chmod\s+0?666|MODE="0?666")', txt),
            f"Workflow free of world-writable 0666 device permissions: {rel}",
            "found world-writable 0666 mode",
        )
        unpinned = [
            ln.strip()
            for ln in txt.splitlines()
            if re.match(r"^\s*-?\s*uses:\s+", ln)
            and not re.search(r"@[0-9a-f]{40}(?:\s+#|\s*$)", ln)
        ]
        r.check(
            not unpinned,
            f"All GitHub Actions pinned to 40-char commit SHA: {rel}",
            f"unpinned actions: {unpinned}",
        )


def audit_manifests_and_eol(r: AuditReport) -> None:
    for p in sorted(ROOT.rglob("*.toml")):
        tomllib.loads(p.read_text(encoding="utf-8"))
    for p in sorted(list(ROOT.rglob("*.json")) + list(ROOT.rglob("*.ipynb"))):
        json.loads(p.read_text(encoding="utf-8"))
    svg_text = _read("branding/source/neurocore-logo.svg")
    svg_ok = (
        "<svg " in svg_text
        and "</svg>" in svg_text
        and "<!DOCTYPE" not in svg_text.upper()
        and "<!ENTITY" not in svg_text.upper()
    )
    r.check(svg_ok, "All TOML, JSON, Jupyter notebook & XXE-safe SVG manifests valid", "invalid or unsafe SVG")

    crlf_bad = []
    exts = {
        ".sh", ".py", ".rs", ".mojo", ".h", ".toml", ".conf", ".cfg",
        ".service", ".slice", ".fragment", ".patch", ".plymouth", ".script",
        ".yml", ".json", ".ipynb", ".chroot", ".sources",
    }
    for p in ROOT.rglob("*"):
        if p.is_file() and (
            p.suffix in exts
            or p.name in {"Makefile", "Kbuild", "os-release", "10-neurocore", "theme.txt"}
        ):
            if b"\r\n" in p.read_bytes():
                crlf_bad.append(str(p.relative_to(ROOT)))
    r.check(not crlf_bad, "Zero CRLF line endings in Linux files", ", ".join(crlf_bad))


def main() -> int:
    report = AuditReport()
    audit_kernel_hardening(report)
    audit_kernel_patches(report)
    audit_os_defense_in_depth(report)
    audit_systemd_sandboxing(report)
    audit_code_security(report)
    audit_github_workflows(report)
    audit_manifests_and_eol(report)

    print(f"=== NeuroCore OS Security Hardening & Bug Audit ({len(report.passed)} passed, {len(report.failed)} failed) ===")
    if report.failed:
        for item in report.failed:
            print(f"  [FAIL] {item}", file=sys.stderr)
        return 1

    print("[PASS] All security hardening, code safety, patch integrity & workflow checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
