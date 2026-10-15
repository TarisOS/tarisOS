// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris
import Taris.Config
import Taris.I18n
import qs.services

// The launcher's >install and >uninstall. >install offers a web app or a package: a web app asks
// for its name (>install web …), then its address (>install url …), and is written by
// assets/install-webapp.sh; a package is searched for in the package repos (>install package …)
// and installed with pacman in the shell's terminal. >uninstall searches the apps, asks, then
// removes the chosen one with assets/remove-app.sh, whatever kind it is.
Singleton {
    id: root

    readonly property string prefix: GlobalConfig.launcher.actionPrefix
    property string webAppName
    property var pendingRemoval: null
    property var packages: []
    property string packageQuery

    function isInstallText(text: string): bool {
        return text.startsWith(`${prefix}install `) || text.startsWith(`${prefix}uninstall `);
    }

    function results(text: string): var {
        const rest = p => text.slice(`${prefix}${p} `.length).trim();

        if (text.startsWith(`${prefix}install web `))
            return [nameRow(rest("install web"))];
        if (text.startsWith(`${prefix}install url `))
            return [urlRow(rest("install url"))];
        if (text.startsWith(`${prefix}install package `)) {
            if (!rest("install package"))
                return [
                    {
                        name: Tr.tr("Package name"),
                        desc: Tr.tr("Search the package repositories"),
                        icon: "search",
                        onClicked: () => {}
                    }
                ];
            return packages.map(packageRow);
        }
        if (text.startsWith(`${prefix}install `)) {
            const search = rest("install").toLowerCase();
            return kinds.filter(k => k.name.toLowerCase().includes(search));
        }
        if (text.startsWith(`${prefix}uninstall `)) {
            const entry = pendingRemoval;
            if (entry)
                return [
                    {
                        name: Tr.tr("Remove %1").arg(entry.name),
                        desc: entry.comment || entry.genericName || "",
                        appIcon: entry.icon,
                        onClicked: list => {
                            root.remove(entry);
                            list.screenState.launcher = false;
                        }
                    },
                    {
                        name: Tr.tr("Cancel"),
                        icon: "close",
                        onClicked: () => root.pendingRemoval = null
                    }
                ];
            return Apps.search(rest("uninstall")).map(appRow);
        }
        return [];
    }

    // The search text changed: package search, and a pending removal is dropped
    function searchChanged(text: string): void {
        pendingRemoval = null;
        const query = text.startsWith(`${prefix}install package `) ? text.slice(`${prefix}install package `.length).trim() : "";
        if (query === packageQuery)
            return;
        packageQuery = query;
        if (query)
            packageSearchTimer.restart();
        else
            packages = [];
    }

    function nameRow(name: string): var {
        return {
            name: name || Tr.tr("Name"),
            desc: Tr.tr("Web app name"),
            icon: "badge",
            onClicked: list => {
                if (!name)
                    return;
                root.webAppName = name;
                list.search.text = `${root.prefix}install url `;
            }
        };
    }

    function urlRow(url: string): var {
        return {
            name: url || "https://",
            desc: Tr.tr("Address for %1").arg(webAppName),
            icon: "link",
            onClicked: list => {
                if (!root.webAppName) {
                    list.search.text = `${root.prefix}install web `;
                    return;
                }
                if (!url)
                    return;
                webAppProc.appName = root.webAppName;
                webAppProc.command = [`${Quickshell.shellDir}/assets/install-webapp.sh`, root.webAppName, url];
                webAppProc.running = true;
                root.webAppName = "";
                list.screenState.launcher = false;
            }
        };
    }

    function packageRow(pkg: var): var {
        return {
            name: pkg.name,
            desc: [pkg.repo, pkg.version, pkg.description].filter(s => s).join(" · "),
            icon: pkg.installed ? "check_circle" : "package_2",
            onClicked: list => {
                if (pkg.installed) {
                    Toaster.toast(Tr.tr("%1 is already installed").arg(pkg.name), "", "check_circle");
                    return;
                }
                list.screenState.launcher = false;
                // pacman asks for the password and to confirm in the terminal. With the system's
                // pending updates: from outdated package lists the install fails (the old files are
                // gone from the mirror), and refreshing them alone (-Sy) is a partial upgrade
                ShellState.componentsForActive()?.panels?.popouts.showTerminal(Tr.tr("Installing %1").arg(pkg.name), `sudo pacman -Syu --needed ${pkg.name}`);
            }
        };
    }

    function appRow(entry: DesktopEntry): var {
        return {
            name: entry.name,
            desc: entry.comment || entry.genericName || "",
            appIcon: entry.icon,
            onClicked: () => root.pendingRemoval = entry
        };
    }

    // Also the app drawer's Remove…: a launcher of yours goes at once; a package's or flatpak's
    // app is uninstalled in the shell's terminal, which asks for the password and to confirm
    function remove(entry: DesktopEntry): void {
        pendingRemoval = null;
        remover.appName = entry.name;
        remover.command = [`${Quickshell.shellDir}/assets/remove-app.sh`, entry.id, entry.name];
        remover.running = true;
    }

    readonly property var kinds: [
        {
            name: Tr.tr("Web app"),
            desc: Tr.tr("A website in its own window"),
            icon: "language",
            onClicked: list => list.search.text = `${root.prefix}install web `
        },
        {
            name: Tr.tr("Package"),
            desc: Tr.tr("From the package repositories"),
            icon: "package_2",
            onClicked: list => list.search.text = `${root.prefix}install package `
        }
    ]

    Timer {
        id: packageSearchTimer

        interval: 200
        onTriggered: {
            if (packageSearch.running)
                return; // Its onExited searches again
            // pacman -Ss takes extended regular expressions, one per word, all of which must match
            const words = root.packageQuery.split(/\s+/).map(w => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
            packageSearch.query = root.packageQuery;
            packageSearch.command = ["pacman", "-Ss", "--", ...words];
            packageSearch.running = true;
        }
    }

    Process {
        id: packageSearch

        property string query

        onExited: { // qmllint disable signal-handler-parameters
            if (root.packageQuery && query !== root.packageQuery)
                packageSearchTimer.restart();
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (packageSearch.query !== root.packageQuery)
                    return;

                // "repo/name version [(groups)] [[installed…]]", then the description indented
                const found = [];
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const m = lines[i].match(/^([^\s/]+)\/(\S+) (\S+)(?: \([^)]*\))?( \[installed[^\]]*\])?$/);
                    if (m && /^[a-zA-Z0-9@._+-]+$/.test(m[2]))
                        found.push({
                            repo: m[1],
                            name: m[2],
                            version: m[3],
                            installed: !!m[4],
                            description: (lines[i + 1] ?? "").trim()
                        });
                }

                // Exact name first, then names starting with the search, then names with it in
                const q = root.packageQuery.toLowerCase();
                const rank = p => p.name === q ? 0 : p.name.startsWith(q) ? 1 : p.name.includes(q) ? 2 : 3;
                root.packages = found.sort((a, b) => rank(a) - rank(b) || a.name.length - b.name.length).slice(0, 50);
            }
        }
    }

    Process {
        id: webAppProc

        property string appName

        stderr: StdioCollector {
            id: webAppErr
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            // The output is collected after the exit
            Qt.callLater(() => {
                if (code === 0)
                    Toaster.toast(Tr.tr("%1 installed").arg(appName), "", "language", Toast.Success);
                else
                    Toaster.toast(Tr.tr("Couldn't install %1").arg(appName), webAppErr.text.trim(), "error", Toast.Error);
            });
        }
    }

    // assets/remove-app.sh: removes a launcher of yours itself, or prints "run <command>" for the
    // terminal (a package's or flatpak's uninstall)
    Process {
        id: remover

        property string appName

        stdout: StdioCollector {
            onStreamFinished: {
                const run = text.match(/^run (.*)$/m);
                if (run)
                    ShellState.componentsForActive()?.panels?.popouts.showTerminal(Tr.tr("Removing %1").arg(remover.appName), run[1]);
            }
        }
    }
}
