// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import "lock"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Taris.Config
import Taris.Services
import qs.services

Scope {
    id: root

    required property Lock lock
    // logind announced sleep and waits for the session to lock (SessionManager.delaySleep)
    property bool sleepPending
    readonly property bool hasPlayer: Players.list.some(p => p.isPlaying)
    readonly property bool isCharging: !UPower.onBattery
    readonly property bool enabled: {
        if (GlobalConfig.general.idle.inhibitWhenAudio && hasPlayer)
            return false;
        if (GlobalConfig.general.idle.inhibitWhenCharging && isCharging)
            return false;
        return true;
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            lock.lock.locked = true;
        else if (action === "unlock")
            lock.lock.locked = false;
        else if (typeof action === "string")
            Hypr.dispatch(Hypr.usingLua && ["dpms off", "dpms on"].includes(action) ? `hl.dsp.dpms({ action = "${action === "dpms off" ? "disable" : "enable"}" })` : action);
        else if (!SessionManager.exec(action))
            Quickshell.execDetached(action);
    }

    Connections {
        function onAboutToSleep(): void {
            if (!GlobalConfig.general.idle.lockBeforeSleep)
                return;
            root.lock.lock.locked = true;
            if (root.lock.lock.secure)
                SessionManager.allowSleep();
            else
                root.sleepPending = true;
        }

        function onResumed(): void {
            root.sleepPending = false;
        }

        function onLockRequested(): void {
            root.lock.lock.locked = true;
        }

        function onUnlockRequested(): void {
            root.lock.lock.unlock();
        }

        target: SessionManager
    }

    // Sleep goes ahead once the compositor has the lock screen up on every screen
    Connections {
        function onSecureStateChanged(): void {
            if (root.sleepPending && root.lock.lock.secure) {
                root.sleepPending = false;
                SessionManager.allowSleep();
            }
        }

        target: root.lock.lock
    }

    // The machine doesn't sleep before the session is locked: logind waits for it (up to its
    // InhibitDelayMaxSec, raised to 15 s by taris-desktop)
    Binding {
        target: SessionManager
        property: "delaySleep"
        value: GlobalConfig.general.idle.lockBeforeSleep
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts.values

        IdleMonitor {
            required property var modelData

            enabled: {
                if (!root.enabled || !(modelData.enabled ?? true))
                    return false;
                if (modelData.inhibitWhenAudio && root.hasPlayer)
                    return false;
                if (modelData.inhibitWhenCharging && root.isCharging)
                    return false;
                return true;
            }
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
