# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

KERNEL_TRACK    ?= lts
LTS_VERSION     ?= 6.18.64
NEXT_VERSION    ?= 7.3.5

ifeq ($(KERNEL_TRACK),next)
  KERNEL_VERSION := $(NEXT_VERSION)
else
  KERNEL_VERSION := $(LTS_VERSION)
endif

KERNEL_ARCH     ?= x86_64
KERNEL_RUSTC    ?= /usr/bin/rustc
KERNEL_BINDGEN  ?= /usr/bin/bindgen
SRC_DIR         := $(CURDIR)/src/linux-$(KERNEL_VERSION)
BUILD_DIR       := $(CURDIR)/build/$(KERNEL_TRACK)-$(KERNEL_ARCH)
MKOSI_PKG_DIR   := $(CURDIR)/../mkosi/mkosi.packages

export KERNEL_TRACK KERNEL_VERSION KERNEL_ARCH KERNEL_RUSTC KERNEL_BINDGEN

.PHONY: help fetch rust-check build-deb build-rust-module clean

help:
	@echo "NeuroCore OS Kernel Build System"
	@echo "  KERNEL_TRACK=lts  -> Linux $(LTS_VERSION) LTS (default)"
	@echo "  KERNEL_TRACK=next -> Linux $(NEXT_VERSION) (Rust Nova + 7.x validation)"
	@echo ""
	@echo "Targets: fetch | rust-check | build-deb | build-rust-module | clean"

fetch:
	./fetch-kernel.sh --version "$(KERNEL_VERSION)" --dest "$(CURDIR)/src"

rust-check: fetch
	@echo "==> Verifying Rust-for-Linux toolchain availability (rustc=$(KERNEL_RUSTC))"
	$(MAKE) -C "$(SRC_DIR)" O="$(BUILD_DIR)" LLVM=1 RUSTC="$(KERNEL_RUSTC)" BINDGEN="$(KERNEL_BINDGEN)" rustavailable

build-deb: fetch
	./build-kernel-deb.sh \
		--track "$(KERNEL_TRACK)" \
		--version "$(KERNEL_VERSION)" \
		--arch "$(KERNEL_ARCH)" \
		--src-dir "$(SRC_DIR)" \
		--build-dir "$(BUILD_DIR)" \
		--out-dir "$(MKOSI_PKG_DIR)"

build-rust-module:
	$(MAKE) -C rust-modules/neurocore_telemetry \
		KDIR="$(BUILD_DIR)" \
		LLVM=1 \
		RUSTC="$(KERNEL_RUSTC)" \
		BINDGEN="$(KERNEL_BINDGEN)"

clean:
	rm -rf "$(CURDIR)/build"
	$(MAKE) -C rust-modules/neurocore_telemetry clean || true
