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
using util::i18n::markCtx;

class LauncherUseFuzzy : public settings::ObjectNode {
    CONFIG_NODE(LauncherUseFuzzy, settings::ObjectNode)

    CONFIG_PROPERTY(bool, apps, false)
    CONFIG_PROPERTY(bool, actions, false)
    CONFIG_PROPERTY(bool, schemes, false)
    CONFIG_PROPERTY(bool, variants, false)
    CONFIG_PROPERTY(bool, wallpapers, false)
};

class LauncherAction : public settings::ObjectNode {
    CONFIG_NODE(LauncherAction, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(QString, name, {})
    CONFIG_PROPERTY(QString, icon, {})
    CONFIG_PROPERTY(QString, description, {})
    CONFIG_PROPERTY(QStringList, command, {})
    CONFIG_PROPERTY(bool, dangerous, false)
};
CONFIG_LIST_TYPE(LauncherAction, LauncherActionList)

class LauncherConfig : public settings::ObjectNode {
    CONFIG_NODE(LauncherConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(bool, showOnHover, false)
    CONFIG_PROPERTY(int, maxShown, 7)
    CONFIG_PROPERTY(int, maxWallpapers, 9)
    CONFIG_GLOBAL_PROPERTY(QString, specialPrefix, u"@"_s)
    CONFIG_GLOBAL_PROPERTY(QString, actionPrefix, u">"_s)
    CONFIG_GLOBAL_PROPERTY(bool, enableDangerousActions, false)
    CONFIG_PROPERTY(int, dragThreshold, 50)
    CONFIG_GLOBAL_PROPERTY(bool, vimKeybinds, false)
    CONFIG_GLOBAL_PROPERTY(QStringList, favouriteApps, {})
    // Tools other packages bring along, which aren't apps to open from the drawer, KDE Connect's own
    // windows (the shell has its own: taris-kdeconnect) and Papers (sushi's, a second document viewer
    // beside Evince)
    CONFIG_GLOBAL_PROPERTY(QStringList, hiddenApps,
        DEFAULT_ARG({ u"avahi-discover"_s, u"bssh"_s, u"bvnc"_s, u"cmake-gui"_s, u"qv4l2"_s, u"qvidcap"_s,
            u"mpv"_s, u"vim"_s, u"lstopo"_s, u"org.kde.kdeconnect.app"_s, u"org.kde.kdeconnect.sms"_s,
            u"org.kde.kdeconnect.nonplasma"_s, u"org.gnome.Papers"_s }))
    // The app drawer's order: TarisOS's apps, then the apps installed on first use (each with the ids
    // its stand-in and the installed app can have); everything else comes after
    CONFIG_GLOBAL_PROPERTY(QStringList, appOrder,
        DEFAULT_ARG({ u"taris-settings"_s, u"taris-store"_s, u"org.gnome.DiskUtility"_s, u"taris-kdeconnect"_s,
            u"kitty"_s, u"org.gnome.Nautilus"_s, u"chromium"_s, u"tor-browser"_s, u"webapp-discord"_s, u"taris-music"_s,
            u"org.qbittorrent.qBittorrent"_s, u"org.gnome.TextEditor"_s, u"nvim"_s, u"taris-install-code"_s,
            u"codium"_s, u"com.microsoft.VSCode"_s, u"code"_s, u"visual-studio-code"_s, u"taris-install-steam"_s,
            u"steam"_s,
            u"taris-install-obs"_s, u"com.obsproject.Studio"_s, u"taris-install-writer"_s,
            u"libreoffice-writer"_s, u"taris-install-calc"_s, u"libreoffice-calc"_s, u"taris-install-impress"_s,
            u"libreoffice-impress"_s, u"org.gnome.Evince"_s, u"taris-install-firefox"_s, u"firefox"_s,
            u"taris-install-nordvpn"_s, u"taris-nordvpn"_s }))
    CONFIG_GLOBAL_SUBOBJECT(LauncherUseFuzzy, useFuzzy)
    CONFIG_GLOBAL_LIST(LauncherActionList, actions,
        DEFAULT_ARG({
            vmap({
                { u"name"_s, markCtx(u"Calculator"_s, u"launcher action"_s) },
                { u"icon"_s, u"calculate"_s },
                { u"description"_s, mark(u"Do simple maths equations (powered by Qalc)"_s) },
                { u"command"_s, QStringList{ u"autocomplete"_s, u"calc"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Install"_s, u"launcher action"_s) },
                { u"icon"_s, u"download"_s },
                { u"description"_s, mark(u"Add a web app or a package"_s) },
                { u"command"_s, QStringList{ u"autocomplete"_s, u"install"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Uninstall"_s, u"launcher action"_s) },
                { u"icon"_s, u"delete"_s },
                { u"description"_s, mark(u"Remove an app"_s) },
                { u"command"_s, QStringList{ u"autocomplete"_s, u"uninstall"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Scheme"_s, u"launcher action"_s) },
                { u"icon"_s, u"palette"_s },
                { u"description"_s, mark(u"Change the current colour scheme"_s) },
                { u"command"_s, QStringList{ u"autocomplete"_s, u"scheme"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Wallpaper"_s, u"launcher action"_s) },
                { u"icon"_s, u"image"_s },
                { u"description"_s, mark(u"Change the current wallpaper"_s) },
                { u"command"_s, QStringList{ u"autocomplete"_s, u"wallpaper"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Variant"_s, u"launcher action"_s) },
                { u"icon"_s, u"colors"_s },
                { u"description"_s, mark(u"Change the current scheme variant"_s) },
                { u"command"_s, QStringList{ u"autocomplete"_s, u"variant"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Random"_s, u"launcher action"_s) },
                { u"icon"_s, u"casino"_s },
                { u"description"_s, mark(u"Switch to a random wallpaper"_s) },
                { u"command"_s, QStringList{ u"taris"_s, u"wallpaper"_s, u"-r"_s, u"-n"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Light"_s, u"launcher action"_s) },
                { u"icon"_s, u"light_mode"_s },
                { u"description"_s, mark(u"Change the scheme to light mode"_s) },
                { u"command"_s, QStringList{ u"setMode"_s, u"light"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Dark"_s, u"launcher action"_s) },
                { u"icon"_s, u"dark_mode"_s },
                { u"description"_s, mark(u"Change the scheme to dark mode"_s) },
                { u"command"_s, QStringList{ u"setMode"_s, u"dark"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Shutdown"_s, u"launcher action"_s) },
                { u"icon"_s, u"power_settings_new"_s },
                { u"description"_s, mark(u"Shutdown the system"_s) },
                { u"command"_s, QStringList{ u"poweroff"_s } },
                { u"dangerous"_s, true },
            }),
            vmap({
                { u"name"_s, markCtx(u"Reboot"_s, u"launcher action"_s) },
                { u"icon"_s, u"cached"_s },
                { u"description"_s, mark(u"Reboot the system"_s) },
                { u"command"_s, QStringList{ u"reboot"_s } },
                { u"dangerous"_s, true },
            }),
            vmap({
                { u"name"_s, markCtx(u"Logout"_s, u"launcher action"_s) },
                { u"icon"_s, u"exit_to_app"_s },
                { u"description"_s, mark(u"Log out of the current session"_s) },
                { u"command"_s, QStringList{ u"logout"_s } },
                { u"dangerous"_s, true },
            }),
            vmap({
                { u"name"_s, markCtx(u"Lock"_s, u"launcher action"_s) },
                { u"icon"_s, u"lock"_s },
                { u"description"_s, mark(u"Lock the current session"_s) },
                { u"command"_s, QStringList{ u"loginctl"_s, u"lock-session"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Sleep"_s, u"launcher action"_s) },
                { u"icon"_s, u"bedtime"_s },
                { u"description"_s, mark(u"Suspend then hibernate"_s) },
                { u"command"_s, QStringList{ u"suspendThenHibernate"_s } },
            }),
            vmap({
                { u"name"_s, markCtx(u"Settings"_s, u"launcher action"_s) },
                { u"icon"_s, u"settings"_s },
                { u"description"_s, mark(u"Configure the shell"_s) },
                { u"command"_s, QStringList{ u"taris"_s, u"shell"_s, u"nexus"_s, u"open"_s } },
            }),
        }))
};

} // namespace taris::config
