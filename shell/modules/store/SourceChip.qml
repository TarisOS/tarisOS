// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.Config
import Taris.I18n
import qs.components
import qs.services

// Where an app comes from: the Arch repos, Flathub or the AUR
StyledRect {
    id: root

    required property string source

    readonly property string label: source === "flathub" ? "Flathub" : source === "aur" ? "AUR" : Tr.tr("Arch")

    implicitWidth: text.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: text.implicitHeight + Tokens.padding.extraSmall * 2
    radius: Tokens.rounding.full
    color: source === "aur" ? Colours.palette.m3tertiaryContainer : Colours.palette.m3secondaryContainer

    StyledText {
        id: text

        anchors.centerIn: parent
        text: root.label
        font: Tokens.font.label.small
        color: root.source === "aur" ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSecondaryContainer
    }
}
