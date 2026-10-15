// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.modules.nexus.common

// Power: profile, idle timeouts (lock, screen off, suspend), sleep and battery behaviour
PageBase {
    id: root

    // Where charging stops (the battery's charge limit, in percent; 0: no such setting here). The
    // wheel group may set it (taris-hardware's udev rule); Asahi keeps it across reboots.
    readonly property string chargeLimitPath: "/sys/class/power_supply/macsmc-battery/charge_control_end_threshold"
    property int chargeLimit

    property FileView _chargeLimitFile: FileView {
        id: chargeLimitFile

        path: root.chargeLimitPath
        printErrors: false
        // (The switch shows what the battery says, also after a write that didn't take)
        onLoaded: {
            root.chargeLimit = parseInt(text()) || 0;
            chargeLimitToggle.checked = root.chargeLimit > 0 && root.chargeLimit < 100;
        }
        onLoadFailed: root.chargeLimit = 0
    }

    property Process _chargeLimitSet: Process {
        id: chargeLimitSet

        onExited: chargeLimitFile.reload()
    }

    function actionName(action: var): string {
        const a = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        if (a === "lock")
            return Tr.tr("Lock the screen");
        if (a.includes("dpms") || a.includes("off"))
            return Tr.tr("Turn the screen off");
        if (a.includes("suspend"))
            return Tr.tr("Suspend");
        return a || Tr.tr("Idle action");
    }

    title: Tr.tr("Power")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Power profile")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: [
                    { profile: PowerProfile.PowerSaver, label: Tr.tr("Power saver") },
                    { profile: PowerProfile.Balanced, label: Tr.tr("Balanced") },
                    { profile: PowerProfile.Performance, label: Tr.tr("Performance") }
                ].filter(p => p.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

                TextButton {
                    required property var modelData

                    Layout.fillWidth: true
                    type: TextButton.Tonal
                    isToggle: true
                    checked: PowerProfiles.profile === modelData.profile
                    text: modelData.label
                    onClicked: PowerProfiles.profile = modelData.profile
                }
            }
        }

        SectionHeader {
            text: Tr.tr("When idle")
        }

        Repeater {
            model: GlobalConfig.general.idle.timeouts.values

            ColumnLayout {
                id: timeout

                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                ToggleRow {
                    first: timeout.index === 0
                    text: root.actionName(timeout.modelData.idleAction)
                    subtext: Tr.tr("After %1 idle minutes").arg(Math.round(timeout.modelData.timeout / 60))
                    checked: timeout.modelData.enabled
                    onToggled: timeout.modelData.enabled = checked
                }

                ChoiceRow {
                    readonly property int minutes: Math.round(timeout.modelData.timeout / 60)

                    last: timeout.index === GlobalConfig.general.idle.timeouts.values.length - 1
                    label: Tr.tr("After")
                    options: [...new Set([1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, minutes])].sort((a, b) => a - b).map(m => ({
                                value: m,
                                label: m % 60 === 0 ? Tr.tr("%1 h").arg(m / 60) : Tr.tr("%1 min").arg(m)
                            }))
                    current: minutes
                    onChosen: v => timeout.modelData.timeout = v * 60
                }
            }
        }

        SectionHeader {
            text: Tr.tr("Power button")
        }

        ChoiceRow {
            first: true
            last: true
            icon: "power_settings_new"
            label: Tr.tr("When pressed")
            options: [
                {
                    value: "lock",
                    label: Tr.tr("Lock the screen")
                },
                {
                    value: "sleep",
                    label: Tr.tr("Sleep")
                },
                {
                    value: "poweroff",
                    label: Tr.tr("Shut down")
                }
            ]
            current: GlobalConfig.general.powerButton
            onChosen: v => GlobalConfig.general.powerButton = v
        }

        SectionHeader {
            text: Tr.tr("Lid")
        }

        ChoiceRow {
            first: true
            last: true
            icon: "laptop_mac"
            label: Tr.tr("When closed")
            options: [
                {
                    value: "stash",
                    label: Tr.tr("Stash")
                },
                {
                    value: "sleep",
                    label: Tr.tr("Sleep")
                },
                {
                    value: "nothing",
                    label: Tr.tr("Do nothing")
                }
            ]
            current: GlobalConfig.general.lidAction
            onChosen: v => GlobalConfig.general.lidAction = v
        }

        SectionHeader {
            text: Tr.tr("Sleep")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Lock before sleeping")
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            text: Tr.tr("Stay awake while media plays")
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Stay awake while charging")
            checked: GlobalConfig.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }

        SectionHeader {
            text: Tr.tr("Battery")
        }

        StepperRow {
            first: true
            last: root.chargeLimit === 0
            label: Tr.tr("Critical level")
            subtext: Tr.tr("Percentage at which the battery counts as critical")
            value: GlobalConfig.general.battery.criticalLevel
            from: 1
            to: 30
            onMoved: v => GlobalConfig.general.battery.criticalLevel = Math.round(v)
        }

        ToggleRow {
            id: chargeLimitToggle

            visible: root.chargeLimit > 0
            last: true
            text: Tr.tr("Limit charging to 80%")
            checked: root.chargeLimit > 0 && root.chargeLimit < 100
            onToggled: {
                chargeLimitSet.command = ["sh", "-c", 'echo "$1" > "$2"', "sh", checked ? "80" : "100", root.chargeLimitPath];
                chargeLimitSet.running = true;
            }
        }
    }
}
