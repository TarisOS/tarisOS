// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.I18n
import qs.components.controls

// A ChoiceRow taking the menu items pages already build: the current one on the right, the
// choices in a list that opens on click.
ChoiceRow {
    id: root

    property list<MenuItem> menuItems
    property var active
    property string fallbackText
    property string fallbackIcon // Kept for pages that set it
    property bool menuOnTop // Kept for pages that set it

    signal selected(item: MenuItem)

    options: [...menuItems].map((m, i) => ({
                value: i,
                label: m.text
            }))
    current: active ? [...menuItems].indexOf(active) : -1
    placeholder: fallbackText || Tr.tr("Choose…")
    onChosen: i => {
        const item = root.menuItems[i];
        root.selected(item);
        item.clicked();
    }
}
