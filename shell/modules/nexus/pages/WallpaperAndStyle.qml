// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Taris
import Taris.Components
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // The icons (GTK's icon theme, which Qt apps and the shell follow too, each the next time it
    // starts): a pack that isn't installed is installed first, in the background as apps installed
    // on first use are (services/OnDemandInstaller), with the shell's password prompt. The dark
    // variants, as Papirus-Dark was always set. Each pack is set as taris-desktop's Taris-<pack>
    // theme (value), the pack (dir) falling back to the others: an app with no icon in the pack nor
    // one of its own (one installed on first use, Tor Browser) shows another pack's.
    readonly property var iconThemes: [
        {
            value: "Taris-Papirus-Dark",
            dir: "Papirus-Dark",
            label: "Papirus",
            pkg: "papirus-icon-theme"
        },
        {
            value: "Taris-Adwaita",
            dir: "Adwaita",
            label: "Adwaita",
            pkg: "adwaita-icon-theme"
        },
        {
            value: "Taris-breeze-dark",
            dir: "breeze-dark",
            label: "Breeze",
            pkg: "breeze-icons"
        },
        {
            value: "Taris-Tela-dark",
            dir: "Tela-dark",
            label: "Tela",
            pkg: "tela-icon-theme"
        },
        {
            value: "Taris-WhiteSur-dark",
            dir: "WhiteSur-dark",
            label: "WhiteSur",
            pkg: "whitesur-icon-theme"
        },
        {
            value: "Taris-Fluent-dark",
            dir: "Fluent-dark",
            label: "Fluent",
            pkg: "fluent-icon-theme-git"
        }
    ]
    // Set: a pack set by itself (before the Taris-<pack> themes) shows as that pack too
    readonly property string iconChoice: iconThemes.find(t => t.value === iconTheme || t.dir === iconTheme)?.value ?? iconTheme
    property string iconTheme
    // Set until the dock has read its icons from the new pack
    property bool iconsWaiting
    property Connections _iconsDone: Connections {
        function onIconRevisionChanged(): void {
            root.iconsWaiting = false;
        }

        target: Dock
    }

    property Process _iconsGet: Process {
        command: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.iconTheme = text.trim().replace(/^'|'$/g, "")
        }
    }

    // Read again once it's set (or the install failed or was cancelled: 126 and 127 are the password
    // prompt cancelled or refused)
    property Process _iconsSet: Process {
        property string label

        stderr: StdioCollector {}
        onExited: code => {
            root._iconsGet.running = true;
            if (code !== 0)
                root.iconsWaiting = false;
            if (code !== 0 && code !== 126 && code !== 127) {
                const errors = root._iconsSet.stderr.text.split("\n").filter(l => l.startsWith("error:")).slice(0, 3).map(l => l.slice(6).trim());
                Toaster.toast(Tr.tr("%1 couldn't be installed").arg(root._iconsSet.label), errors.join("\n"), "error", Toast.Error);
            }
        }
    }

    // As the App Store installs: the freshest mirrors first (no password), then pacman, with the
    // system's pending updates
    function setIconTheme(theme: string): void {
        const pack = iconThemes.find(t => t.value === theme);
        if (!pack || theme === iconChoice)
            return;
        iconsWaiting = true;
        _iconsSet.label = pack.label;
        _iconsSet.command = ["sh", "-c", '[ -d "/usr/share/icons/$3" ] || { pkexec /usr/lib/taris/mirrors && pkexec pacman -Syu --needed --noconfirm "$2"; } || exit; exec gsettings set org.gnome.desktop.interface icon-theme "$1"', "sh", theme, pack.pkg, pack.dir];
        _iconsSet.running = true;
    }

    title: Tr.tr("Wallpaper & style")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Tr.tr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: Wallpapers.current
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: Tr.tr("Wallpapers")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: Tr.tr("Colours")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            first: true
            text: Tr.tr("Display wallpaper")
            checked: Config.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: Tr.tr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        ChoiceRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            last: true
            label: Tr.tr("Icons")
            options: root.iconThemes
            current: root.iconChoice
            enabled: !root._iconsSet.running
            // While a pack is installed or set
            busy: root._iconsSet.running || root.iconsWaiting
            onChosen: v => root.setIconTheme(v)
        }
    }
}
