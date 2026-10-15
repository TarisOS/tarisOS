// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

/*
 * SiliconMotion's SMIUSBDisplayManager calls evdi_open_attached_to(NULL) to
 * get any free EVDI device. Upstream libevdi runs strlen() on that argument
 * and crashes; its _fixed variant handles NULL (get_generic_device) properly.
 * Preloaded into smiusbdisplay.service to route the call there.
 */
#include <stddef.h>
#include <string.h>

typedef struct evdi_device_context *evdi_handle;
evdi_handle evdi_open_attached_to_fixed(const char *sysfs_parent_device, size_t length);

evdi_handle evdi_open_attached_to(const char *sysfs_parent_device)
{
	return evdi_open_attached_to_fixed(sysfs_parent_device,
					   sysfs_parent_device ? strlen(sysfs_parent_device) : 0);
}
