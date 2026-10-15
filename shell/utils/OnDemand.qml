// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import Quickshell

// Apps installed on first use (taris-desktop's taris-install-*.desktop entries, which install the
// app and open it): shown greyed out in the launcher and the dock until the app is installed, then
// the app's own entry takes their place. Also TarisOS's entries for apps whose package has no entry
// that shows, or none the launcher shows (taris-shell's: NordVPN's own is only its login link
// handler, and KDE Connect opens in the shell rather than in KDE's app).
Singleton {
    // The stand-in's entry id -> the ids the installed app's entry can have (VSCodium's; VS Code's,
    // which TarisOS installed before it: its arm64 package names it com.microsoft.VSCode, other
    // builds code)
    readonly property var apps: ({
            "taris-install-code": ["codium", "com.microsoft.VSCode", "code", "visual-studio-code"],
            "taris-install-steam": ["steam"],
            "taris-install-obs": ["com.obsproject.Studio"],
            "taris-install-writer": ["libreoffice-writer"],
            "taris-install-calc": ["libreoffice-calc"],
            "taris-install-impress": ["libreoffice-impress"],
            "taris-install-firefox": ["firefox"],
            "taris-install-nordvpn": ["nordvpn"]
        })
    // The stand-in's entry id -> the package that installs it (as /usr/lib/taris/install-on-demand
    // has them, for an entry opened without the shell: keep the two the same)
    readonly property var packages: ({
            "taris-install-code": "vscodium-bin",
            "taris-install-steam": "steam",
            "taris-install-obs": "obs-studio",
            "taris-install-writer": "libreoffice-fresh",
            "taris-install-calc": "libreoffice-fresh",
            "taris-install-impress": "libreoffice-fresh",
            "taris-install-firefox": "firefox",
            "taris-install-nordvpn": "nordvpn-bin"
        })
    // TarisOS's entry id -> the package's own (hidden) entry id. TarisOS's stays installed when the
    // package is removed, and Quickshell doesn't read TryExec, so it shows only while the package's
    // own is there. Remove… uninstalls the package its X-Taris-Package names (assets/remove-app.sh).
    readonly property var fronts: ({
            "taris-kdeconnect": "org.kde.kdeconnect.app",
            "taris-nordvpn": "nordvpn"
        })

    function isPlaceholder(entry: var): bool {
        return !!entry && Object.prototype.hasOwnProperty.call(apps, entry.id);
    }

    // The installed app's entry for a stand-in's id (null until it's installed): TarisOS's entry
    // for it where it has one (NordVPN's own only handles its login links)
    function installedFor(id: string): var {
        DesktopEntries.applications.values; // Again when apps are installed or removed
        for (const real of apps[id] ?? []) {
            const entry = DesktopEntries.byId(real);
            if (entry) {
                const front = Object.keys(fronts).find(f => fronts[f] === real);
                return (front ? DesktopEntries.byId(front) : null) ?? entry;
            }
        }
        return null;
    }

    // A front whose package isn't installed
    function missing(entry: var): bool {
        DesktopEntries.applications.values; // Again when apps are installed or removed
        const own = entry ? fronts[entry.id] : undefined;
        return own !== undefined && DesktopEntries.byId(own) === null;
    }

    function hidden(entry: var): bool {
        return (isPlaceholder(entry) && installedFor(entry.id) !== null) || missing(entry);
    }
}
