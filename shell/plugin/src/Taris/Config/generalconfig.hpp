// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qstring.h>
#include <qstringlist.h>
#include <qvariantlist.h>

#include "settings/objectnode.hpp"
#include "util/i18n.hpp"
#include "common.hpp"

namespace taris::config {

using Qt::StringLiterals::operator""_s;
using settings::vmap;
using util::i18n::mark;

class GeneralApps : public settings::ObjectNode {
    CONFIG_NODE(GeneralApps, settings::ObjectNode)

    CONFIG_PROPERTY(QStringList, terminal, { u"kitty"_s })
    CONFIG_PROPERTY(QStringList, audio, { u"pwvucontrol"_s })
    CONFIG_PROPERTY(QStringList, playback, { u"mpv"_s })
    CONFIG_PROPERTY(QStringList, explorer, { u"nautilus"_s })
    // The coding agent the dashboard's Agent tab runs (an id assets/agent/launch.sh knows); Claude
    // Code is installed the first time the tab runs it
    CONFIG_PROPERTY(QString, agent, u"claude"_s)
};

class GeneralIdleTimeout : public settings::ObjectNode {
    CONFIG_NODE(GeneralIdleTimeout, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(int, timeout, 300)
    CONFIG_PROPERTY(QVariant, idleAction, {}, .allowedTypes = settings::unionTypes<QString, QStringList>())
    CONFIG_PROPERTY(QVariant, returnAction, {}, .allowedTypes = settings::unionTypes<QString, QStringList>())
    CONFIG_PROPERTY(bool, inhibitWhenAudio, false)
    CONFIG_PROPERTY(bool, inhibitWhenCharging, false)
    CONFIG_PROPERTY(bool, respectInhibitors, true)
};
CONFIG_LIST_TYPE(GeneralIdleTimeout, GeneralIdleTimeoutList)

class GeneralIdle : public settings::ObjectNode {
    CONFIG_NODE(GeneralIdle, settings::ObjectNode)

    CONFIG_PROPERTY(bool, lockBeforeSleep, true)
    CONFIG_PROPERTY(bool, inhibitWhenAudio, true)
    CONFIG_PROPERTY(bool, inhibitWhenCharging, false)
    CONFIG_LIST(GeneralIdleTimeoutList, timeouts,
        DEFAULT_ARG({
            vmap({
                { u"timeout"_s, 180 },
                { u"idleAction"_s, u"lock"_s },
            }),
            vmap({
                { u"timeout"_s, 300 },
                { u"idleAction"_s, u"dpms off"_s },
                { u"returnAction"_s, u"dpms on"_s },
            }),
            vmap({
                { u"timeout"_s, 600 },
                { u"idleAction"_s, QStringList{ u"suspendThenHibernate"_s } },
            }),
        }))
};

class GeneralBatteryWarnLevel : public settings::ObjectNode {
    CONFIG_NODE(GeneralBatteryWarnLevel, settings::ObjectNode)

    CONFIG_PROPERTY(int, level, -1)
    CONFIG_PROPERTY(QString, title, {})
    CONFIG_PROPERTY(QString, message, {})
    CONFIG_PROPERTY(QString, icon, {})
    CONFIG_PROPERTY(bool, critical, false)
};
CONFIG_LIST_TYPE(GeneralBatteryWarnLevel, GeneralBatteryWarnList)

class GeneralBattery : public settings::ObjectNode {
    CONFIG_NODE(GeneralBattery, settings::ObjectNode)

    CONFIG_LIST(GeneralBatteryWarnList, warnLevels,
        DEFAULT_ARG({
            vmap({
                { u"level"_s, 20 },
                { u"title"_s, mark(u"Low battery"_s) },
                { u"message"_s, mark(u"You might want to plug in a charger"_s) },
                { u"icon"_s, u"battery_android_frame_2"_s },
            }),
            vmap({
                { u"level"_s, 10 },
                { u"title"_s, mark(u"Did you see the previous message?"_s) },
                { u"message"_s, mark(u"You should probably plug in a charger <b>now</b>"_s) },
                { u"icon"_s, u"battery_android_frame_1"_s },
            }),
            vmap({
                { u"level"_s, 5 },
                { u"title"_s, mark(u"Critical battery level"_s) },
                { u"message"_s, mark(u"PLUG THE CHARGER RIGHT NOW!!"_s) },
                { u"icon"_s, u"battery_android_alert"_s },
                { u"critical"_s, true },
            }),
        }))
    CONFIG_PROPERTY(int, criticalLevel, 3)
};

class GeneralConfig : public settings::ObjectNode {
    CONFIG_NODE(GeneralConfig, settings::ObjectNode)

    CONFIG_GLOBAL_PROPERTY(QString, logo, {})
    // What the taskbar's launcher button opens: "settings", "launcher", "store", "terminal", "files",
    // "overview", or "app:<desktop entry id>" for an app (Settings > Panels > Taskbar)
    CONFIG_GLOBAL_PROPERTY(QString, logoAction, u"settings"_s)
    CONFIG_GLOBAL_PROPERTY(QString, language, {})
    // What the power button does: "lock", "sleep" or "poweroff" (logind's own action)
    CONFIG_GLOBAL_PROPERTY(QString, powerButton, u"lock"_s)
    // What closing the lid does: "sleep" (logind's own), "stash" (the open apps kept, then shut
    // down) or "nothing"
    CONFIG_GLOBAL_PROPERTY(QString, lidAction, u"sleep"_s)
    // The output (eDP-1, DVI-I-1…) that always has the shell, takes the shortcuts pressed on a
    // display without it, and holds workspace 1 (Settings > Displays). Empty: the first screen
    CONFIG_GLOBAL_PROPERTY(QString, mainDisplay, {})
    CONFIG_PROPERTY(bool, showOverFullscreen, false)
    CONFIG_PROPERTY(qreal, mediaGifSpeedAdjustment, 300)
    CONFIG_GLOBAL_SUBOBJECT(GeneralApps, apps)
    CONFIG_GLOBAL_SUBOBJECT(GeneralIdle, idle)
    CONFIG_GLOBAL_SUBOBJECT(GeneralBattery, battery)
};

} // namespace taris::config
