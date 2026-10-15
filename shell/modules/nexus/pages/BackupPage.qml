// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Backups of the whole system (/usr/lib/taris/backup, as root through pkexec: the apps, packages,
// settings and every account's files, at most 20), made now or on a schedule and restored at the
// next start; and the factory reset. The list is the helper's (/var/lib/taris/backups.json).
PageBase {
    id: root

    // Newest first: { id: "YYYYmmdd-HHMMSS", kind: "manual" | "automatic" }
    property var backups: []
    property string schedule: "off"
    // The system as installed is there to go back to (TarisOS images)
    property bool hasFactory
    // The backup a first click on Restore armed; the second restores
    property string restoreArmed

    property FileView _index: FileView {
        id: index

        path: "/var/lib/taris/backups.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.schedule = data.schedule ?? "off";
                root.backups = (data.backups ?? []).slice().reverse();
            } catch (e) {}
        }
    }

    property Process _backup: Process {
        id: backup

        onExited: index.reload()
    }

    property Process _factoryCheck: Process {
        running: true
        command: ["test", "-e", "/etc/taris/factory"]
        onExited: code => root.hasFactory = code === 0 // qmllint disable signal-handler-parameters
    }

    property Process _factoryReset: Process {
        id: factoryReset

        command: ["pkexec", "/usr/lib/taris/factory-reset"]
    }

    property Timer _restoreDisarm: Timer {
        id: restoreDisarm

        interval: 5000
        onTriggered: root.restoreArmed = ""
    }

    function run(args: list<string>): void {
        backup.command = ["pkexec", "/usr/lib/taris/backup", ...args];
        backup.running = true;
    }

    function dateOf(id: string): date {
        return new Date(+id.slice(0, 4), +id.slice(4, 6) - 1, +id.slice(6, 8), +id.slice(9, 11), +id.slice(11, 13), +id.slice(13, 15));
    }

    title: Tr.tr("Backup & restore")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Backups")
        }

        RowButton {
            first: true
            last: root.backups.length === 0
            icon: "backup"
            text: Tr.tr("Back up now")
            disabled: backup.running
            onClicked: root.run(["create"])
        }

        Repeater {
            model: root.backups

            BackupRow {}
        }

        SectionHeader {
            text: Tr.tr("Automatic backups")
        }

        ToggleRow {
            first: true
            last: root.schedule === "off"
            text: Tr.tr("Automatic backups")
            checked: root.schedule !== "off"
            onToggled: root.run(["schedule", checked ? "daily" : "off"])
        }

        ChoiceRow {
            visible: root.schedule !== "off"
            last: true
            icon: "schedule"
            label: Tr.tr("How often")
            options: [
                {
                    value: "daily",
                    label: Tr.tr("Every day")
                },
                {
                    value: "weekly",
                    label: Tr.tr("Every week")
                },
                {
                    value: "monthly",
                    label: Tr.tr("Every month")
                }
            ]
            current: root.schedule
            onChosen: v => root.run(["schedule", v])
        }

        SectionHeader {
            visible: root.hasFactory
            text: Tr.tr("Factory reset")
        }

        DialogRowButton {
            visible: root.hasFactory
            rootParent: root.flickable
            icon: "restore"
            label: Tr.tr("Erase everything")
            header: Tr.tr("Erase everything?")
            acceptLabel: Tr.tr("Erase everything")
            content: StyledText {
                text: Tr.tr("Every account, file, app and backup on this Mac will be deleted, and TarisOS will be as it was when it was installed. The Mac restarts to do it.")
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }
            onAccepted: factoryReset.running = true
        }
    }

    // One backup: when it was made, how, and Restore (a second click restarts into it) and Delete
    component BackupRow: ConnectedRect {
        id: row

        required property var modelData
        required property int index
        readonly property bool armed: root.restoreArmed === modelData.id

        Layout.fillWidth: true
        last: index === root.backups.length - 1
        implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2

        RowLayout {
            id: rowLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.small

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.dateOf(row.modelData.id).toLocaleString(Qt.locale(), Locale.ShortFormat)
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.kind === "automatic" ? Tr.trCtx("Automatic", "backup made on a schedule") : Tr.trCtx("Manual", "backup made by the user")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            TextButton {
                type: row.armed ? TextButton.Filled : TextButton.Tonal
                disabled: backup.running
                text: row.armed ? Tr.tr("Click again to restore and restart") : Tr.trCtx("Restore", "button")
                onClicked: {
                    if (row.armed) {
                        restoreDisarm.stop();
                        root.run(["restore", row.modelData.id]);
                    } else {
                        root.restoreArmed = row.modelData.id;
                        restoreDisarm.restart();
                    }
                }
            }

            IconButton {
                icon: "delete"
                type: IconButton.Text
                disabled: backup.running
                onClicked: root.run(["delete", row.modelData.id])
            }
        }
    }
}
