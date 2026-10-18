# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-2.0-only

# Builds the read-only SMC key reader against the running kernel's headers (linux-asahi-headers).
# Usage: make; make clean

obj-m := taris_smc_keys.o

KDIR ?= /usr/lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
