// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import "center"
import QtQuick
import QtQuick.Layouts
import Taris.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    required property var lock
    readonly property real centerScale: Math.min(1, (lock.screen?.height ?? 1440) / 1440)
    readonly property int centerWidth: Tokens.sizes.lock.centerWidth * centerScale

    Layout.preferredWidth: centerWidth
    Layout.fillWidth: false
    Layout.fillHeight: true

    spacing: Tokens.spacing.largeIncreased

    Clock {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.large
        centerScale: root.centerScale
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter

        text: Time.format("dddd • d MMM").toUpperCase()
        color: Colours.palette.m3onSurface
        font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
    }

    ProfilePic {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.extraExtraLarge * root.centerScale
        Layout.bottomMargin: (root.lock.pam.greeter ? Tokens.spacing.large : Tokens.spacing.extraLarge) * root.centerScale
        centerWidth: root.centerWidth
        path: root.lock.pam.facePath
    }

    // The greeter: whose account it is, with arrows to the others
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Tokens.spacing.large * root.centerScale
        visible: root.lock.pam.greeter
        spacing: Tokens.spacing.small

        IconButton {
            visible: root.lock.pam.users.length > 1
            type: IconButton.Text
            icon: "chevron_left"
            disabled: root.lock.pam.busy
            onClicked: root.lock.pam.switchUser(-1)
        }

        StyledText {
            text: root.lock.pam.userRealName
            color: Colours.palette.m3onSurface
            font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
        }

        IconButton {
            visible: root.lock.pam.users.length > 1
            type: IconButton.Text
            icon: "chevron_right"
            disabled: root.lock.pam.busy
            onClicked: root.lock.pam.switchUser(1)
        }
    }

    PasswordInput {
        Layout.alignment: Qt.AlignHCenter
        centerScale: Math.max(0.8, root.centerScale)
        centerWidth: root.centerWidth
        lock: root.lock
    }

    // Shut down, sleep and restart (and log out and stash on the lock screen) without signing in:
    // the greeter's always, before anyone has logged in, the lock screen's as Settings > Security
    // says
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        visible: root.lock.pam.greeter || GlobalConfig.lock.enableSessionControls
        spacing: Tokens.spacing.large

        SessionButton {
            visible: !root.lock.pam.greeter
            icon: Config.session.icons.logout
            command: Config.session.commands.logout
            fontScale: root.centerScale
        }
        SessionButton {
            icon: Config.session.icons.shutdown
            command: Config.session.commands.shutdown
            fontScale: root.centerScale
        }
        SessionButton {
            icon: Config.session.icons.hibernate
            command: Config.session.commands.hibernate
            fontScale: root.centerScale
        }
        SessionButton {
            visible: !root.lock.pam.greeter
            icon: Config.session.icons.stash
            command: Config.session.commands.stash
            fontScale: root.centerScale
        }
        SessionButton {
            icon: Config.session.icons.reboot
            command: Config.session.commands.reboot
            fontScale: root.centerScale
        }
    }

    StateMessage {
        Layout.fillWidth: true
        pam: root.lock.pam
    }
}
