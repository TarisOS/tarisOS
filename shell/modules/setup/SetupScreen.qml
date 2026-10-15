// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Taris.Config
import Taris.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services

// The setup screen's steps on one screen: the wallpaper blurred behind a card, like the lock screen
Item {
    id: root

    required property ShellScreen screen
    required property SetupState setup

    readonly property list<string> titles: ["", Tr.tr("Keyboard"), Tr.tr("Wi-Fi"), Tr.tr("Time zone"), Tr.tr("Your account"), Tr.tr("Setting up")]

    // The account step's checks
    readonly property string nameError: setup.fullName.trim() && /[:,\\]/.test(setup.fullName) ? Tr.tr("No : , or \\ in the name") : ""
    readonly property string userError: setup.userNameError(setup.userName)
    readonly property string confirmError: confirmField.text && confirmField.text !== passwordField.text ? Tr.tr("The passwords don't match") : ""
    readonly property bool accountReady: setup.fullName.trim() !== "" && !nameError && setup.userName !== "" && !userError && passwordField.text !== "" && confirmField.text === passwordField.text

    function next(): void {
        if (setup.working)
            return;
        if (setup.step === SetupState.Account) {
            if (!accountReady)
                return;
            setup.password = passwordField.text;
            passwordField.text = "";
            confirmField.text = "";
            setup.finish();
        } else if (setup.step < SetupState.Account) {
            setup.step++;
        }
    }

    function back(): void {
        if (!setup.working && setup.step > SetupState.Welcome && setup.step <= SetupState.Account)
            setup.step--;
    }

    // Typing goes to the step's first field
    function focusStep(): void {
        if (setup.step === SetupState.Keyboard)
            keyboardList.searchField.forceActiveFocus();
        else if (setup.step === SetupState.TimeZone)
            zoneList.searchField.forceActiveFocus();
        else if (setup.step === SetupState.Account)
            nameField.forceActiveFocus();
        else
            card.forceActiveFocus();
    }

    Connections {
        function onStepChanged(): void {
            Qt.callLater(root.focusStep);
        }

        target: root.setup
    }

    Component.onCompleted: Qt.callLater(focusStep)

    // TarisOS's first wallpaper, as it is on the desktop
    CachingImage {
        anchors.fill: parent
        path: `${Wallpapers.builtinDir}/1.webp`
    }

    // The card's backdrop: the wallpaper behind it blurred, as Hyprland blurs behind a window (this
    // screen is one surface, so it's drawn here, at TarisOS's window style: blur size 12, 3 passes)
    StyledClippingRect {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius

        CachingImage {
            x: -parent.x
            y: -parent.y
            width: root.width
            height: root.height
            path: `${Wallpapers.builtinDir}/1.webp`

            layer.enabled: true
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1
                blurMax: 64
                blurMultiplier: 1
            }
        }
    }

    // Every step in the same card: a fixed 82% of the screen, in the middle, see-through over its
    // blurred backdrop as windows are (90% opaque)
    StyledRect {
        id: card

        anchors.centerIn: parent
        width: Math.round(parent.width * 0.82)
        height: Math.round(parent.height * 0.82)

        radius: Tokens.rounding.extraLarge * 1.5
        color: Qt.alpha(Colours.palette.m3surface, 0.9)
        focus: true

        Keys.onEscapePressed: root.back()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLargeIncreased
            spacing: Tokens.spacing.large

            // The step's title and how far along (not on the welcome)
            RowLayout {
                Layout.fillWidth: true
                visible: root.setup.step !== SetupState.Welcome
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: root.titles[root.setup.step] ?? ""
                    font: Tokens.font.headline.medium
                    elide: Text.ElideRight
                }

                // How far along
                Row {
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: 4

                        // The four steps from Keyboard (the welcome isn't one)
                        StyledRect {
                            required property int index

                            readonly property int stepIndex: root.setup.step - SetupState.Keyboard

                            implicitWidth: index === stepIndex ? Tokens.padding.large * 2 : Tokens.padding.small * 2
                            implicitHeight: Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: index <= stepIndex ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                            Behavior on implicitWidth {
                                Anim {}
                            }
                        }
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.setup.step

                // Welcome
                Item {
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: Tokens.spacing.medium

                        Logo {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.bottomMargin: Tokens.spacing.large
                            implicitWidth: Math.round(implicitHeight * 128 / 117)
                            implicitHeight: Math.min(160, Math.round(card.height * 0.25))
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Tr.tr("Welcome to TarisOS")
                            font: Tokens.font.headline.large
                            wrapMode: Text.Wrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Tr.tr("Let's get you set up")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.title.medium
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // Keyboard
                SearchList {
                    id: keyboardList

                    items: root.setup.layouts.map(l => ({
                                key: `${l.layout}:${l.variant}`,
                                label: l.name,
                                data: l
                            }))
                    current: `${root.setup.layout}:${root.setup.variant}`
                    onChosen: item => root.setup.setLayout(item.data.layout, item.data.variant)
                    onAccepted: root.next()
                }

                // Wi-Fi
                WifiStep {}

                // Time zone
                SearchList {
                    id: zoneList

                    items: root.setup.zones.map(z => ({
                                key: z,
                                label: z.replace(/_/g, " ")
                            }))
                    current: root.setup.timezone
                    onChosen: item => root.setup.timezone = item.key
                    onAccepted: root.next()
                }

                // The account
                ColumnLayout {
                    spacing: Tokens.spacing.medium

                    StyledTextField {
                        id: nameField

                        Layout.fillWidth: true
                        leadingIcon: "person"
                        placeholderText: Tr.tr("Full name")
                        text: root.setup.fullName
                        isError: root.nameError !== ""
                        errorText: root.nameError
                        onTextChanged: {
                            root.setup.fullName = text;
                            // The username follows the name until it's typed by hand
                            if (!root.setup.userNameEdited) {
                                root.setup.userName = root.setup.suggestUserName(text);
                                userField.text = root.setup.userName;
                            }
                        }
                        onAccepted: userField.forceActiveFocus()
                    }

                    StyledTextField {
                        id: userField

                        Layout.fillWidth: true
                        leadingIcon: "alternate_email"
                        placeholderText: Tr.tr("Username")
                        isError: root.userError !== ""
                        errorText: root.userError
                        onTextEdited: {
                            root.setup.userNameEdited = text !== "";
                            root.setup.userName = text;
                        }
                        onAccepted: passwordField.forceActiveFocus()
                    }

                    StyledTextField {
                        id: passwordField

                        // Shown as typed while the eye is on
                        property bool revealed

                        echoMode: revealed ? TextInput.Normal : TextInput.Password
                        trailingIcon: "visibility"
                        trailingIconClickable: true
                        trailingIconColour: revealed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        onTrailingIconClicked: revealed = !revealed

                        Layout.fillWidth: true
                        leadingIcon: "password"
                        placeholderText: Tr.tr("Password")
                        onAccepted: confirmField.forceActiveFocus()
                    }

                    StyledTextField {
                        id: confirmField

                        // Shown as typed while the eye is on
                        property bool revealed

                        echoMode: revealed ? TextInput.Normal : TextInput.Password
                        trailingIcon: "visibility"
                        trailingIconClickable: true
                        trailingIconColour: revealed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        onTrailingIconClicked: revealed = !revealed

                        Layout.fillWidth: true
                        leadingIcon: "password"
                        placeholderText: Tr.tr("Confirm password")
                        isError: root.confirmError !== ""
                        errorText: root.confirmError
                        onAccepted: root.next()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.setup.error
                        color: Colours.palette.m3error
                        font: Tokens.font.body.medium
                        wrapMode: Text.Wrap
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }

                // Setting up, then logging in
                Item {
                    LoadingIndicator {
                        anchors.centerIn: parent
                        implicitSize: Tokens.font.headline.medium.pointSize * 4
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.setup.step !== SetupState.Finishing
                spacing: Tokens.spacing.small

                TextButton {
                    visible: root.setup.step > SetupState.Welcome
                    type: TextButton.Text
                    isRound: true
                    horizontalPadding: Tokens.padding.largeIncreased
                    verticalPadding: Tokens.padding.medium
                    text: Tr.trCtx("Back", "button")
                    onClicked: root.back()
                }

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    type: TextButton.Filled
                    isRound: true
                    horizontalPadding: Tokens.padding.largeIncreased
                    verticalPadding: Tokens.padding.medium
                    disabled: root.setup.step === SetupState.Account && !root.accountReady
                    text: root.setup.step === SetupState.Account ? Tr.tr("Set up") : Tr.trCtx("Next", "button")
                    onClicked: root.next()
                }
            }
        }
    }

    // A list to pick one from, with a search field above it (Enter goes on)
    component SearchList: ColumnLayout {
        id: list

        property list<var> items: [] // { key, label }
        property string current
        readonly property alias searchField: search

        signal chosen(item: var)
        signal accepted

        spacing: Tokens.spacing.medium

        StyledTextField {
            id: search

            Layout.fillWidth: true
            leadingIcon: "search"
            placeholderText: Tr.tr("Search")
            onAccepted: {
                // Enter picks the only match, then goes on
                if (view.count === 1)
                    list.chosen(view.model.values[0]);
                list.accepted();
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            StyledListView {
                id: view

                // The current one in view when the list appears: again once it has its size and
                // shows (a step's list is made while hidden, at no height, where centring it
                // scrolls half a row too far)
                function showCurrent(): void {
                    if (search.text || height <= 0 || !visible)
                        return;
                    const i = list.items.findIndex(it => it.key === list.current);
                    if (i >= 0)
                        positionViewAtIndex(i, ListView.Center);
                }

                anchors.fill: parent
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.extraSmall / 2
                boundsBehavior: Flickable.StopAtBounds

                model: ScriptModel {
                    values: {
                        const q = search.text.trim().toLowerCase();
                        return q ? list.items.filter(i => i.label.toLowerCase().includes(q)) : list.items;
                    }
                }

                onCountChanged: showCurrent()
                onHeightChanged: showCurrent()
                onVisibleChanged: showCurrent()

                delegate: Item {
                    id: row

                    required property var modelData
                    readonly property bool isCurrent: modelData.key === list.current

                    width: view.width
                    implicitHeight: label.implicitHeight + Tokens.padding.medium * 2

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.medium
                        color: row.isCurrent ? Colours.palette.m3secondaryContainer : "transparent"
                    }

                    StateLayer {
                        radius: Tokens.rounding.medium
                        onClicked: list.chosen(row.modelData)
                    }

                    StyledText {
                        id: label

                        anchors.left: parent.left
                        anchors.right: check.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.large
                        anchors.rightMargin: Tokens.spacing.small
                        text: row.modelData.label
                        color: row.isCurrent ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        elide: Text.ElideRight
                    }

                    MaterialIcon {
                        id: check

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: Tokens.padding.large
                        text: "check"
                        visible: row.isCurrent
                        color: Colours.palette.m3onSecondaryContainer
                    }
                }
            }
        }
    }
}
