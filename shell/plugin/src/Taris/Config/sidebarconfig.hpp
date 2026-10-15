// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace taris::config {

class SidebarConfig : public settings::ObjectNode {
    CONFIG_NODE(SidebarConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(bool, showOnHover, true)
    // How long the pointer has to keep pushing into the top-right corner before the sidebar opens on
    // hover, in milliseconds (0: at a touch); modules/drawers/Interactions.qml
    CONFIG_PROPERTY(int, pushTime, 30)
    CONFIG_PROPERTY(int, minHoverThreshold, 200)
    CONFIG_PROPERTY(int, dragThreshold, 80)
};

} // namespace taris::config
