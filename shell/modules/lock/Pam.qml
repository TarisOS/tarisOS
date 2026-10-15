// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Greetd
import Taris.Config
import Taris.Services
import qs.utils

Scope {
    id: root

    enum PamState {
        None,
        Error,
        MaxTries,
        Failed
    }

    required property WlSessionLock lock

    // The greeter (greeter.qml): the same screen logs a user in through greetd instead of
    // unlocking, with the password only (no face). The user's session starts once
    // the password is right.
    property bool greeter
    property string user: Quickshell.env("USER") ?? ""
    property list<string> sessionCommand: ["start-hyprland"]
    property list<string> sessionEnv: ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=Hyprland", "XDG_CURRENT_DESKTOP=Hyprland"]
    property bool greeterBusy
    property string greeterError
    // The accounts the greeter offers ({ name, realName }); Up and Down switch between them
    property list<var> users: []
    readonly property string userRealName: users.find(u => u.name === user)?.realName || user
    // The account picture: the user's ~/.face (the greeter's copy of it, for the greeter)
    readonly property string facePath: greeter ? `${GreeterPaths.faces}/${user}` : `${Paths.home}/.face`

    readonly property alias passwd: passwd
    readonly property alias howdy: howdy
    // A password being checked (or the greeter starting the session)
    readonly property bool busy: greeter ? greeterBusy : passwd.active
    readonly property string errorMessage: greeter ? greeterError : passwd.message

    property string lockMessage
    property int state
    property string buffer

    signal flashMsg
    signal loggedIn

    // The greeter: the next or previous account; what was typed and said goes with the old one
    function switchUser(step: int): void {
        if (busy || users.length < 2)
            return;
        const i = users.findIndex(u => u.name === user);
        user = users[((i < 0 ? 0 : i) + step + users.length) % users.length].name;
        buffer = "";
        lockMessage = "";
        clearTransientState();
    }

    // Checks the password typed (Enter, or the arrow button)
    function submit(): void {
        // An empty password is never sent: it would only count as a failed attempt (faillock)
        if (busy || buffer.length === 0)
            return;
        // A lockout message is about the attempt it came with: a new one gets its own
        lockMessage = "";
        if (!greeter) {
            passwd.start();
            return;
        }
        if (!user)
            return;
        if (!Greetd.available) {
            greeterError = "greetd isn't running";
            failed(PamResult.Error);
            return;
        }
        greeterError = "";
        greeterBusy = true;
        Greetd.createSession(user);
    }

    function handleKey(event: KeyEvent): void {
        if (busy)
            return;

        // Trigger howdy on enter while empty buffer
        if (howdy.canAttempt && !howdy.active && (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && buffer.length === 0)
            return howdy.start(); // Gate on active so double enter still allows empty password

        if (state === Pam.MaxTries)
            return;

        if (greeter && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            switchUser(event.key === Qt.Key_Up ? -1 : 1);
            return;
        }

        // Abort howdy on pwd input
        if (howdy.active)
            howdy.abort();

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            submit();
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier) {
                buffer = "";
            } else {
                buffer = buffer.slice(0, -1);
            }
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            // Allow anything except control characters
            buffer += event.text;
        }
    }

    function clearTransientState(): void {
        for (const obj of [root, howdy])
            if (obj.state !== Pam.MaxTries)
                obj.state = Pam.None;
    }

    // faillock's lockout notice comes in two messages: that the account is locked (and why), then
    // the time left
    function noteMessage(message: string): void {
        if (message.startsWith("The account is locked"))
            lockMessage = message;
        else if (lockMessage && message.endsWith(" left to unlock)"))
            lockMessage += "\n" + message;
    }

    function failed(result: int): void {
        clearTransientState();
        if (result === PamResult.Error)
            state = Pam.Error;
        else if (result === PamResult.MaxTries)
            state = Pam.MaxTries;
        else
            state = Pam.Failed;
        flashMsg();
        pwdStateReset.restart();
    }

    // greetd's side of a login (the greeter only)
    Connections {
        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (responseRequired) {
                Greetd.respond(root.buffer);
                root.buffer = "";
            } else {
                root.noteMessage(message);
            }
        }

        function onAuthFailure(message: string): void {
            root.greeterBusy = false;
            root.buffer = "";
            root.failed(PamResult.Failed);
        }

        function onReadyToLaunch(): void {
            root.loggedIn();
            Greetd.launch(root.sessionCommand, root.sessionEnv, true);
        }

        function onError(error: string): void {
            root.greeterBusy = false;
            root.greeterError = error;
            root.failed(PamResult.Error);
        }

        target: root.greeter ? Greetd : null
    }

    PamContext {
        id: passwd

        config: "passwd"
        configDirectory: Quickshell.shellPath("assets/pam.d")

        onMessageChanged: root.noteMessage(message)

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;

            respond(root.buffer);
            root.buffer = "";
        }

        onCompleted: res => {
            if (res === PamResult.Success)
                return root.lock.unlock();
            root.failed(res);
        }
    }

    Timer {
        id: pwdStateReset

        interval: 4000
        onTriggered: {
            if (root.state !== Pam.MaxTries)
                root.state = Pam.None;
        }
    }

    ManualPamContext {
        id: howdy

        config: "howdy"
        availCommand: ["sh", "-c", "command -v howdy"]
        enabled: GlobalConfig.lock.enableHowdy && !root.greeter
        maxTries: GlobalConfig.lock.maxHowdyTries
    }

    Connections {
        function onResumed(): void {
            if (howdy.canAttempt && !howdy.active && GlobalConfig.lock.triggerHowdyOnWake)
                howdy.start();
        }

        target: SessionManager
    }

    Connections {
        function onSecureChanged(): void {
            if (root.lock.secure) {
                howdy.checkAvailable();
                howdy.reset();
                root.buffer = "";
                root.state = Pam.None;
                root.lockMessage = "";
            }
        }

        function onUnlock(): void {
            howdy.abort();
            passwd.abort();
        }

        target: root.lock
    }

    Connections {
        function onEnableHowdyChanged(): void {
            if (!GlobalConfig.lock.enableHowdy && howdy.active)
                howdy.abort();
        }

        target: GlobalConfig.lock
    }

    component ManualPamContext: Scope {
        id: ctx

        required property bool enabled
        required property int maxTries
        property alias config: pam.config
        property alias availCommand: availProc.command

        property bool available
        property int tries
        property int errorTries
        property int state
        readonly property bool canAttempt: available && enabled && root.lock.secure && tries < maxTries

        readonly property alias active: pam.active
        readonly property alias message: pam.message

        function checkAvailable(): void {
            availProc.running = true;
        }

        function start(): void {
            pam.start();
        }

        function abort(): void {
            pam.abort();
        }

        function reset(): void {
            tries = 0;
            errorTries = 0;
            state = Pam.None;
        }

        PamContext {
            id: pam

            configDirectory: Quickshell.shellPath("assets/pam.d")

            onCompleted: res => {
                if (!ctx.available)
                    return;

                if (res === PamResult.Success)
                    return root.lock.unlock();

                root.clearTransientState();

                if (res === PamResult.Error) {
                    ctx.state = Pam.Error;
                    ctx.errorTries++;
                    if (ctx.errorTries < 5) {
                        abort();
                        errorRetry.restart();
                    }
                } else if (res === PamResult.MaxTries || res === PamResult.Failed) {
                    ctx.tries++;
                    if (ctx.tries < ctx.maxTries) {
                        ctx.state = Pam.Failed;
                    } else {
                        ctx.state = Pam.MaxTries;
                        abort();
                    }
                }

                root.flashMsg();
                stateReset.restart();
            }
        }

        Timer {
            id: errorRetry

            interval: 800
            onTriggered: pam.start()
        }

        Timer {
            id: stateReset

            interval: 4000
            onTriggered: {
                if (ctx.state !== Pam.MaxTries)
                    ctx.state = Pam.None;
                ctx.errorTries = 0;
            }
        }

        Process {
            id: availProc

            onExited: code => ctx.available = code === 0 // qmllint disable signal-handler-parameters
        }
    }
}
