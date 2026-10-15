// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris
import Taris.I18n
import qs.services

// The Store's data (modules/store). assets/store.py runs while a Store is open (users > 0) and
// answers requests over stdin/stdout; installs, removals and updates of Flatpak and repo apps are
// jobs it reports progress for. AUR apps are built by yay in the shell's terminal instead.
Singleton {
    id: root

    property int users // Stores open; the helper runs while there are any, or a job is running
    property bool ready
    property var jobs: ({}) // key -> { state: running | done | failed, progress, message }
    // An install, removal or update is running: the helper must not be stopped mid-way (pacman
    // interrupted can leave its database locked or half-updated)
    readonly property bool busy: Object.values(jobs).some(j => j.state === "running")
    property int changes // Goes up when what's installed changed: views load again
    property int updateCount // Flatpak and AUR apps with an update (the Updates tab)
    // AUR packages a terminal is working on: pkg -> { mode: install | remove | update, version
    // (before an update), since }
    property var awaitingAur: ({})

    property int _nextId: 1
    property var _callbacks: ({})
    property list<string> _queue: []

    // TarisOS's own builds (its repository), which the AUR has other versions of: never offered as
    // AUR updates (on a machine where they were built locally, they look like AUR packages)
    readonly property list<string> localBuilds: ["taris-shell", "taris-cli", "quickshell-taris", "libcava", "python-materialyoucolor", "qmltermwidget-taris", "qt6-m3shapes-git", "ttf-rubik-vf", "evdi-dkms", "mise-bin", "yay", "vscodium-bin", "nordvpn-bin", "lyrebird-proxy", "tela-icon-theme", "whitesur-icon-theme", "fluent-icon-theme-git", "libva-v4l2-request-avd", "tor-browser-bin", "taris-music"]

    // Returns the request's id, for cancel() (a view closed before its answer came). The id and
    // cmd go on last, so nothing in args can replace them
    function request(cmd: string, args: var, callback: var): int {
        const id = _nextId++;
        _callbacks[id] = callback ?? null;
        const line = JSON.stringify(Object.assign({}, args ?? {}, {
            id,
            cmd
        }));
        if (ready)
            helper.write(line + "\n");
        else
            _queue.push(line);
        return id;
    }

    function cancel(id: int): void {
        delete _callbacks[id];
    }

    function checkUpdates(): void {
        request("updates", {}, result => {
            if (result)
                updateCount = result.length;
        });
    }

    onReadyChanged: {
        if (ready)
            checkUpdates();
    }
    onChangesChanged: checkUpdates()

    function jobFor(key: string): var {
        return jobs[key] ?? null;
    }

    // Package names go into a terminal command line
    function safeName(pkg: string): bool {
        return /^[a-zA-Z0-9@._+-]+$/.test(pkg);
    }

    function install(app: var, source: string, pkg: string, key: string): void {
        if (source === "aur")
            return aurTerminal(Tr.tr("Installing %1").arg(app.name), "yay -S", [pkg], "install", {});
        markRunning(key);
        request("install", {
            key,
            source,
            pkg
        }, (result, err) => {
            if (err)
                finishJob(key, false, err);
        });
    }

    // A job the helper never started (it refused, or the terminal took it over)
    function finishJob(key: string, ok: bool, message: string): void {
        const all = Object.assign({}, jobs);
        if (ok)
            delete all[key];
        else
            all[key] = {
                state: "failed",
                progress: 1,
                message
            };
        jobs = all;
        if (!ok)
            Toaster.toast(Tr.tr("Couldn't finish"), message, "error", Toast.Error);
    }

    // Running from the click on, before the helper says so: the Store may close meanwhile (a
    // password prompt takes the focus)
    function markRunning(key: string): void {
        const all = Object.assign({}, jobs);
        all[key] = {
            state: "running",
            progress: -1,
            message: ""
        };
        jobs = all;
    }

    function remove(app: var, source: string, pkg: string, key: string): void {
        if (source === "aur")
            return aurTerminal(Tr.tr("Removing %1").arg(app.name), "sudo pacman -Rns", [pkg], "remove", {});
        markRunning(key);
        request("remove", {
            key,
            source,
            pkg
        }, (result, err) => {
            if (err)
                finishJob(key, false, err);
        });
    }

    function update(app: var): void {
        if (app.source === "aur")
            return aurTerminal(Tr.tr("Updating %1").arg(app.name), "yay -S", [app.pkg], "update", {
                [app.pkg]: app.version
            });
        markRunning(app.key);
        request("update", {
            key: app.key,
            source: app.source,
            pkg: app.pkg
        }, (result, err) => {
            if (err)
                finishJob(app.key, false, err);
        });
    }

    // command and the packages (checked, they go into a command line) in the shell's terminal;
    // versions: each package's version before an update
    function aurTerminal(title: string, command: string, pkgs: list<string>, mode: string, versions: var): void {
        if (!pkgs.length || !pkgs.every(p => safeName(p)))
            return;
        terminalJob(title, `${command} ${pkgs.join(" ")}`, pkgs, mode, versions);
    }

    // A whole command line in the shell's terminal; pkgs are what it installs, removes or updates
    // (watched until it has)
    function terminalJob(title: string, commandLine: string, pkgs: list<string>, mode: string, versions: var): void {
        ShellState.componentsForActive()?.panels?.popouts.showTerminal(title, commandLine);
        const waiting = Object.assign({}, awaitingAur);
        for (const pkg of pkgs)
            waiting[pkg] = {
                mode,
                version: versions[pkg] ?? "",
                since: Date.now()
            };
        awaitingAur = waiting;
    }

    // The app's launcher, or `flatpak run` for a Flatpak this session's launcher doesn't list yet
    function launch(app: var): void {
        const id = (app.desktop ?? "").replace(/\.desktop$/, "");
        const entry = id ? DesktopEntries.byId(id) : null;
        if (entry)
            entry.execute();
        else if (app.source === "flathub")
            Quickshell.execDetached(["flatpak", "run", app.pkg]);
    }

    function handle(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.event === "ready") {
            ready = true;
            for (const queued of _queue)
                helper.write(queued + "\n");
            _queue = [];
        } else if (msg.event === "job") {
            const all = Object.assign({}, jobs);
            all[msg.key] = {
                state: msg.state,
                progress: msg.progress,
                message: msg.message
            };
            jobs = all;
            if (msg.state === "failed")
                Toaster.toast(Tr.tr("Couldn't finish"), msg.message, "error", Toast.Error);
        } else if (msg.event === "changed") {
            changes++;
        } else if (msg.id !== undefined) {
            const callback = _callbacks[msg.id];
            delete _callbacks[msg.id];
            if (callback)
                callback(msg.error ? null : msg.result, msg.error ?? "");
        }
    }

    Process {
        id: helper

        running: root.users > 0 || root.busy || Object.keys(root.awaitingAur).length > 0
        stdinEnabled: true
        command: ["python3", "-I", `${Quickshell.shellDir}/assets/store.py`, "--ignore-aur", root.localBuilds.join(",")]
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        onRunningChanged: {
            if (!running) {
                root.ready = false;
                root._callbacks = {};
                root._queue = [];
                root.jobs = {};
            }
        }
    }

    // While a terminal installs or removes an AUR app: notice when it has (given up after 15 minutes)
    Timer {
        running: root.ready && Object.keys(root.awaitingAur).length > 0
        interval: 3000
        repeat: true
        onTriggered: root.request("refresh", {
            pkgs: Object.keys(root.awaitingAur)
        }, versions => {
            if (!versions)
                return;
            const waiting = Object.assign({}, root.awaitingAur);
            let done = false;
            for (const pkg in waiting) {
                const w = waiting[pkg];
                const now = versions[pkg] ?? "";
                if (w.mode === "install" ? now !== "" : w.mode === "remove" ? now === "" : now !== "" && now !== w.version) {
                    delete waiting[pkg];
                    done = true;
                } else if (Date.now() - waiting[pkg].since > 15 * 60000) {
                    delete waiting[pkg];
                }
            }
            root.awaitingAur = waiting;
            if (done)
                root.changes++;
        })
    }
}
