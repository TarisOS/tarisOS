// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.modules.nexus.common

// General, one page as in the Witcher's Tweaks settings: About, Updates and Language & region, one
// after another (PageRegistry.consolidated shows this instead of the three)
PageBase {
    id: root

    title: Tr.tr("General")

    ColumnLayout {
        width: root.flickable.width
        spacing: Tokens.spacing.extraLargeIncreased

        AboutPage {
            Layout.fillWidth: true
            nState: root.nState
            embedded: true
        }

        UpdatesPage {
            Layout.fillWidth: true
            nState: root.nState
            embedded: true
        }

        LanguageAndRegion {
            Layout.fillWidth: true
            nState: root.nState
            embedded: true
        }
    }
}
