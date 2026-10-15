// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.launcher.services as Launcher

// Colours: light/dark mode, every scheme and flavour (or dynamic from the wallpaper), its main
// colours changed one by one (kept per scheme, Colours.colourOptions), transparency and UI scale.
PageBase {
    id: root

    // A saved theme is the current one: its scheme's own card isn't marked then
    readonly property bool customCurrent: Colours.customThemes.some(t => Colours.isCustomThemeCurrent(t))
    property string newThemeName

    readonly property var optionLabels: ({
            accent: Tr.tr("Accent"),
            highlight: Tr.tr("Highlights"),
            tertiary: Tr.tr("Third accent"),
            outline: Tr.tr("Outlines"),
            panels: Tr.tr("Taskbar & panels"),
            windows: Tr.tr("Window background"),
            windowText: Tr.tr("Window text")
        })

    function setScheme(args: list<string>): void {
        Quickshell.execDetached(["taris", "scheme", "set", ...args]);
        reloadTimer.restart();
    }

    // Picking a scheme gives the window border its colours again
    function pickScheme(args: list<string>): void {
        if (WindowStyle.style.bordertheme === "0")
            WindowStyle.save({
                bordertheme: "1"
            });
        setScheme(args);
    }

    function pickCustomTheme(theme: var): void {
        if (WindowStyle.style.bordertheme === "0")
            WindowStyle.save({
                bordertheme: "1"
            });
        Colours.applyCustomTheme(theme);
        reloadTimer.restart();
    }

    // A saved theme's swatches: its own colours, else its scheme's
    function themeSwatches(theme: var): list<color> {
        const own = Launcher.Schemes.list.find(s => s.name === theme.scheme && s.flavour === theme.flavour)?.colours ?? {};
        return ["primary", "secondary", "tertiary", "surface"].map(k => `#${theme.colours?.[k] ?? own[k] ?? "000000"}`);
    }

    title: Tr.tr("Colours")
    isSubPage: true

    Component.onCompleted: Launcher.Schemes.reload()

    property Timer _timer1: Timer {
        id: reloadTimer

        interval: 500
        onTriggered: Launcher.Schemes.reload()
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Mode")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Light mode")
            checked: Colours.currentLight
            onToggled: root.setScheme(["-m", checked ? "light" : "dark"])
        }

        SectionHeader {
            text: Tr.tr("Scheme")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(2, Math.floor(width / 170))
            columnSpacing: Tokens.spacing.small
            rowSpacing: Tokens.spacing.small

            // Saved themes first
            Repeater {
                model: Colours.customThemes

                SchemeCard {
                    required property var modelData

                    theme: modelData
                    name: modelData.scheme
                    flavour: modelData.flavour
                    label: modelData.name
                    swatches: root.themeSwatches(modelData)
                }
            }

            // Dynamic: generated from the wallpaper
            SchemeCard {
                name: "dynamic"
                flavour: "default"
                label: Tr.tr("From wallpaper")
                swatches: [Colours.palette.m3primary, Colours.palette.m3secondary, Colours.palette.m3tertiary, Colours.palette.m3surface]
            }

            Repeater {
                model: Launcher.Schemes.list.filter(s => s.name !== "dynamic")

                SchemeCard {
                    required property var modelData

                    name: modelData.name
                    flavour: modelData.flavour
                    label: `${modelData.name} ${modelData.flavour}`
                    swatches: ["primary", "secondary", "tertiary", "surface"].map(k => `#${modelData.colours[k] ?? "000000"}`)
                }
            }
        }

        // How the From wallpaper scheme builds its palette (also the launcher's >variant)
        ChoiceRow {
            Layout.topMargin: Tokens.spacing.small
            visible: Colours.scheme === "dynamic"
            first: true
            last: true
            icon: "colors"
            label: Tr.tr("Variant")
            options: Launcher.M3Variants.list.map(v => ({
                        value: v.variant,
                        label: v.name
                    }))
            current: Launcher.Schemes.currentVariant
            onChosen: v => root.setScheme(["-v", v])
        }

        SectionHeader {
            text: Tr.tr("Scheme colours")
        }

        Repeater {
            model: Colours.colourOptions

            ColourOption {}
        }

        TextButton {
            Layout.topMargin: Tokens.spacing.small
            visible: Object.keys(Colours.schemeOverrides).length > 0
            type: TextButton.Tonal
            text: Tr.tr("Reset colours")
            onClicked: Colours.resetOverrides()
        }

        RowLayout {
            Layout.topMargin: Tokens.spacing.small
            visible: Object.keys(Colours.schemeOverrides).length > 0
            spacing: Tokens.spacing.small

            TextFieldRow {
                id: themeName

                first: true
                last: true
                label: Tr.tr("Theme name")
                onValueEdited: v => root.newThemeName = v.trim()
            }

            TextButton {
                type: TextButton.Filled
                disabled: root.newThemeName.length === 0
                text: Tr.tr("Save as theme")
                onClicked: {
                    Colours.saveCustomTheme(root.newThemeName);
                    themeName.clear();
                    root.newThemeName = "";
                }
            }
        }

        SectionHeader {
            text: Tr.tr("System Transparency & Scale")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Transparency")
            checked: Tokens.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        ToggleRow {
            visible: Tokens.transparency.enabled
            text: Tr.tr("Blur behind panels")
            checked: WindowStyle.style.shellblur !== "0"
            onToggled: WindowStyle.save({
                    shellblur: checked ? "1" : "0"
                })
        }

        StepperRow {
            label: Tr.tr("Panel opacity")
            value: Tokens.transparency.base
            from: 0.3
            to: 1
            stepSize: 0.05
            onMoved: v => GlobalConfig.appearance.transparency.base = Math.round(v * 100) / 100
        }

        StepperRow {
            label: Tr.tr("Layer opacity")
            value: Tokens.transparency.layers
            from: 0
            to: 1
            stepSize: 0.05
            onMoved: v => GlobalConfig.appearance.transparency.layers = Math.round(v * 100) / 100
        }

        StepperRow {
            last: true
            label: Tr.tr("Interface scale")
            subtext: Tr.tr("Fonts, padding, spacing and rounding together")
            value: Config.appearance.font.scale
            from: 0.5
            to: 1.5
            stepSize: 0.05
            onMoved: v => {
                const s = Math.round(v * 100) / 100;
                GlobalConfig.appearance.font.scale = s;
                GlobalConfig.appearance.padding.scale = s;
                GlobalConfig.appearance.spacing.scale = s;
                GlobalConfig.appearance.rounding.scale = s;
            }
        }
    }

    // One of Colours.colourOptions: its name, a reset button once changed, and its swatch
    component ColourOption: ConnectedRect {
        id: option

        required property var modelData
        required property int index
        readonly property bool changed: {
            Colours.schemeOverrides;
            return Colours.optionChanged(modelData.id);
        }

        Layout.fillWidth: true
        first: index === 0
        last: index === Colours.colourOptions.length - 1
        implicitHeight: optionRow.implicitHeight + Tokens.padding.medium * 2

        RowLayout {
            id: optionRow

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: root.optionLabels[option.modelData.id]
                elide: Text.ElideRight
            }

            IconButton {
                visible: option.changed
                icon: "restart_alt"
                type: IconButton.Text
                onClicked: Colours.resetColourOption(option.modelData.id)
            }

            ColorWell {
                color: {
                    Colours.schemeColours;
                    Colours.current.m3surface;
                    Colours.current.m3onSurface;
                    return Colours.optionColour(option.modelData.id);
                }
                onPicked: c => Colours.setColourOption(option.modelData.id, c)
            }
        }
    }

    component SchemeCard: StyledRect {
        id: card

        required property string name
        required property string flavour
        required property string label
        required property list<color> swatches
        property var theme: null // A saved theme
        readonly property bool current: theme ? Colours.isCustomThemeCurrent(theme) : !root.customCurrent && (Launcher.Schemes.currentScheme === `${name} ${flavour}` || (name === "dynamic" && Colours.scheme === "dynamic"))

        Layout.fillWidth: true
        implicitHeight: 64
        radius: Tokens.rounding.large
        color: current ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

        StateLayer {
            radius: card.radius
            onClicked: {
                if (card.theme)
                    root.pickCustomTheme(card.theme);
                else
                    root.pickScheme(card.name === "dynamic" ? ["-n", "dynamic"] : ["-n", card.name, "-f", card.flavour]);
            }
        }

        IconButton {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.small
            visible: card.theme !== null
            icon: "delete"
            type: IconButton.Text
            onClicked: Colours.deleteCustomTheme(card.theme.name)
        }

        Row {
            id: swatchRow

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: -6

            Repeater {
                model: card.swatches

                StyledRect {
                    required property color modelData

                    implicitWidth: 20
                    implicitHeight: 20
                    radius: 10
                    color: modelData
                    border.width: 2
                    border.color: card.color
                }
            }
        }

        StyledText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.medium
            text: card.label
            elide: Text.ElideRight
            font: Tokens.font.label.medium
            color: card.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        }

        MaterialIcon {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            visible: card.current
            text: "check_circle"
            color: Colours.palette.m3primary
            fill: 1
        }
    }
}
