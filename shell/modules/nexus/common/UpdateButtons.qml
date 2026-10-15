// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components.controls
import qs.services

// Check again and Update now (UpdatesPage, UpdatesListPage)
RowLayout {
    Layout.alignment: Qt.AlignHCenter
    Layout.bottomMargin: Tokens.spacing.large
    spacing: Tokens.spacing.medium

    TextButton {
        type: TextButton.Tonal
        text: Tr.tr("Check again")
        onClicked: Updates.check()
    }

    TextButton {
        visible: Updates.pending.length > 0
        text: Tr.tr("Update now")
        onClicked: Updates.update()
    }
}
