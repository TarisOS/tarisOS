// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.Config
import Taris.I18n
import qs.components
import qs.services

// The taskbar's Tor icon's menu, laid out as the apps' tray menus are: where Tor is, a new
// identity while it's connected, and the switch (off asks for a password)
Column {
    id: root

    required property PopoutState popouts

    topPadding: Tokens.padding.small - Tokens.padding.extraSmall / 2
    bottomPadding: Tokens.padding.small
    leftPadding: Tokens.padding.small
    rightPadding: Tokens.padding.small
    spacing: Tokens.spacing.small

    StyledText {
        width: Tokens.sizes.bar.trayMenuWidth
        text: {
            if (Tor.failed)
                return Tr.tr("Tor couldn't start");
            if (Tor.connected)
                return Tor.exitAddress ? Tr.trCtx("Tor connected · %1", "the Tor exit's address").arg(Tor.exitAddress) : Tr.tr("Tor connected");
            if (Tor.connecting)
                return Tr.tr("Tor connecting...");
            return Tr.tr("Tor off");
        }
        color: Colours.palette.m3outline
        elide: Text.ElideRight
    }

    StyledRect {
        width: Tokens.sizes.bar.trayMenuWidth
        height: 1
        color: Colours.palette.m3outlineVariant
    }

    Item {
        visible: Tor.connected
        width: Tokens.sizes.bar.trayMenuWidth
        implicitHeight: identityLabel.implicitHeight

        StateLayer {
            anchors.margins: -Tokens.padding.extraSmall / 2
            anchors.leftMargin: -Tokens.padding.small
            anchors.rightMargin: -Tokens.padding.small

            radius: Tokens.rounding.full
            disabled: Tor.changing
            onClicked: {
                root.popouts.hasCurrent = false;
                Tor.newIdentity();
            }
        }

        StyledText {
            id: identityLabel

            text: Tr.tr("New identity")
            color: Tor.changing ? Colours.palette.m3outline : Colours.palette.m3onSurface
        }
    }

    Item {
        width: Tokens.sizes.bar.trayMenuWidth
        implicitHeight: label.implicitHeight

        StateLayer {
            anchors.margins: -Tokens.padding.extraSmall / 2
            anchors.leftMargin: -Tokens.padding.small
            anchors.rightMargin: -Tokens.padding.small

            radius: Tokens.rounding.full
            disabled: Tor.switching
            onClicked: {
                root.popouts.hasCurrent = false;
                Tor.toggle();
            }
        }

        StyledText {
            id: label

            text: Tor.enabled ? Tr.tr("Turn off") : Tr.tr("Turn on")
            color: Tor.switching ? Colours.palette.m3outline : Colours.palette.m3onSurface
        }
    }
}
