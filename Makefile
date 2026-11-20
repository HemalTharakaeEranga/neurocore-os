# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

VERSION        := $(shell cat VERSION)
PROFILE        ?= baremetal-foss
KERNEL_TRACK   ?= lts
ARCH           ?= amd64
OUT_DIR        := $(CURDIR)/out
SOURCE_DATE_EPOCH ?= $(shell git log -1 --pretty=%ct 2>/dev/null || date +%s)
export SOURCE_DATE_EPOCH
export VERSION
export PROFILE

.PHONY: all help doctor fetch-licenses security-audit branding kernel rust-tools ml-stack image image-libre \
        iso vdi qcow2 sbom gpl-sources reuse-lint verify verify-vbox clean

all: branding rust-tools kernel image iso vdi qcow2 sbom

help:
	@echo "NeuroCore OS v$(VERSION) ('Spark') Build System"
	@echo ""
	@echo "Profiles: PROFILE=baremetal-foss (default) | PROFILE=core-libre"
	@echo "Kernel:   KERNEL_TRACK=lts (Linux 6.18 LTS, default) | KERNEL_TRACK=next (Linux 7.3+)"
	@echo ""
	@echo "Targets:"
	@echo "  make doctor       Verify Linux/WSL2 host prerequisites"
	@echo "  make branding     Generate dark-adapted CLUT224, GRUB, Plymouth, and hicolor icons"
	@echo "  make kernel       Fetch, verify, patch, and compile Linux $(KERNEL_TRACK) kernel + Rust .ko"
	@echo "  make rust-tools   Build neuro, neurocore-daemon, and neuro-bench (Rust 1.100)"
	@echo "  make ml-stack     Fetch Fashion-MNIST, generate synthetic tabular data, stage ML manifests"
	@echo "  make image        Build mkosi Debian 13 disk image (PROFILE=$(PROFILE))"
	@echo "  make image-libre  Build strictly 100% Debian-main core-libre image (zero non-free-firmware)"
	@echo "  make iso          Wrap mkosi .raw rootfs into reproducible tri-mode BIOS/UEFI hybrid ISO"
	@echo "  make vdi          Convert mkosi .raw disk image into VirtualBox .vdi"
	@echo "  make qcow2        Convert mkosi .raw disk image into compressed QEMU .qcow2"
	@echo "  make sbom         Generate Syft SPDX + CycloneDX SBOMs and validate license policy"
	@echo "  make gpl-sources  Package GPLv2 Section 3 Complete Corresponding Source archive"
	@echo "  make reuse-lint   Run FSFE REUSE 3.3 compliance verification"
	@echo "  make verify       Run headless QEMU/KVM BIOS + UEFI smoke tests"
	@echo "  make verify-vbox  Run VirtualBox 7.2 scripted smoke test"
	@echo "  make clean        Remove build artifacts and staging caches"

doctor:
	@echo "==> Checking host build prerequisites (Linux / WSL2)"
	@for cmd in git bash python3 make clang-19 lld-19 rustc cargo mkosi mksquashfs grub-mkrescue xorriso qemu-img; do \
		if command -v "$$cmd" >/dev/null 2>&1; then \
			printf "  [OK]      %s -> %s\n" "$$cmd" "$$(command -v "$$cmd")"; \
		else \
			printf "  [MISSING] %s\n" "$$cmd"; \
		fi; \
	done
	@if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then \
		echo "  [OK]      ImageMagick found"; \
	else \
		echo "  [MISSING] ImageMagick (magick/convert)"; \
	fi
	@if [ -w /dev/kvm ]; then \
		echo "  [OK]      /dev/kvm writable (KVM hardware acceleration enabled)"; \
	else \
		echo "  [WARN]    /dev/kvm not writable (QEMU smoke tests require KVM)"; \
	fi

branding:
	./branding/build-branding.sh

kernel: branding
	$(MAKE) -C kernel KERNEL_TRACK=$(KERNEL_TRACK) build-deb

rust-tools:
	cd rust && cargo build --release --workspace
	install -d mkosi/mkosi.extra/usr/local/bin mkosi/mkosi.extra/usr/local/libexec
	install -m 0755 rust/target/release/neuro mkosi/mkosi.extra/usr/local/bin/neuro
	install -m 0755 rust/target/release/neuro-bench mkosi/mkosi.extra/usr/local/bin/neuro-bench
	install -m 0755 rust/target/release/neurocore-daemon mkosi/mkosi.extra/usr/local/libexec/neurocore-daemon

ml-stack:
	./ml-stack/fetch-datasets.sh mkosi/mkosi.extra/usr/share/neurocore/datasets

image:
	mkdir -p $(OUT_DIR)
	mkosi --directory=mkosi --profile=$(PROFILE) --output-directory=$(OUT_DIR) build

image-libre:
	$(MAKE) PROFILE=core-libre image

iso:
	./packaging/wrap-iso.sh --profile "$(PROFILE)" --version "$(VERSION)" --out-dir "$(OUT_DIR)"

vdi:
	./packaging/build-vdi.sh --profile "$(PROFILE)" --version "$(VERSION)" --out-dir "$(OUT_DIR)"

qcow2:
	./packaging/build-qcow2.sh --profile "$(PROFILE)" --version "$(VERSION)" --out-dir "$(OUT_DIR)"

sbom:
	python3 tests/verify-sbom-licenses.py \
		--spdx "$(OUT_DIR)/neurocore-$(VERSION)-$(PROFILE).spdx.json" \
		--policy tests/expected-licenses.json \
		--profile "$(PROFILE)"

gpl-sources:
	./packaging/collect-gpl-sources.sh --profile "$(PROFILE)" --version "$(VERSION)" --out-dir "$(OUT_DIR)"

fetch-licenses:
	./scripts/fetch-spdx-licenses.sh

security-audit:
	python3 tests/verify-security-hardening.py
	python3 tests/verify-sbom-licenses.py --self-test

reuse-lint:
	reuse lint

verify:
	./tests/qemu-smoke.sh --iso "$(OUT_DIR)/neurocore-$(VERSION)-$(PROFILE)-$(ARCH).iso"

verify-vbox:
	./tests/vbox-smoke.sh --iso "$(OUT_DIR)/neurocore-$(VERSION)-$(PROFILE)-$(ARCH).iso" \
		--vdi "$(OUT_DIR)/neurocore-$(VERSION)-$(PROFILE)-$(ARCH).vdi"

clean:
	rm -rf $(OUT_DIR) branding/generated rust/target kernel/build tests/logs tests/work
	rm -rf mkosi/mkosi.cache mkosi/mkosi.builddir
