// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// The session's password prompt (its polkit agent): anything asking for administrator rights
// (pkexec, the Store's installs and removals…). On the focused screen, over everything, styled
// like the Settings dialogs; its window only exists while a request is waiting. The shell is the
// session's only agent: polkit-gnome isn't started any more.
Scope {
    id: root

    // The prompt's window only appears once the shell's focus grabs are gone (the Binding below
    // turns them off): Hyprland gives no keyboard focus to a surface outside an active grab, and
    // doesn't hand it over when the grab ends, so a prompt that appeared over an open panel or the
    // settings could never be typed in
    property bool grabsGone

    Binding {
        target: ShellState
        property: "authenticating"
        value: agent.isActive
    }

    PolkitAgent {
        id: agent

        onIsActiveChanged: {
            root.grabsGone = false;
            if (isActive)
                grabsGoneTimer.restart();
            else
                grabsGoneTimer.stop();
        }
        onIsRegisteredChanged: {
            if (!isRegistered)
                console.warn("Polkit: another authentication agent is registered; this one isn't in use");
        }
    }

    Timer {
        id: grabsGoneTimer

        interval: 100
        onTriggered: root.grabsGone = true
    }

    LazyLoader {
        active: agent.isActive && agent.flow !== null && root.grabsGone

        StyledWindow {
            id: win

            readonly property AuthFlow flow: agent.flow
            // faillock's notice that the account is locked (why, and the time left): two info
            // messages, shown like an error
            property string lockMessage

            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
            name: "polkit"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Each request (they queue: the next one reuses this window): an empty field, and this
            // user to authenticate as when polkit picked someone else (it lists every admin and
            // picks the first). Only then: changing the identity aborts the conversation polkit
            // already started, which PAM counts as a failed login (faillock locks the account after
            // a few), so it must never happen when this user is already the one picked.
            function startRequest(): void {
                password.text = "";
                lockMessage = "";
                dialog.pendingSubmit = false;
                const me = Quickshell.env("USER");
                const picked = flow?.selectedIdentity ?? null;
                if (flow && me && !(picked && !picked.isGroup && picked.string === me)) {
                    const ids = flow.identities ?? [];
                    for (let i = 0; i < ids.length; i++) {
                        if (!ids[i].isGroup && ids[i].string === me) {
                            flow.selectedIdentity = ids[i];
                            break;
                        }
                    }
                }
                password.forceActiveFocus();
            }

            Component.onCompleted: startRequest()
            onFlowChanged: {
                if (flow)
                    startRequest();
            }

            StyledRect {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3scrim, 0.5)
                opacity: dialog.opacity
            }

            Item {
                id: dialog

                // Enter pressed before polkit asked: sent as soon as it does
                property bool pendingSubmit

                function submit(): void {
                    if (password.text.length === 0)
                        return;
                    if (win.flow?.isResponseRequired) {
                        pendingSubmit = false;
                        win.lockMessage = "";
                        win.flow.submit(password.text);
                    } else {
                        pendingSubmit = true;
                    }
                }

                anchors.centerIn: parent
                width: Math.min(parent.width * 0.9, 460)
                height: layout.implicitHeight + Tokens.padding.extraLarge * 2

                opacity: 0
                scale: 0.9
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }

                // Esc anywhere in the dialog cancels
                Keys.onEscapePressed: win.flow?.cancelAuthenticationRequest()

                Connections {
                    function onIsResponseRequiredChanged(): void {
                        if (!win.flow?.isResponseRequired)
                            return;
                        password.forceActiveFocus();
                        if (dialog.pendingSubmit)
                            dialog.submit();
                    }

                    function onSupplementaryMessageChanged(): void {
                        const message = String(win.flow?.supplementaryMessage ?? "");
                        if (message.startsWith("The account is locked"))
                            win.lockMessage = message;
                        else if (win.lockMessage && message.endsWith(" left to unlock)"))
                            win.lockMessage += " " + message;
                    }

                    // A wrong password: empty again for the next try
                    function onAuthenticationFailed(): void {
                        password.text = "";
                        dialog.pendingSubmit = false;
                        password.forceActiveFocus();
                    }

                    target: win.flow
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Behavior on scale {
                    Anim {}
                }

                Elevation {
                    anchors.fill: parent
                    radius: bg.radius
                    level: 4
                }

                StyledRect {
                    id: bg

                    anchors.fill: parent
                    radius: Tokens.rounding.extraLargeIncreased
                    color: Colours.tPalette.m3surface // The windows' background, as Settings and the Store have
                }

                ColumnLayout {
                    id: layout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.extraLarge
                    anchors.bottomMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.large

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.large

                        StyledRect {
                            implicitWidth: implicitHeight
                            implicitHeight: lockIcon.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3secondaryContainer

                            MaterialIcon {
                                id: lockIcon

                                anchors.centerIn: parent
                                text: "lock"
                                color: Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.large
                                fill: 1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Tr.tr("Authentication required")
                            font: Tokens.font.title.builders.large.weight(Font.Normal).build()
                            wrapMode: Text.Wrap
                        }
                    }

                    StyledTextField {
                        id: password

                        Layout.fillWidth: true
                        // Typing goes here from the start; it stays editable and focused even
                        // while polkit isn't asking (it's starting, or checking a password)
                        focus: true
                        leadingIcon: "password"
                        placeholderText: String(win.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || Tr.tr("Password")
                        echoMode: win.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                        isError: win.lockMessage !== "" || (win.flow?.supplementaryIsError ?? false)
                        // Only what went wrong (a wrong password, a locked account)
                        errorText: win.lockMessage || (win.flow?.supplementaryIsError ? win.flow.supplementaryMessage : "")

                        onAccepted: dialog.submit()
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Tokens.spacing.extraSmall

                        TextButton {
                            type: TextButton.Text
                            isRound: true
                            horizontalPadding: Tokens.padding.largeIncreased
                            verticalPadding: Tokens.padding.medium
                            text: Tr.trCtx("Cancel", "button")
                            onClicked: win.flow?.cancelAuthenticationRequest()
                        }

                        TextButton {
                            type: TextButton.Text
                            isRound: true
                            horizontalPadding: Tokens.padding.largeIncreased
                            verticalPadding: Tokens.padding.medium
                            disabled: password.text.length === 0 || dialog.pendingSubmit
                            text: Tr.tr("Authenticate")
                            onClicked: dialog.submit()
                        }
                    }
                }
            }
        }
    }
}
