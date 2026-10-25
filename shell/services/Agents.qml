// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Taris.Config
import qs.utils

// Coding agents for the dashboard's Agent tab: which one is the default, and its usage (plan and
// rate limits). Ported from the Witcher's Tweaks agent panel; the usage collectors are bundled
// (assets/agent).
Singleton {
    id: root

    // The agents Settings > Apps > Agent offers, in its order
    readonly property var list: [
        { id: "claude", name: "Claude Code" },
        { id: "codex", name: "Codex" },
        { id: "agy", name: "Antigravity" },
        { id: "copilot", name: "GitHub Copilot" },
        { id: "crush", name: "Crush" },
        { id: "grok", name: "Grok" },
        { id: "hermes", name: "Hermes" },
        { id: "omp", name: "Oh My Pi" },
        { id: "opencode", name: "OpenCode" },
        { id: "ori", name: "Ori" },
        { id: "pi", name: "Pi" }
    ]
    // Agents with a bundled usage collector (assets/agent/usage-<id>.py)
    readonly property var tracked: ["claude", "codex"]

    readonly property string scriptDir: `${Quickshell.shellDir}/assets/agent`
    readonly property string usageDir: `${Paths.state}/agents/usage`
    readonly property string defaultAgent: GlobalConfig.general.apps.agent

    // Usage records by agent id (what the collectors write)
    property var records: ({})
    // The records are watched through their folder, which a watch can't follow until it exists: on
    // a new account's first login the collector only makes it later, and its records went unseen
    property bool usageDirReady
    readonly property var usage: records[defaultAgent] ?? null

    // Collectors only run once the tab has been shown (they scan transcripts)
    property bool active

    // Installed agents (checkInstalled refreshes it; assets/agent/install.sh knows how to tell)
    property var installed: []

    function nameOf(id: string): string {
        return list.find(a => a.id === id)?.name ?? (id || "Agent");
    }

    function iconOf(id: string): string {
        if (!tracked.includes(id))
            return "";
        return Qt.resolvedUrl(`${scriptDir}/icons/${id}${id === "codex" && Colours.light ? "-light" : ""}.svg`);
    }

    function checkInstalled(): void {
        if (!installedCheck.running)
            installedCheck.running = true;
    }

    // Make it the default, and install it first when it isn't (in a terminal)
    function pick(id: string): void {
        setDefault(id);
        pickCheck.agent = id;
        pickCheck.running = true;
    }

    function setDefault(id: string): void {
        GlobalConfig.general.apps.agent = id;
    }

    // Opening the tab wants the numbers that go stale on the wire, not another scan of every
    // transcript: the collectors reuse their recent scans in this mode. At most once a minute:
    // each run starts Python and asks the agent's servers, and switching tabs shows it again
    property real limitsCheckedAt
    function refreshLimits(): void {
        active = true;
        if (Date.now() - limitsCheckedAt < 60000)
            return;
        limitsCheckedAt = Date.now();
        run(["--limits-only"]);
    }

    function refresh(): void {
        active = true;
        run(["--force"]);
    }

    property var queued: null

    function run(flags: var, ids: var): void {
        const agents = (ids ?? [defaultAgent]).filter(id => tracked.includes(id));
        if (agents.length === 0)
            return;
        // The tab only shows the plan and the limits: --no-stats skips totalling the transcripts
        const command = [`${scriptDir}/usage-update.sh`, "--no-stats", ...flags, ...agents];
        if (updater.running) {
            queued = command;
            return;
        }
        updater.command = command;
        updater.running = true;
    }

    // A collector that couldn't reach its limits endpoint (the seconds after login before the
    // network is up) sets retryAdvised: try that one again sooner than the full interval
    function scheduleRetry(): void {
        const advising = tracked.filter(id => records[id]?.retryAdvised === true);
        retryTimer.ids = advising;
        if (advising.length > 0)
            retryTimer.restart();
        else
            retryTimer.stop();
    }

    onDefaultAgentChanged: {
        if (active)
            run([]);
    }

    Process {
        id: installedCheck

        command: [`${root.scriptDir}/install.sh`, "--installed"]
        stdout: StdioCollector {
            onStreamFinished: root.installed = text.split("\n").filter(id => id)
        }
    }

    Process {
        id: pickCheck

        property string agent

        command: [`${root.scriptDir}/install.sh`, "--check", agent]
        onExited: exitCode => {
            if (exitCode !== 0)
                Quickshell.execDetached([Paths.runApp, ...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, `${root.scriptDir}/install.sh`, agent, root.nameOf(agent)]);
        }
    }

    Process {
        id: updater

        onExited: {
            if (root.queued) {
                command = root.queued;
                root.queued = null;
                running = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("Agents:", text.trim());
            }
        }
    }

    Timer {
        interval: 15 * 60 * 1000
        running: root.active
        repeat: true
        onTriggered: root.run([])
    }

    Timer {
        id: retryTimer

        property var ids: []

        interval: 30000
        onTriggered: root.run(["--limits-only"], ids)
    }

    // An agent that isn't signed in yet, or whose saved sign-in has expired, names the file signing
    // in writes (authFile): collect again as soon as it changes, so the limits show seconds after
    // signing in, or after the agent refreshes its sign-in, rather than at the next regular run. Its
    // modification time is looked at, never what it holds.
    Instantiator {
        model: ScriptModel {
            values: root.active ? root.tracked.filter(id => typeof root.records[id]?.authFile === "string") : []
        }

        Scope {
            id: authWatch

            required property string modelData
            readonly property string file: root.records[authWatch.modelData]?.authFile ?? ""
            // Its modification time when last looked at ("" while it doesn't exist)
            property var seen: null

            Timer {
                interval: 3000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: {
                    if (!authStat.running)
                        authStat.running = true;
                }
            }

            Process {
                id: authStat

                command: ["stat", "-L", "-c", "%.9Y", authWatch.file]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const mtime = text.trim();
                        // Start from the time the collector saw when it read the file
                        // (authFileMtime), so a change made before this first look still counts:
                        // the Agent tab starts the agent, which refreshes its sign-in, at the same
                        // moment it collects
                        if (authWatch.seen === null)
                            authWatch.seen = root.records[authWatch.modelData]?.authFileMtime ?? mtime;
                        if (mtime !== authWatch.seen) {
                            authWatch.seen = mtime;
                            root.run(["--limits-only"], [authWatch.modelData]);
                        }
                    }
                }
            }
        }
    }

    Process {
        command: ["mkdir", "-p", root.usageDir]
        running: true
        onExited: root.usageDirReady = true
    }

    Instantiator {
        model: root.tracked

        FileView {
            required property string modelData

            path: root.usageDirReady ? `${root.usageDir}/${modelData}.json` : ""
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: {
                try {
                    const map = Object.assign({}, root.records);
                    map[modelData] = JSON.parse(text());
                    root.records = map;
                    root.scheduleRetry();
                } catch (e) {
                    console.warn("Agents: ignoring bad usage record", path, e);
                }
            }
        }
    }
}
