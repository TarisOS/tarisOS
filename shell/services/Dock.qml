// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris
import Taris.Config
import qs.services
import qs.utils
import qs.modules.launcher.services as Launcher

Singleton {
    id: root

    readonly property list<string> pinned: adapter.pinned
    // The dock at the bottom of the screen (Settings > Dock)
    readonly property bool enabled: adapter.enabled
    // The app drawer button at the end of the dock
    readonly property bool showAppsButton: adapter.showAppsButton
    // Taris Settings in its own place, just above the apps button (instead of as a pinned app)
    readonly property bool showSettings: adapter.showSettings
    // The Trash at the very end of the dock
    readonly property bool showTrash: adapter.showTrash
    // How long the pointer has to keep pushing into the bottom edge before the dock shows, in
    // milliseconds (0: at a touch); modules/drawers/Interactions.qml
    readonly property int pushTime: adapter.pushTime
    // Desktop ids that open at login (~/.config/autostart)
    property list<string> autostart: []
    // Taris's own windows (Settings and its file picker) carry Quickshell's app id, whose desktop
    // entry launches nothing; in the dock they're Taris Settings, which opens Settings again
    readonly property string settingsId: "taris-settings"

    // Steam, which Asahi runs in a small VM (muvm): closing its window leaves it running for its
    // tray icon, which can't reach the shell from the VM. While the VM runs, Steam stays in the
    // dock as running: a click shows its window again, Quit shuts it down (and the VM with it).
    readonly property string steamId: "steam"
    property bool steamRunning
    readonly property bool steamInstalled: {
        DesktopEntries.applications.values; // Again when apps are installed or removed
        return !!DesktopEntries.byId(steamId);
    }
    // Docks shown (Ref in the dock's Wrapper): what's running only shows there
    property int refCount: 0
    // Bumped when the icon theme changes (Settings > Wallpaper & style), so the dock's icons, made
    // once and kept, are read again from the new pack
    property int iconRevision
    // Set for a moment as the pack changes: the dock lets go of its icons so they can be dropped
    property bool iconsClearing

    // The pinned apps' entries, in order (pins whose app is gone are left out)
    readonly property list<var> pinnedApps: {
        DesktopEntries.applications.values; // Again once the apps are read (none are at startup)
        const out = [];
        const seen = new Set();
        if (showSettings)
            seen.add(settingsId);
        for (const id of adapter.pinned) {
            const e = entryFor(id);
            if (e && !seen.has(e.id)) {
                seen.add(e.id);
                out.push(e);
            }
        }
        return out;
    }

    // Running apps that aren't pinned
    readonly property list<var> runningApps: {
        const out = [];
        const seen = new Set(pinnedApps.map(e => e.id));
        if (showSettings)
            seen.add(settingsId);
        for (const t of Hypr.toplevels.values) {
            const e = entryForToplevel(t);
            if (e && !seen.has(e.id)) {
                seen.add(e.id);
                out.push(e);
            }
        }
        // Steam with its window closed
        const steam = steamRunning ? DesktopEntries.byId(steamId) : null;
        if (steam && !seen.has(steam.id))
            out.push(steam);
        return out;
    }

    // Settings in its own place (just before the apps button)
    readonly property DesktopEntry settingsApp: {
        DesktopEntries.applications.values;
        return showSettings ? DesktopEntries.byId(settingsId) : null;
    }

    // Pinned apps first, then running apps that aren't pinned
    readonly property list<var> apps: [...pinnedApps, ...runningApps]

    // Dragging an app to the dock, to pin it or move it (from the dock itself or the app drawer).
    // The dock under the drag sets dropIndex (where among the pinned apps it lands, -1 when it
    // isn't over them) and overTrash (dropping it there takes it out of the dock).
    property DesktopEntry dragApp: null
    property var dragWindow: null
    property point dragPos // In dragWindow's content item
    property int dropIndex: -1
    property bool overTrash
    // The drag started in the dock: dropped anywhere off it, the app leaves the dock
    property bool dragFromDock

    // The dock as it would be with the dragged app dropped where it's held
    readonly property list<var> previewApps: {
        if (!dragApp || dropIndex < 0)
            return apps;
        const pins = pinnedApps.filter(e => e.id !== dragApp.id);
        pins.splice(Math.min(dropIndex, pins.length), 0, dragApp);
        return [...pins, ...runningApps.filter(e => e.id !== dragApp.id)];
    }

    signal dragStarted(window: var)
    signal dragEnded

    function setEnabled(on: bool): void {
        adapter.enabled = on;
    }

    function setShowAppsButton(show: bool): void {
        adapter.showAppsButton = show;
    }

    function setShowSettings(show: bool): void {
        adapter.showSettings = show;
    }

    function setShowTrash(show: bool): void {
        adapter.showTrash = show;
    }

    function setPushTime(ms: int): void {
        adapter.pushTime = ms;
    }

    function move(id: string, by: int): void {
        const list = [...adapter.pinned];
        const i = list.indexOf(id);
        const j = i + by;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        [list[i], list[j]] = [list[j], list[i]];
        adapter.pinned = list;
    }

    function startDrag(entry: DesktopEntry, window: var, pos: point, fromDock: bool): void {
        // Settings keeps its own place while it's shown there
        if (showSettings && entry.id === settingsId)
            return;
        dropIndex = -1;
        overTrash = false;
        dragFromDock = fromDock;
        dragWindow = window;
        dragPos = pos;
        dragApp = entry;
        dragStarted(window);
    }

    function endDrag(): void {
        const entry = dragApp;
        if (entry) {
            // On the Trash, or (dragged out of the dock) anywhere off the dock: unpinned
            if (overTrash && OnDemand.isPlaceholder(entry))
                removeStandIn(entry);
            else if (overTrash || (dragFromDock && dropIndex < 0))
                adapter.pinned = adapter.pinned.filter(p => entryFor(p)?.id !== entry.id);
            else if (dropIndex >= 0)
                pinAt(entry.id, dropIndex);
        }
        cancelDrag();
    }

    function cancelDrag(): void {
        dragApp = null;
        dragWindow = null;
        dropIndex = -1;
        overTrash = false;
        dragFromDock = false;
        dragEnded();
    }

    // Pins the app at index among the pinned apps the dock shows (moving it when it's pinned
    // already); every other pin stays, in its order, those whose app isn't found too
    function pinAt(id: string, index: int): void {
        const pins = adapter.pinned.filter(p => p !== id && entryFor(p)?.id !== id);
        let at = pins.length;
        let shown = 0;
        for (let i = 0; i < pins.length; i++) {
            if (!entryFor(pins[i]))
                continue;
            if (shown === index) {
                at = i;
                break;
            }
            shown++;
        }
        pins.splice(at, 0, id);
        adapter.pinned = [...new Set(pins)];
    }

    function openTrash(): void {
        trashOpener.running = true;
    }

    function emptyTrash(): void {
        Quickshell.execDetached(["gio", "trash", "--empty"]);
    }

    // (A pinned stand-in for an app installed on first use is the app once it's installed; a front
    // whose package was removed is gone, as the app would be)
    function entryFor(id: string): DesktopEntry {
        const entry = OnDemand.installedFor(id) ?? DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
        return OnDemand.missing(entry) ? null : entry;
    }

    function entryForToplevel(toplevel: var): var {
        const ipc = toplevel?.lastIpcObject;
        // The agent workspace's window is no app's: SUPER + A shows it
        if (ipc?.pid === Quickshell.processId)
            return ipc.title === Hypr.agentWindowTitle ? null : DesktopEntries.byId(settingsId);
        const cls = ipc?.class ?? "";
        return cls ? DesktopEntries.heuristicLookup(cls) : null;
    }

    // Running with no window showing (Steam, its window closed until it's quit)
    function runsInBackground(entry: DesktopEntry): bool {
        return entry?.id === steamId && steamRunning;
    }

    // Steam's own launcher in its VM, where Asahi's steam package keeps it (/usr/bin/steam, the
    // package's, puts up a splash each time): it hands the argument to the Steam running there
    function steamCommand(arg: string): void {
        Quickshell.execDetached([Paths.runApp, "sh", "-c", 'exec muvm -- FEXBash -c "$HOME/.local/share/fex-steam/steam-launcher/bin_steam.sh $1"', "_", arg]);
    }

    function windowsFor(entry: DesktopEntry): list<var> {
        return Hypr.toplevels.values.filter(t => entryForToplevel(t)?.id === entry.id);
    }

    function isPinned(id: string): bool {
        return adapter.pinned.includes(id);
    }

    function togglePin(id: string): void {
        adapter.pinned = isPinned(id) ? adapter.pinned.filter(p => p !== id) : [...adapter.pinned, id];
    }

    // An app installed on first use that isn't wanted: out of the dock and hidden in the launcher
    // (nothing is uninstalled; its entry belongs to taris-desktop)
    function removeStandIn(entry: DesktopEntry): void {
        adapter.pinned = adapter.pinned.filter(p => entryFor(p)?.id !== entry.id);
        const hidden = GlobalConfig.launcher.hiddenApps;
        if (!hidden.includes(entry.id))
            GlobalConfig.launcher.hiddenApps = [...hidden, entry.id];
    }

    // Focus the app's next window (cycling), or launch it when it has none; the music player's
    // workspace is shown or hidden instead
    function activate(entry: DesktopEntry): void {
        const wins = windowsFor(entry);
        if (wins.length === 0) {
            if (runsInBackground(entry))
                steamCommand("steam://open/main");
            else
                Launcher.Apps.launch(entry);
            return;
        }

        if (wins.some(w => w.workspace?.name === Hypr.musicWorkspace)) {
            Hypr.toggleMusic();
            return;
        }

        // Minimized windows come back to the current workspace first
        const minimized = wins.find(w => isMinimized(w));
        if (minimized) {
            focusWindow(minimized);
            return;
        }

        const activeIdx = wins.findIndex(w => w === Hypr.activeToplevel);
        focusWindow(wins[(activeIdx + 1) % wins.length]);
    }

    // A window, brought back first when it's minimized, focused and raised: focus alone leaves a
    // floating window under the others (as the overview does, in one batch so they go in order)
    function focusWindow(toplevel: var): void {
        const a = `address:0x${toplevel.address}`;
        const messages = [];
        if (isMinimized(toplevel)) {
            const ws = Hypr.activeWsId;
            messages.push(Hypr.usingLua ? `dispatch hl.dsp.window.move({ window = "${a}", workspace = "${ws}", follow = true })` : `dispatch movetoworkspace ${ws},${a}`);
        }
        messages.push(Hypr.usingLua ? `dispatch hl.dsp.focus({ window = "${a}" })` : `dispatch focuswindow ${a}`);
        messages.push(Hypr.usingLua ? `dispatch hl.dsp.window.alter_zorder({ window = "${a}", mode = "top" })` : `dispatch alterzorder top,${a}`);
        Hypr.extras.batchMessage(messages);
    }

    function isMinimized(toplevel: var): bool {
        return toplevel?.workspace?.name === "special:minimized";
    }

    // Hide: every window of the app into special:minimized, where the dock brings them back from
    function minimizeAll(entry: DesktopEntry): void {
        // (Not the music player: its workspace is its place, taris.lua)
        for (const w of windowsFor(entry).filter(w => !isMinimized(w) && w.workspace?.name !== Hypr.musicWorkspace)) {
            const a = `address:0x${w.address}`;
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.move({ window = "${a}", workspace = "special:minimized", follow = false })` : `movetoworkspacesilent special:minimized,${a}`);
        }
    }

    function launch(entry: DesktopEntry): void {
        Launcher.Apps.launch(entry);
    }

    function showAllWindows(): void {
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.global("taris:overviewOpen")` : "global taris:overviewOpen");
    }

    function opensAtLogin(entry: DesktopEntry): bool {
        return autostart.includes(entry.id.replace(/\.desktop$/, ""));
    }

    // Open at Login: a copy of the app's launcher in ~/.config/autostart, without the keys that
    // would hide it from the session (as the Witcher's Tweaks dock does)
    function setOpensAtLogin(entry: DesktopEntry, on: bool): void {
        const id = entry.id.replace(/\.desktop$/, "");
        autostartSet.command = ["sh", "-c", on ? 'dir="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"; for d in "${XDG_DATA_HOME:-$HOME/.local/share}/applications" /usr/local/share/applications /usr/share/applications /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do if [ -f "$d/$1.desktop" ]; then mkdir -p "$dir" && grep -v -E "^(Hidden|NoDisplay)=" "$d/$1.desktop" > "$dir/$1.desktop"; exit; fi; done; exit 1' : 'rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/$1.desktop"', "sh", id];
        autostartSet.running = true;
    }

    function refreshAutostart(): void {
        autostartGet.running = true;
    }

    function closeAll(entry: DesktopEntry): void {
        // Closing Steam's window only hides it: it's shut down instead
        if (runsInBackground(entry)) {
            steamCommand("-shutdown");
            return;
        }
        for (const w of windowsFor(entry)) {
            const addr = `address:0x${w.address}`;
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.close({ window = "${addr}" })` : `closewindow ${addr}`);
        }
    }

    onSteamInstalledChanged: {
        if (!steamInstalled)
            steamRunning = false;
    }

    Process {
        id: autostartGet

        running: true
        command: ["sh", "-c", 'ls "${XDG_CONFIG_HOME:-$HOME/.config}/autostart" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: root.autostart = text.split("\n").filter(f => f.endsWith(".desktop")).map(f => f.slice(0, -8))
        }
    }

    // trash:/// has no handler of its own (xdg-open hands it to the browser), so it goes to whatever
    // opens folders, started from its launcher's command as every app is (Launcher.Apps.launch).
    // gtk-launch asked Nautilus over D-Bus instead, and the Trash never opened
    Process {
        id: trashOpener

        command: ["xdg-mime", "query", "default", "inode/directory"]
        stdout: StdioCollector {
            onStreamFinished: {
                const entry = DesktopEntries.byId(text.trim().replace(/\.desktop$/, ""));
                Quickshell.execDetached([Paths.runApp, ...(entry?.command ?? ["nautilus"]), "trash:///"]);
            }
        }
    }

    // Steam's VM, looked for every few seconds while Steam is installed and a dock is shown (pgrep
    // reads every process's command line: about 6 ms each time, every 3 s all day otherwise). Hidden,
    // the last answer stays; a dock appearing asks again at once
    Process {
        id: steamCheck

        command: ["pgrep", "-f", "^(/usr/bin/)?muvm .*bin_steam\\.sh"]
        onExited: code => root.steamRunning = code === 0 // qmllint disable signal-handler-parameters
    }

    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.steamInstalled && root.refCount > 0
        onTriggered: steamCheck.running = true
    }

    // Qt doesn't follow the theme by itself: it's set in Qt, then the icons are read again
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "icon-theme"]
        stdout: SplitParser {
            onRead: line => {
                CUtils.setIconTheme(line.replace(/^icon-theme:\s*'?|'$/g, "").trim());
                iconReload.restart();
            }
        }
    }

    Timer {
        id: iconReload

        interval: 500
        onTriggered: {
            root.iconsClearing = true;
            CUtils.purgeImageCache();
            root.iconsClearing = false;
            root.iconRevision++;
        }
    }

    Process {
        id: autostartSet

        onExited: autostartGet.running = true
    }

    FileView {
        path: `${Paths.state}/dock.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            // Settings pinned while its windows went by Quickshell's own entry, and pins made twice
            const pins = [...new Set(adapter.pinned.map(p => p === Quickshell.appId ? root.settingsId : p))];
            if (pins.length !== adapter.pinned.length || pins.some((p, i) => p !== adapter.pinned[i]))
                adapter.pinned = pins;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter

            property list<string> pinned: []
            property bool enabled: true
            property bool showAppsButton: true
            property bool showSettings: true
            property bool showTrash: true
            property int pushTime: 40
        }
    }
}
