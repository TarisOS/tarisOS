// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qstring.h>
#include <qstringlist.h>

#include "settings/objectnode.hpp"
#include "common.hpp"

namespace taris::config {

using Qt::StringLiterals::operator""_s;

class SessionIcons : public settings::ObjectNode {
    CONFIG_NODE(SessionIcons, settings::ObjectNode)

    CONFIG_PROPERTY(QString, logout, u"logout"_s)
    CONFIG_PROPERTY(QString, shutdown, u"power_settings_new"_s)
    // The third button sleeps (named hibernate for the configs that set it; Apple Silicon can't
    // hibernate, so it suspends)
    CONFIG_PROPERTY(QString, hibernate, u"bedtime"_s)
    CONFIG_PROPERTY(QString, stash, u"move_to_inbox"_s)
    CONFIG_PROPERTY(QString, reboot, u"cached"_s)
};

class SessionCommands : public settings::ObjectNode {
    CONFIG_NODE(SessionCommands, settings::ObjectNode)

    CONFIG_PROPERTY(QStringList, logout, { u"logout"_s })
    CONFIG_PROPERTY(QStringList, shutdown, { u"poweroff"_s })
    CONFIG_PROPERTY(QStringList, hibernate, { u"suspend"_s })
    // "stash" is the shell's Stash (the Stash service), not a program
    CONFIG_PROPERTY(QStringList, stash, { u"stash"_s })
    CONFIG_PROPERTY(QStringList, reboot, { u"reboot"_s })
};

class SessionConfig : public settings::ObjectNode {
    CONFIG_NODE(SessionConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(int, dragThreshold, 30)
    CONFIG_PROPERTY(bool, vimKeybinds, false)
    // Whether the Stash button asks first (its notice, until "Don't show this again")
    CONFIG_GLOBAL_PROPERTY(bool, stashNotice, true)
    CONFIG_SUBOBJECT(SessionIcons, icons)
    CONFIG_SUBOBJECT(SessionCommands, commands)
};

} // namespace taris::config
