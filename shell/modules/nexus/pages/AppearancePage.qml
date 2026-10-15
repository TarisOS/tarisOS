// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.modules.nexus.common

// Appearance, one page as in the Witcher's Tweaks settings: Wallpaper & style, then Window style
// (PageRegistry.consolidated shows this instead of the two). Its sub-pages are Wallpaper & style's,
// in the same places, so that page's links to them still open them.
PageBase {
    id: root

    title: Tr.tr("Appearance")

    ColumnLayout {
        width: root.flickable.width
        spacing: Tokens.spacing.extraLargeIncreased

        WallpaperAndStyle {
            Layout.fillWidth: true
            nState: root.nState
            embedded: true
        }

        WindowStylePage {
            Layout.fillWidth: true
            nState: root.nState
            embedded: true
        }
    }
}
