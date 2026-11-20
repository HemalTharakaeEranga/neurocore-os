# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: GPL-2.0-only

KDIR    ?= /lib/modules/$(shell uname -r)/build
LLVM    ?= 1
RUSTC   ?= /usr/bin/rustc
BINDGEN ?= /usr/bin/bindgen

.PHONY: all clean

all:
	$(MAKE) -C "$(KDIR)" M="$(CURDIR)" LLVM="$(LLVM)" RUSTC="$(RUSTC)" BINDGEN="$(BINDGEN)" modules

clean:
	$(MAKE) -C "$(KDIR)" M="$(CURDIR)" clean || rm -f *.o *.ko *.mod* .*.cmd Module.symvers modules.order
