// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// The notice the power panel's Stash button shows first (Stash.request): Stash is a work in
// progress. On the focused screen, over everything, styled like the Settings dialogs, as the
// password prompt is (polkit/Polkit.qml).
Scope {
    id: root

    // The window only appears once the power panel's focus grab is gone: Hyprland gives no keyboard
    // focus to a surface outside an active grab, and doesn't hand it over when the grab ends
    property bool grabsGone

    Connections {
        function onConfirmingChanged(): void {
            root.grabsGone = false;
            if (Stash.confirming)
                grabsGoneTimer.restart();
            else
                grabsGoneTimer.stop();
        }

        target: Stash
    }

    Timer {
        id: grabsGoneTimer

        interval: 100
        onTriggered: root.grabsGone = true
    }

    LazyLoader {
        active: Stash.confirming && root.grabsGone

        StyledWindow {
            id: win

            property bool dontShowAgain

            function proceed(): void {
                if (dontShowAgain)
                    GlobalConfig.session.stashNotice = false;
                Stash.confirming = false;
                Stash.stash();
            }

            function cancel(): void {
                Stash.confirming = false;
            }

            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
            name: "stash-notice"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            StyledRect {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3scrim, 0.5)
                opacity: dialog.opacity
            }

            Item {
                id: dialog

                anchors.centerIn: parent
                width: Math.min(parent.width * 0.9, 520)
                height: layout.implicitHeight + Tokens.padding.extraLarge * 2

                focus: true
                opacity: 0
                scale: 0.9
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                    forceActiveFocus();
                }

                Keys.onEscapePressed: win.cancel()
                Keys.onReturnPressed: win.proceed()
                Keys.onEnterPressed: win.proceed()

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
                            implicitHeight: stashIcon.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3secondaryContainer

                            MaterialIcon {
                                id: stashIcon

                                anchors.centerIn: parent
                                text: GlobalConfig.session.icons.stash
                                color: Colours.palette.m3onSecondaryContainer
                                fontStyle: Tokens.font.icon.large
                                fill: 1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Tr.tr("Stash is a work in progress")
                            font: Tokens.font.title.builders.large.weight(Font.Normal).build()
                            wrapMode: Text.Wrap
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Stash tries to keep every app and its data from your session, but some apps might lose their data.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        // The tick box: never show this notice again
                        Item {
                            implicitWidth: tickRow.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: tickRow.implicitHeight + Tokens.padding.small * 2

                            StateLayer {
                                radius: Tokens.rounding.full
                                onClicked: win.dontShowAgain = !win.dontShowAgain
                            }

                            RowLayout {
                                id: tickRow

                                anchors.centerIn: parent
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: win.dontShowAgain ? "check_box" : "check_box_outline_blank"
                                    color: win.dontShowAgain ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.medium
                                    fill: win.dontShowAgain ? 1 : 0
                                }

                                StyledText {
                                    text: Tr.tr("Don't show this again")
                                    font: Tokens.font.body.medium
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        TextButton {
                            type: TextButton.Text
                            isRound: true
                            horizontalPadding: Tokens.padding.largeIncreased
                            verticalPadding: Tokens.padding.medium
                            text: Tr.trCtx("Cancel", "button")
                            onClicked: win.cancel()
                        }

                        TextButton {
                            type: TextButton.Text
                            isRound: true
                            horizontalPadding: Tokens.padding.largeIncreased
                            verticalPadding: Tokens.padding.medium
                            text: Tr.tr("Understood")
                            onClicked: win.proceed()
                        }
                    }
                }
            }
        }
    }
}
